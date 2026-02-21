import Foundation
import Supabase
import Combine

// MARK: - Want to Play Model
struct WantToPlayGame: Identifiable, Codable {
    let id: String
    let userId: String
    let gameId: Int
    let gameTitle: String
    let gameCoverUrl: String?
    let source: String?
    let sourceFriendId: String?
    let note: String?
    let isVisible: Bool
    let createdAt: String?
    let sortPosition: Int?
    
    // For displaying source friend name (not from DB)
    var sourceFriendName: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameId = "game_id"
        case gameTitle = "game_title"
        case gameCoverUrl = "game_cover_url"
        case source
        case sourceFriendId = "source_friend_id"
        case note
        case isVisible = "is_visible"
        case createdAt = "created_at"
        case sortPosition = "sort_position"
    }
    
    /// Convert to Game for use in ComparisonView
    func toGame() -> Game {
        Game(
            from: RAWGGame(
                id: gameId,
                name: gameTitle,
                backgroundImage: gameCoverUrl,
                released: nil,
                metacritic: nil,
                genres: nil,
                platforms: nil,
                added: nil,
                rating: nil,
                descriptionRaw: nil,
                descriptionHtml: nil,
                tags: nil
            )
        )
    }
}

// MARK: - Want to Play Manager
@MainActor
class WantToPlayManager: ObservableObject {
    static let shared = WantToPlayManager()
    
    @Published var myWantToPlayIds: Set<Int> = []
    
    private let supabase = SupabaseManager.shared
    
