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
            id: gameId,
            rawgId: 0,
            title: gameTitle,
            coverURL: gameCoverUrl,
            genres: [],
            platforms: [],
            releaseDate: nil,
            metacriticScore: nil,
            added: nil,
            rating: nil,
            gameDescription: nil,
            gameDescriptionHtml: nil,
            tags: []
        )
    }
}

// MARK: - Want to Play Manager
@MainActor
class WantToPlayManager: ObservableObject {
    static let shared = WantToPlayManager()
    
    @Published var myWantToPlayIds: Set<Int> = []
    @Published var myWantToPlayRawgIds: Set<Int> = []
    
    private let supabase = SupabaseManager.shared
    
    // MARK: - Refresh cached IDs
    func refreshMyIds() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct Row: Decodable {
                let game_id: Int
                let games: GameRawg?
                struct GameRawg: Decodable {
                    let rawg_id: Int?
                }
            }
            let rows: [Row] = try await supabase.client
                .from("want_to_play")
                .select("game_id, games(rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            myWantToPlayIds = Set(rows.map { $0.game_id })
            myWantToPlayRawgIds = Set(rows.compactMap { $0.games?.rawg_id })
        } catch {
            debugLog("❌ Error fetching want to play IDs: \(error)")
        }
    }
    
    // MARK: - Add game (unranked by default)
    func addGame(gameId: Int, gameTitle: String, gameCoverUrl: String?, source: String, sourceFriendId: String? = nil) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        guard !myWantToPlayIds.contains(gameId) else {
            debugLog("ℹ️ \(gameTitle) already in Want to Play set, skipping")
            return true
        }
        
        do {
            let localGameId = await resolveLocalGameId(rawgOrLocalId: gameId, title: gameTitle, coverUrl: gameCoverUrl)
            
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
                if localGameId != gameId {
                    myWantToPlayRawgIds.insert(gameId)
                }
                debugLog("✅ Added \(gameTitle) to Want to Play (local ID: \(localGameId))")
                
                // Post to activity feed (batched)
                await postWantToPlayFeedEntry(
                    userId: userId.uuidString,
                    gameId: localGameId,
                    gameTitle: gameTitle,
                    gameCoverUrl: gameCoverUrl
                )
                
                return true
        } catch {
                if let pgError = error as? PostgrestError, pgError.code == "23505" {
                    debugLog("ℹ️ \(gameTitle) already in Want to Play, ignoring duplicate")
                    return true
                }
                debugLog("❌ Error adding to want to play: \(error)")
                return false
            }
        }
        
    // MARK: - Post Want to Play Feed Entry
    private func postWantToPlayFeedEntry(userId: String, gameId: Int, gameTitle: String, gameCoverUrl: String?) async {
        do {
            struct WtpPostInsert: Encodable {
                let user_id: String
                let post_type: String
                let metadata: ChildMeta
                struct ChildMeta: Encodable {
                    let game_id: Int
                    let game_title: String
                    let game_cover_url: String?
                }
            }
            
            try await supabase.client
                .from("feed_posts")
                .insert(WtpPostInsert(
                    user_id: userId,
                    post_type: "want_to_play",
                    metadata: .init(
                        game_id: gameId,
                        game_title: gameTitle,
                        game_cover_url: gameCoverUrl
                    )
                ))
                .execute()
            
            debugLog("✅ Posted want_to_play feed entry for \(gameTitle)")
        } catch {
            debugLog("⚠️ Failed to post want_to_play feed entry: \(error)")
        }
    }
    
    // MARK: - Resolve Local Game ID
    /// Given an ID that might be a RAWG ID or a local games table ID,
    /// returns the local games table ID (creating the row if needed).
    private func resolveLocalGameId(rawgOrLocalId: Int, title: String, coverUrl: String?) async -> Int {
        do {
            // Check by rawg_id first — avoids collision between RAWG IDs and local DB IDs
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
            
            // Fall back to local DB ID check
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
            
            // Doesn't exist at all — create it, enriched with RAWG data
            var releaseDate: String? = nil
            var genres: [String] = []
            var metacriticScore: Int = 0
            if let cached = GameMetadataCache.shared.get(gameId: rawgOrLocalId) {
                releaseDate = cached.releaseDate
                genres = cached.curatedGenres ?? []
                metacriticScore = cached.metacriticScore ?? 0
            } else if let details = try? await RAWGService.shared.getGameDetails(id: rawgOrLocalId) {
                releaseDate = details.releaseDate
                genres = details.genres
                metacriticScore = details.metacriticScore ?? 0
            }
            
            struct NewGame: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let genres: [String]
                let tags: [String]
                let release_date: String?
                let metacritic_score: Int
            }
            
            struct InsertedGame: Decodable { let id: Int }
            
            let inserted: InsertedGame = try await supabase.client
                .from("games")
                .insert(NewGame(
                    rawg_id: rawgOrLocalId,
                    title: title,
                    cover_url: coverUrl,
                    genres: genres,
                    tags: [],
                    release_date: releaseDate,
                    metacritic_score: metacriticScore
                ))
                .select("id")
                .single()
                .execute()
                .value
            
            debugLog("📦 Created new games row for RAWG ID \(rawgOrLocalId): local ID \(inserted.id)")
            return inserted.id
            
        } catch {
            debugLog("⚠️ resolveLocalGameId failed, using original ID: \(error)")
            return rawgOrLocalId
        }
    }
    
    // MARK: - Remove game
    func removeGame(gameId: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            // Resolve RAWG ID to local game ID if needed
            var localGameId = gameId
            if !myWantToPlayIds.contains(gameId) {
                struct GameLookup: Decodable { let id: Int }
                let rows: [GameLookup] = try await supabase.client
                    .from("games")
                    .select("id")
                    .eq("rawg_id", value: gameId)
                    .limit(1)
                    .execute()
                    .value
                if let found = rows.first {
                    localGameId = found.id
                }
            }
            
            try await supabase.client
                .rpc("remove_want_to_play", params: [
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_game_id": AnyJSON.integer(localGameId)
                ])
                .execute()
                
            myWantToPlayIds.remove(localGameId)
            myWantToPlayRawgIds.remove(gameId)
                
            // Remove associated feed posts (check both local and original ID)
            await removeWantToPlayFeedPosts(userId: userId.uuidString, gameId: localGameId, rawgId: gameId != localGameId ? gameId : nil)
                
                return true
            } catch {
                debugLog("❌ Error removing from want to play: \(error)")
                return false
            }
        }
    
    // MARK: - Remove Want to Play Feed Posts
    private func removeWantToPlayFeedPosts(userId: String, gameId: Int, rawgId: Int? = nil) async {
        do {
            // Find child feed posts for this game
            struct FeedPostRow: Decodable {
                let id: String
                let batch_post_id: String?
            }
            
            let _: [FeedPostRow] = try await supabase.client
                .from("feed_posts")
                .select("id, batch_post_id")
                .eq("user_id", value: userId)
                .eq("post_type", value: "want_to_play")
                .execute()
                .value
            
            // Filter to posts matching this game_id in metadata
            // We need to check metadata->game_id
            var matchingPosts: [FeedPostRow] = try await supabase.client
                .from("feed_posts")
                .select("id, batch_post_id")
                .eq("user_id", value: userId)
                .eq("post_type", value: "want_to_play")
                .eq("metadata->>game_id", value: String(gameId))
                .execute()
                .value
            
            // Also check RAWG ID if different from local ID
            if let rawgId = rawgId, matchingPosts.isEmpty {
                matchingPosts = try await supabase.client
                    .from("feed_posts")
                    .select("id, batch_post_id")
                    .eq("user_id", value: userId)
                    .eq("post_type", value: "want_to_play")
                    .eq("metadata->>game_id", value: String(rawgId))
                    .execute()
                    .value
            }
            
            guard !matchingPosts.isEmpty else { return }
            
            let postIds = matchingPosts.map { $0.id }
            let batchParentIds = Set(matchingPosts.compactMap { $0.batch_post_id })
            
            // Delete the child posts
            try await supabase.client
                .from("feed_posts")
                .delete()
                .in("id", values: postIds)
                .execute()
            
            // For each batch parent, check if it still has children
            for batchId in batchParentIds {
                struct ChildCount: Decodable { let id: String }
                let remainingChildren: [ChildCount] = try await supabase.client
                    .from("feed_posts")
                    .select("id")
                    .eq("batch_post_id", value: batchId)
                    .limit(1)
                    .execute()
                    .value
                
                if remainingChildren.isEmpty {
                    // No children left — delete the batch parent
                    try await supabase.client
                        .from("feed_posts")
                        .delete()
                        .eq("id", value: batchId)
                        .execute()
                    
                    debugLog("🗑️ Deleted empty batch parent \(batchId)")
                } else {
                    // Update the parent's game_count
                    let newCount: [ChildCount] = try await supabase.client
                        .from("feed_posts")
                        .select("id")
                        .eq("batch_post_id", value: batchId)
                        .execute()
                        .value
                    
                    struct MetadataUpdate: Encodable {
                        let metadata: MetaPayload
                        struct MetaPayload: Encodable {
                            let game_count: Int
                        }
                    }
                    try await supabase.client
                        .from("feed_posts")
                        .update(MetadataUpdate(metadata: .init(game_count: newCount.count)))
                        .eq("id", value: batchId)
                        .execute()
                    
                    debugLog("📝 Updated batch \(batchId) game_count to \(newCount.count)")
                }
            }
            
            debugLog("🗑️ Removed \(postIds.count) want_to_play feed post(s) for game \(gameId)")
        } catch {
            debugLog("⚠️ Failed to remove want_to_play feed posts: \(error)")
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
            debugLog("❌ Error fetching want to play list: \(error)")
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
            debugLog("❌ Error fetching ranked want to play: \(error)")
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
                .order("created_at", ascending: true)
                .execute()
                .value
            
            return games
        } catch {
            debugLog("❌ Error fetching unranked want to play: \(error)")
            return []
        }
    }
    
    // MARK: - Place game at position (for head-to-head result or manual placement)
    func placeGameAtPosition(gameId: String, position: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            try await supabase.client
                .rpc("place_want_to_play_at_position", params: [
                    "p_game_id": AnyJSON.string(gameId),
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_position": AnyJSON.integer(position)
                ])
                .execute()
            
            debugLog("✅ Placed game \(gameId) at position \(position)")
            return true
        } catch {
            debugLog("❌ Error placing game: \(error)")
            return false
        }
    }
    
    // MARK: - Move game within ranked list (drag reorder)
    func moveGame(gameId: String, from oldPosition: Int, to newPosition: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        guard oldPosition != newPosition else { return true }
        
        do {
            try await supabase.client
                .rpc("move_want_to_play", params: [
                    "p_game_id": AnyJSON.string(gameId),
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_old_position": AnyJSON.integer(oldPosition),
                    "p_new_position": AnyJSON.integer(newPosition)
                ])
                .execute()
            
            return true
        } catch {
            debugLog("❌ Error moving game: \(error)")
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
            
            debugLog("✅ Unranked game \(gameId)")
            return true
        } catch {
            debugLog("❌ Error unranking game: \(error)")
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
            
            debugLog("✅ Reset all want to play rankings")
            return true
        } catch {
            debugLog("❌ Error resetting rankings: \(error)")
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
            debugLog("❌ Error fetching friend's want to play: \(error)")
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
    
    // MARK: - Remove game by RAWG ID (for post-ranking cleanup)
    func removeGameIfPresent(rawgId: Int) async {
        guard myWantToPlayRawgIds.contains(rawgId) || myWantToPlayIds.contains(rawgId) else { return }
        let success = await removeGame(gameId: rawgId)
        if success {
            debugLog("🧹 Auto-removed \(rawgId) from Want to Play after ranking")
        }
    }
}
