import Foundation
import Supabase

// MARK: - PSN Library Game

struct PSNLibraryGame: Identifiable, Codable {
    let titleId: String
    let name: String
    let playtimeMinutes: Int
    let platform: String
    let iconUrl: String?
    let lastPlayedAt: String?

    var id: String { titleId }

    var playtimeFormatted: String {
        let hours = playtimeMinutes / 60
        if hours > 0 {
            return "\(hours)h played"
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

// MARK: - Matched PSN Game (after RAWG matching)

struct MatchedPSNGame: Identifiable, Codable {
    let titleId: String
    let psnName: String
    let playtimeMinutes: Int
    let platform: String
    let rawgId: Int?
    let rawgTitle: String?
    let rawgCoverUrl: String?
    let rawgGenres: [String]
    let rawgPlatforms: [String]
    let rawgReleaseDate: String?
    let rawgMetacriticScore: Int?
    let matchConfidence: Int

    var id: String { titleId }

    var displayTitle: String { rawgTitle ?? psnName }
    var displayCoverUrl: String? { rawgCoverUrl }
    var isMatched: Bool { rawgId != nil }

    var playtimeFormatted: String {
        let hours = playtimeMinutes / 60
        if hours > 0 {
            return "\(hours)h played"
        } else if playtimeMinutes > 0 {
            return "\(playtimeMinutes)m played"
        } else {
            return "Never played"
        }
    }

    func toGame() -> Game {
        Game(
            from: RAWGGame(
                id: rawgId ?? 0,
                name: rawgTitle ?? psnName,
                backgroundImage: rawgCoverUrl,
                released: rawgReleaseDate,
                metacritic: rawgMetacriticScore,
                genres: rawgGenres.map { RAWGGenre(id: 0, name: $0) },
                platforms: rawgPlatforms.map {
                    RAWGPlatformWrapper(platform: RAWGPlatform(id: 0, name: $0))
                },
                added: nil,
                rating: nil,
                descriptionRaw: nil,
                descriptionHtml: nil,
                tags: nil
            )
        )
    }
}

// MARK: - PSN Service

class PSNService {
    static let shared = PSNService()

    private let baseURL = Config.supabaseURL

    // MARK: - Get user JWT

    private func userJWT() async throws -> String {
        do {
            let session = try await SupabaseManager.shared.client.auth.refreshSession()
            debugLog("🔑 Got refreshed session for user: \(session.user.id)")
            return session.accessToken
        } catch {
            debugLog("⚠️ Session refresh failed, falling back to current session: \(error)")
            let session = try await SupabaseManager.shared.client.auth.session
            return session.accessToken
        }
    }

    // MARK: - Authenticated URL request helper

    private func authedRequest(url: URL, body: [String: Any]) async throws -> URLRequest {
        let jwt = try await userJWT()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Exchange NPSSO for access token + save psn_id

    func authenticate(npsso: String) async throws -> PSNAuthResult {
        let url = URL(string: "\(baseURL)/functions/v1/psn-auth")!
        debugLog("🔑 psn-auth URL: \(url.absoluteString)")
        let jwt = try await userJWT()
        debugLog("🔑 JWT prefix: \(String(jwt.prefix(20)))")
        debugLog("🔑 JWT length: \(jwt.count)")
        let request = try await authedRequest(url: url, body: ["npsso": npsso])
        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let rawBody = String(data: data, encoding: .utf8) ?? "no body"
            debugLog("❌ psn-auth failed [\(http.statusCode)]: \(rawBody)")
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw PSNError.authFailed(msg ?? "Unknown error")
        }

        struct AuthResponse: Decodable {
            let accessToken: String
            let psnAccountId: String
            let psnOnlineId: String?
        }

        let result = try JSONDecoder().decode(AuthResponse.self, from: data)
        debugLog("✅ PSN auth success — accountId: \(result.psnAccountId), onlineId: \(result.psnOnlineId ?? "nil")")
        return PSNAuthResult(
            accessToken: result.accessToken,
            psnAccountId: result.psnAccountId,
            psnOnlineId: result.psnOnlineId
        )
    }

    // MARK: - Fetch PSN library

    func fetchLibrary(accessToken: String, psnAccountId: String) async throws -> [PSNLibraryGame] {
        let url = URL(string: "\(baseURL)/functions/v1/psn-games")!
        let request = try await authedRequest(url: url, body: [
            "accessToken": accessToken,
            "psnAccountId": psnAccountId
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        let rawBody = String(data: data, encoding: .utf8) ?? "no body"
            debugLog("📦 psn-games response: \(rawBody.prefix(500))")

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                throw PSNError.fetchFailed(msg ?? "Unknown error")
            }

        struct LibraryResponse: Decodable {
            let games: [PSNLibraryGame]
            let totalCount: Int
        }

        let result = try JSONDecoder().decode(LibraryResponse.self, from: data)
        debugLog("📦 psn-games totalCount: \(result.totalCount), games returned: \(result.games.count)")
        return result.games
    }

    // MARK: - Match games against RAWG (batched, mirrors SteamService)

    func matchGames(
        games: [PSNLibraryGame],
        progressCallback: @escaping (Int, Int) -> Void
    ) async throws -> [MatchedPSNGame] {
        var allMatches: [MatchedPSNGame] = []
        let batchSize = 5
        let batches = stride(from: 0, to: games.count, by: batchSize).map {
            Array(games[$0..<min($0 + batchSize, games.count)])
        }

        let url = URL(string: "\(baseURL)/functions/v1/steam-games")!

        for (batchIndex, batch) in batches.enumerated() {
            // Reuse the steam-games match_rawg action — it only needs name + appid shape
            let appIds = batch.map { game -> [String: Any] in
                [
                    // Use titleId hash as a stable numeric stand-in for appid
                    "appid": abs(game.titleId.hashValue % 1_000_000),
                    "name": game.name,
                    "playtimeMinutes": game.playtimeMinutes
                ]
            }

            var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
                request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
                request.timeoutInterval = 60
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "action": "match_rawg",
                    "appIds": appIds
                ])

            let (data, response) = try await URLSession.shared.data(for: request)

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let rawBody = String(data: data, encoding: .utf8) ?? "no body"
            debugLog("🎮 PSN matchGames batch \(batchIndex) [\(statusCode)]: \(rawBody.prefix(800))")

            guard statusCode == 200 else {
                throw PSNError.fetchFailed("steam-games returned \(statusCode): \(rawBody.prefix(200))")
            }

            struct RawMatch: Decodable {
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
            }

            struct MatchResponse: Decodable {
                let matches: [RawMatch]
            }

            let result = try JSONDecoder().decode(MatchResponse.self, from: data)

            // Re-associate with the original PSN game to restore titleId + platform
            for (index, raw) in result.matches.enumerated() {
                guard let original = batch[safe: index] else { continue }
                allMatches.append(MatchedPSNGame(
                    titleId: original.titleId,
                    psnName: original.name,
                    playtimeMinutes: original.playtimeMinutes,
                    platform: original.platform,
                    rawgId: raw.rawgId,
                    rawgTitle: raw.rawgTitle,
                    rawgCoverUrl: raw.rawgCoverUrl,
                    rawgGenres: raw.rawgGenres,
                    rawgPlatforms: raw.rawgPlatforms,
                    rawgReleaseDate: raw.rawgReleaseDate,
                    rawgMetacriticScore: raw.rawgMetacriticScore,
                    matchConfidence: raw.matchConfidence
                ))
            }

            let completed = min((batchIndex + 1) * batchSize, games.count)
            await MainActor.run { progressCallback(completed, games.count) }
        }

        return allMatches
    }

    // MARK: - Check if PSN is connected

    func getPSNId() async -> String? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        do {
            struct UserRow: Decodable { let psn_id: String? }
            let row: UserRow = try await SupabaseManager.shared.client
                .from("users")
                .select("psn_id")
                .eq("id", value: userId.uuidString.lowercased())
                .single()
                .execute()
                .value
            return row.psn_id
        } catch {
            debugLog("❌ Error checking PSN ID: \(error)")
            return nil
        }
    }

    // MARK: - Disconnect PSN

    func disconnect() async -> Bool {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return false }
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .update(["psn_id": nil as String?, "psn_connected_at": nil as String?] as [String: String?])
                .eq("id", value: userId.uuidString.lowercased())
                .execute()
            return true
        } catch {
            debugLog("❌ Error disconnecting PSN: \(error)")
            return false
        }
    }
}

// MARK: - Supporting types

struct PSNAuthResult {
    let accessToken: String
    let psnAccountId: String
    let psnOnlineId: String?
}

enum PSNError: LocalizedError {
    case authFailed(String)
    case fetchFailed(String)
    case noGames

    var errorDescription: String? {
        switch self {
        case .authFailed(let msg): return "PlayStation login failed: \(msg)"
        case .fetchFailed(let msg): return "Couldn't load your PSN library: \(msg)"
        case .noGames: return "No played games found on your PSN account."
        }
    }
}