    // MARK: - Refresh cached IDs
    func refreshMyIds() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct Row: Decodable { let game_id: Int }
            let rows: [Row] = try await supabase.client
                .from("want_to_play")
                .select("game_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            myWantToPlayIds = Set(rows.map { $0.game_id })
        } catch {
            print("❌ Error fetching want to play IDs: \(error)")
        }
    }
    
    // MARK: - Add game (unranked by default)
    func addGame(gameId: Int, gameTitle: String, gameCoverUrl: String?, source: String, sourceFriendId: String? = nil) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            let localGameId = gameId
            
            struct Insert: Encodable {
                let user_id: String
                let game_id: Int
                let game_title: String
                let game_cover_url: String?
                let source: String
                let source_friend_id: String?
            }
            
            try await supabase.client
                .from("want_to_play")
                .insert(Insert(
                    user_id: userId.uuidString,
                    game_id: localGameId,
                    game_title: gameTitle,
                    game_cover_url: gameCoverUrl,
                    source: source,
                    source_friend_id: sourceFriendId
                ))
                .execute()
            
            myWantToPlayIds.insert(localGameId)
            print("✅ Added \(gameTitle) to Want to Play (local ID: \(localGameId))")
            return true
        } catch {
            print("❌ Error adding to want to play: \(error)")
            return false
        }
    }
    
    // MARK: - Resolve Local Game ID
    /// Given an ID that might be a RAWG ID or a local games table ID,
    /// returns the local games table ID (creating the row if needed).
    private func resolveLocalGameId(rawgOrLocalId: Int, title: String, coverUrl: String?) async -> Int {
        do {
            // First check if it's already a valid local ID
            struct LocalCheck: Decodable { let id: Int }
            let localRows: [LocalCheck] = try await supabase.client
                .from("games")
                .select("id")
                .eq("id", value: rawgOrLocalId)
                .limit(1)
                .execute()
                .value
            
            if localRows.first != nil {
                return rawgOrLocalId
            }
            
            // Not a local ID — treat as RAWG ID. Check if this RAWG ID exists.
            struct RawgCheck: Decodable { let id: Int }
            let rawgRows: [RawgCheck] = try await supabase.client
                .from("games")
                .select("id")
                .eq("rawg_id", value: rawgOrLocalId)
                .limit(1)
                .execute()
                .value
            
            if let existing = rawgRows.first {
                return existing.id
            }
            
            // Doesn't exist at all — create it
            struct NewGame: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let genres: [String]
                let tags: [String]
            }
            
            struct InsertedGame: Decodable { let id: Int }
            
            let inserted: InsertedGame = try await supabase.client
                .from("games")
                .insert(NewGame(
                    rawg_id: rawgOrLocalId,
                    title: title,
                    cover_url: coverUrl,
                    genres: [],
                    tags: []
                ))
                .select("id")
                .single()
                .execute()
                .value
            
            print("📦 Created new games row for RAWG ID \(rawgOrLocalId): local ID \(inserted.id)")
            return inserted.id
            
        } catch {
            print("⚠️ resolveLocalGameId failed, using original ID: \(error)")
            return rawgOrLocalId
        }
    }
    
    // MARK: - Remove game
    func removeGame(gameId: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            // Get the game's sort_position before removing
            struct Row: Decodable { let sort_position: Int? }
            let rows: [Row] = try await supabase.client
                .from("want_to_play")
                .select("sort_position")
                .eq("user_id", value: userId.uuidString)
                .eq("game_id", value: gameId)
                .execute()
                .value
            
            let removedPosition = rows.first?.sort_position
            
            // Delete the game
            try await supabase.client
                .from("want_to_play")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("game_id", value: gameId)
                .execute()
            
            // If it was ranked, shift games below it up
            if let pos = removedPosition {
                struct GameToShift: Decodable {
                    let id: String
                    let sort_position: Int?
                }
                
                let gamesToShift: [GameToShift] = try await supabase.client
                    .from("want_to_play")
                    .select("id, sort_position")
                    .eq("user_id", value: userId.uuidString)
                    .not("sort_position", operator: .is, value: "null")
                    .gt("sort_position", value: pos)
                    .execute()
                    .value
                
                for g in gamesToShift {
                    if let sp = g.sort_position {
                        try await supabase.client
                            .from("want_to_play")
                            .update(["sort_position": sp - 1])
                            .eq("id", value: g.id)
                            .execute()
                    }
                }
            }
            
            myWantToPlayIds.remove(gameId)
            return true
        } catch {
            print("❌ Error removing from want to play: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch my list (ranked first by sort_position, then unranked by date)
    func fetchMyList() async -> [WantToPlayGame] {
        guard let userId = supabase.currentUser?.id else { return [] }
        
        do {
            let games: [WantToPlayGame] = try await supabase.client
                .from("want_to_play")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            
            return games
        } catch {
            print("❌ Error fetching want to play list: \(error)")
            return []
        }
    }
    
    // MARK: - Fetch ranked games only (sorted by sort_position)
    func fetchRankedList() async -> [WantToPlayGame] {
        guard let userId = supabase.currentUser?.id else { return [] }
        
        do {
            let games: [WantToPlayGame] = try await supabase.client
                .from("want_to_play")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .not("sort_position", operator: .is, value: "null")
                .order("sort_position", ascending: true)
                .execute()
                .value
            
            return games
        } catch {
            print("❌ Error fetching ranked want to play: \(error)")
            return []
        }
    }
    
    // MARK: - Fetch unranked games only (sorted by date)
    func fetchUnrankedList() async -> [WantToPlayGame] {
        guard let userId = supabase.currentUser?.id else { return [] }
        
        do {
            let games: [WantToPlayGame] = try await supabase.client
                .from("want_to_play")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .filter("sort_position", operator: "is", value: "null")
                .order("created_at", ascending: false)
                .execute()
                .value
            
            return games
        } catch {
            print("❌ Error fetching unranked want to play: \(error)")
            return []
        }
    }
    
    // MARK: - Place game at position (for head-to-head result or manual placement)
    func placeGameAtPosition(gameId: String, position: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            // Shift games at or below the new position down by 1
            struct GameToShift: Decodable {
                let id: String
                let sort_position: Int?
            }
            
            let gamesToShift: [GameToShift] = try await supabase.client
                .from("want_to_play")
                .select("id, sort_position")
                .eq("user_id", value: userId.uuidString)
                .not("sort_position", operator: .is, value: "null")
                .gte("sort_position", value: position)
                .order("sort_position", ascending: false)
                .execute()
                .value
            
            for g in gamesToShift {
                if let sp = g.sort_position {
                    try await supabase.client
                        .from("want_to_play")
                        .update(["sort_position": sp + 1])
                        .eq("id", value: g.id)
                        .execute()
                }
            }
            
            // Set the game's position
            try await supabase.client
                .from("want_to_play")
                .update(["sort_position": position])
                .eq("id", value: gameId)
                .execute()
            
            print("✅ Placed game at position \(position)")
            return true
        } catch {
            print("❌ Error placing game: \(error)")
            return false
        }
    }
    
    // MARK: - Move game within ranked list (drag reorder)
    func moveGame(gameId: String, from oldPosition: Int, to newPosition: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        guard oldPosition != newPosition else { return true }
        
        do {
            struct GameToShift: Decodable {
                let id: String
                let sort_position: Int?
            }
            
            if newPosition < oldPosition {
                // Moving up: shift games between newPosition and oldPosition-1 down by 1
                let gamesToShift: [GameToShift] = try await supabase.client
                    .from("want_to_play")
                    .select("id, sort_position")
                    .eq("user_id", value: userId.uuidString)
                    .not("sort_position", operator: .is, value: "null")
                    .gte("sort_position", value: newPosition)
                    .lt("sort_position", value: oldPosition)
                    .order("sort_position", ascending: false)
                    .execute()
                    .value
                
                for g in gamesToShift {
                    if let sp = g.sort_position {
                        try await supabase.client
                            .from("want_to_play")
                            .update(["sort_position": sp + 1])
                            .eq("id", value: g.id)
                            .execute()
                    }
                }
            } else {
                // Moving down: shift games between oldPosition+1 and newPosition up by 1
                let gamesToShift: [GameToShift] = try await supabase.client
                    .from("want_to_play")
                    .select("id, sort_position")
                    .eq("user_id", value: userId.uuidString)
                    .not("sort_position", operator: .is, value: "null")
                    .gt("sort_position", value: oldPosition)
                    .lte("sort_position", value: newPosition)
                    .order("sort_position", ascending: true)
                    .execute()
                    .value
                
                for g in gamesToShift {
                    if let sp = g.sort_position {
                        try await supabase.client
                            .from("want_to_play")
                            .update(["sort_position": sp - 1])
                            .eq("id", value: g.id)
                            .execute()
                    }
                }
            }
            
            // Set the moved game to new position
            try await supabase.client
                .from("want_to_play")
                .update(["sort_position": newPosition])
                .eq("id", value: gameId)
                .execute()
            
            return true
        } catch {
            print("❌ Error moving game: \(error)")
            return false
        }
    }
    
    // MARK: - Unrank a game (move back to unranked)
    func unrankGame(gameId: String) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            try await supabase.client
                .rpc("unrank_want_to_play_game", params: [
                    "p_id": gameId,
                    "p_user_id": userId.uuidString
                ])
                .execute()
            
            print("✅ Unranked game")
            return true
        } catch {
            print("❌ Error unranking game: \(error)")
            return false
        }
    }
    
    // MARK: - Reset all rankings
    func resetAllRankings() async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            try await supabase.client
                .rpc("reset_want_to_play_rankings", params: ["p_user_id": userId.uuidString])
                .execute()
            
            print("✅ Reset all want to play rankings")
            return true
        } catch {
            print("❌ Error resetting rankings: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch friend's list
    func fetchFriendList(friendId: String) async -> [WantToPlayGame] {
        do {
            let games: [WantToPlayGame] = try await supabase.client
                .from("want_to_play")
                .select("*")
                .eq("user_id", value: friendId)
                .eq("is_visible", value: true)
                .order("sort_position", ascending: true)
                .execute()
                .value
            
            return games
        } catch {
            print("❌ Error fetching friend's want to play: \(error)")
            return []
        }
    }
    
    // MARK: - Check status for a game
    func status(for gameId: Int, rankedGameIds: Set<Int>) -> GameStatus {
        if rankedGameIds.contains(gameId) {
            return .ranked
        } else if myWantToPlayIds.contains(gameId) {
            return .wantToPlay
        } else {
            return .none
        }
    }
    
    enum GameStatus {
        case ranked
        case wantToPlay
        case none
    }
}
