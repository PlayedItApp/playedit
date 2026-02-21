import Foundation
import Auth
import Supabase

// MARK: - Steam Library Game
struct SteamLibraryGame: Identifiable, Codable {
    let appid: Int
    let name: String
    let playtimeMinutes: Int
    let iconUrl: String?
    
    var id: Int { appid }
    
    var playtimeFormatted: String {
        let hours = playtimeMinutes / 60
        if hours > 0 {
            return "\(hours) hours"
        } else if playtimeMinutes > 0 {
            return "\(playtimeMinutes)m played"
        } else {
            return "Never played"
        }
    }
    
    var isSubstantialPlaytime: Bool {
        playtimeMinutes >= 60
    }
}

// MARK: - Matched Steam Game (after RAWG matching)
struct MatchedSteamGame: Identifiable, Codable {
    let steamAppId: Int
    let steamName: String
    let playtimeMinutes: Int
    let rawgId: Int?
    let rawgTitle: String?
    let rawgCoverUrl: String?
    let rawgGenres: [String]
    let rawgPlatforms: [String]
    let rawgReleaseDate: String?
    let rawgMetacriticScore: Int?
    let matchConfidence: Int
    
    var id: Int { steamAppId }
    
    var displayTitle: String { rawgTitle ?? steamName }
    var displayCoverUrl: String? { rawgCoverUrl }
    var isMatched: Bool { rawgId != nil }
    
    var playtimeFormatted: String {
        let hours = playtimeMinutes / 60
        if hours > 0 {
            return "\(hours) hours"
        } else if playtimeMinutes > 0 {
            return "\(playtimeMinutes)m played"
        } else {
            return "Never played"
        }
    }
    
    /// Convert to Game for use in ComparisonView / saving
    func toGame() -> Game {
        Game(
            from: RAWGGame(
                id: rawgId ?? steamAppId,
                name: rawgTitle ?? steamName,
                backgroundImage: rawgCoverUrl,
                released: rawgReleaseDate,
                metacritic: rawgMetacriticScore,
                genres: rawgGenres.map { RAWGGenre(id: 0, name: $0) },
                platforms: rawgPlatforms.map { RAWGPlatformWrapper(platform: RAWGPlatform(id: 0, name: $0)) },
                added: nil,
                rating: nil,
                descriptionRaw: nil,
                descriptionHtml: nil,
                tags: nil
            )
        )
    }
}

// MARK: - Steam Service
class SteamService {
    static let shared = SteamService()
    
    private let baseURL = Config.supabaseURL
    
    // MARK: - Get Steam Login URL
    func getLoginURL(userId: String) async throws -> String {
        let url = URL(string: "\(baseURL)/functions/v1/steam-auth")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: String] = [
            "action": "get_login_url",
            "userId": userId
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode([String: String].self, from: data)
        
        guard let loginUrl = result["url"] else {
            throw SteamError.noLoginURL
        }
        
        return loginUrl
    }
    
    // MARK: - Validate Steam OpenID Response
    func validateOpenID(params: [String: String], userId: String) async throws -> String {
        let url = URL(string: "https://api.playedit.app")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: Any] = [
            "action": "validate",
            "params": params,
            "userId": userId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let result = try? JSONDecoder().decode([String: String].self, from: data),
           let steamId = result["steamId"] {
            return steamId
        }
        
        throw SteamError.validationFailed
    }
    
    // MARK: - Fetch Steam Library
    func fetchLibrary(steamId: String) async throws -> [SteamLibraryGame] {
        let url = URL(string: "\(baseURL)/functions/v1/steam-games")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        
        let body: [String: String] = [
            "action": "fetch_library",
            "steamId": steamId
        ]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        struct LibraryResponse: Codable {
            let gameCount: Int?
            let games: [SteamLibraryGame]?
            let error: String?
            let message: String?
        }
        
        let result = try JSONDecoder().decode(LibraryResponse.self, from: data)
        
        if result.error == "empty_library" {
            throw SteamError.privateProfile
        }
        
        return result.games ?? []
    }
    
    // MARK: - Match Games Against RAWG (batched)
    func matchGames(games: [SteamLibraryGame], progressCallback: @escaping (Int, Int) -> Void) async throws -> [MatchedSteamGame] {
        var allMatches: [MatchedSteamGame] = []
        let batchSize = 5
        let batches = stride(from: 0, to: games.count, by: batchSize).map {
            Array(games[$0..<min($0 + batchSize, games.count)])
        }
        
        for (batchIndex, batch) in batches.enumerated() {
            let url = URL(string: "\(baseURL)/functions/v1/steam-games")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.timeoutInterval = 60
            
            let appIds = batch.map { game -> [String: Any] in
                [
                    "appid": game.appid,
                    "name": game.name,
                    "playtimeMinutes": game.playtimeMinutes
                ]
            }
            
            let body: [String: Any] = [
                "action": "match_rawg",
                "appIds": appIds
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            struct MatchResponse: Codable {
                let matches: [MatchedSteamGame]
            }
            
            let result = try JSONDecoder().decode(MatchResponse.self, from: data)
            allMatches.append(contentsOf: result.matches)
            
            let completed = min((batchIndex + 1) * batchSize, games.count)
            await MainActor.run {
                progressCallback(completed, games.count)
            }
        }
        
        return allMatches
    }
    
    // MARK: - Check if Steam is Connected
    func getSteamId() async -> String? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            struct UserRow: Decodable { let steam_id: String? }
            let row: UserRow = try await SupabaseManager.shared.client
                .from("users")
                .select("steam_id")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            return row.steam_id
        } catch {
            print("❌ Error checking Steam ID: \(error)")
            return nil
        }
    }
    
    // MARK: - Disconnect Steam
    func disconnect() async -> Bool {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return false }
        
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .update(["steam_id": nil as String?, "steam_connected_at": nil as String?] as [String: String?])
                .eq("id", value: userId.uuidString)
                .execute()
            return true
        } catch {
            print("❌ Error disconnecting Steam: \(error)")
            return false
        }
    }
}

// MARK: - Steam Errors
enum SteamError: LocalizedError {
    case noLoginURL
    case validationFailed
    case privateProfile
    case fetchFailed
    
    var errorDescription: String? {
        switch self {
        case .noLoginURL: return "Couldn't connect to Steam. Try again?"
        case .validationFailed: return "Steam login failed. Try again?"
        case .privateProfile: return "Your Steam profile game details are set to private. Set them to Public in Steam's privacy settings to import."
        case .fetchFailed: return "Couldn't load your Steam library. Check your connection and try again?"
        }
    }
}
