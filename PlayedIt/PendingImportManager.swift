import Foundation
import Supabase

struct PendingImportGame: Codable {
    let rawgId: Int
    let title: String
    let coverUrl: String?
    let genres: [String]
    let platforms: [String]
    let releaseDate: String?
    let metacriticScore: Int?
    let sourceMetadata: [String: String]
    
    enum CodingKeys: String, CodingKey {
        case rawgId = "rawg_id"
        case title
        case coverUrl = "cover_url"
        case genres, platforms
        case releaseDate = "release_date"
        case metacriticScore = "metacritic_score"
        case sourceMetadata = "source_metadata"
    }
    
    func toGame() -> Game {
        Game(
            id: rawgId,
            rawgId: rawgId,
            title: title,
            coverURL: coverUrl,
            genres: genres,
            platforms: platforms,
            releaseDate: releaseDate,
            metacriticScore: metacriticScore,
            added: nil,
            rating: nil,
            gameDescription: nil,
            gameDescriptionHtml: nil,
            tags: []
        )
    }
}

struct PendingImport: Codable {
    let id: String
    let userId: String
    let source: String
    let games: [PendingImportGame]
    let currentIndex: Int
    let totalCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case source
        case games
        case currentIndex = "current_index"
        case totalCount = "total_count"
    }
}

class PendingImportManager {
    static let shared = PendingImportManager()
    private init() {}
    
    func save(source: String, games: [PendingImportGame], currentIndex: Int) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            let encoder = JSONEncoder()
            let gamesData = try encoder.encode(games)
            let gamesJSON = String(data: gamesData, encoding: .utf8) ?? "[]"
            
            struct PendingInsert: Encodable {
                let user_id: String
                let source: String
                let games: AnyJSON
                let current_index: Int
                let total_count: Int
                let updated_at: String
            }
            
            let insert = PendingInsert(
                user_id: userId.uuidString,
                source: source,
                games: .string(gamesJSON),
                current_index: currentIndex,
                total_count: games.count,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            
            try await SupabaseManager.shared.client
                .from("pending_imports")
                .upsert(insert, onConflict: "user_id, source")
                .execute()
            
            debugLog("💾 Saved pending import: \(source), index \(currentIndex)/\(games.count)")
        } catch {
            debugLog("❌ Error saving pending import: \(error)")
        }
    }
    
    func updateIndex(source: String, currentIndex: Int) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.client
                .from("pending_imports")
                .update([
                    "current_index": AnyJSON.integer(currentIndex),
                    "updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
                ])
                .eq("user_id", value: userId.uuidString)
                .eq("source", value: source)
                .execute()
        } catch {
            debugLog("❌ Error updating pending import index: \(error)")
        }
    }
    
    func fetch(source: String) async -> PendingImport? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            struct RawRow: Decodable {
                let id: String
                let user_id: String
                let source: String
                let games: String
                let current_index: Int
                let total_count: Int
            }
            
            let row: RawRow = try await SupabaseManager.shared.client
                .from("pending_imports")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("source", value: source)
                .single()
                .execute()
                .value
            
            guard let gamesData = row.games.data(using: .utf8) else { return nil }
            let games = try JSONDecoder().decode([PendingImportGame].self, from: gamesData)
            
            return PendingImport(
                id: row.id,
                userId: row.user_id,
                source: row.source,
                games: games,
                currentIndex: row.current_index,
                totalCount: row.total_count
            )
        } catch {
            debugLog("📭 No pending import for \(source)")
            return nil
        }
    }
    
    func fetchAny() async -> PendingImport? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            struct RawRow: Decodable {
                let id: String
                let user_id: String
                let source: String
                let games: String
                let current_index: Int
                let total_count: Int
            }
            
            let rows: [RawRow] = try await SupabaseManager.shared.client
                .from("pending_imports")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("updated_at", ascending: false)
                .limit(1)
                .execute()
                .value
            
            guard let row = rows.first,
                  let gamesData = row.games.data(using: .utf8) else { return nil }
            let games = try JSONDecoder().decode([PendingImportGame].self, from: gamesData)
            
            return PendingImport(
                id: row.id,
                userId: row.user_id,
                source: row.source,
                games: games,
                currentIndex: row.current_index,
                totalCount: row.total_count
            )
        } catch {
            return nil
        }
    }
    
    func delete(source: String) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            try await SupabaseManager.shared.client
                .from("pending_imports")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("source", value: source)
                .execute()
            
            debugLog("🗑️ Deleted pending import: \(source)")
        } catch {
            debugLog("❌ Error deleting pending import: \(error)")
        }
    }
}
