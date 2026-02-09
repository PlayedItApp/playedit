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
    
    // MARK: - Add game
    func addGame(gameId: Int, gameTitle: String, gameCoverUrl: String?, source: String, sourceFriendId: String? = nil) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
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
                    game_id: gameId,
                    game_title: gameTitle,
                    game_cover_url: gameCoverUrl,
                    source: source,
                    source_friend_id: sourceFriendId
                ))
                .execute()
            
            myWantToPlayIds.insert(gameId)
            print("✅ Added \(gameTitle) to Want to Play")
            return true
        } catch {
            print("❌ Error adding to want to play: \(error)")
            return false
        }
    }
    
    // MARK: - Remove game
    func removeGame(gameId: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            try await supabase.client
                .from("want_to_play")
                .delete()
                .eq("user_id", value: userId.uuidString)
                .eq("game_id", value: gameId)
                .execute()
            
            myWantToPlayIds.remove(gameId)
            return true
        } catch {
            print("❌ Error removing from want to play: \(error)")
            return false
        }
    }
    
    // MARK: - Fetch my list
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
    
    // MARK: - Fetch friend's list
    func fetchFriendList(friendId: String) async -> [WantToPlayGame] {
        do {
            let games: [WantToPlayGame] = try await supabase.client
                .from("want_to_play")
                .select("*")
                .eq("user_id", value: friendId)
                .eq("is_visible", value: true)
                .order("created_at", ascending: false)
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
