import SwiftUI
import Supabase

struct DeepLinkGameView: View {
    let gameId: Int  // RAWG ID from the deep link
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isLoading = true
    @State private var gameNotFound = false
    @State private var gameTitle: String = ""
    @State private var gameCoverURL: String? = nil
    @State private var gameReleaseDate: String? = nil
    @State private var gameDescription: String? = nil
    @State private var metacriticScore: Int? = nil
    @State private var localGameId: Int? = nil
    @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?)] = []
    @State private var myUserGame: UserGame? = nil
    @State private var showLogGame = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
            } else if gameNotFound {
                notFoundView
            } else {
                gameContentView
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !gameNotFound && !isLoading {
                    Button {
                        Task {
                            await GameShareService.shared.shareGame(
                                gameTitle: gameTitle,
                                coverURL: gameCoverURL,
                                gameId: gameId
                            )
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.primaryBlue)
                    }
                }
            }
        }
        .task {
            await loadGame()
        }
        .sheet(isPresented: $showLogGame, onDismiss: {
            Task { await refreshMyGame() }
        }) {
            GameLogView(game: Game(
                id: gameId,
                rawgId: gameId,
                title: gameTitle,
                coverURL: gameCoverURL,
                genres: [],
                platforms: [],
                releaseDate: gameReleaseDate,
                metacriticScore: metacriticScore,
                added: nil,
                rating: nil,
                gameDescription: gameDescription,
                tags: []
            ))
        }
    }
    
    // MARK: - Not Found
    private var notFoundView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("Game not found")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Couldn't find this game. The link might be outdated.")
                .font(.subheadline)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Game Content
    private var gameContentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                GameInfoHeroView(
                    title: gameTitle,
                    coverURL: gameCoverURL,
                    releaseDate: gameReleaseDate,
                    metacriticScore: metacriticScore,
                    gameDescription: gameDescription
                )
                .padding(.top, 20)
                
                // My ranking or CTA
                if let myGame = myUserGame {
                    Text("You ranked this #\(myGame.rankPosition)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(myGame.rankPosition <= 3 ? .accentOrange : .primaryBlue)
                } else {
                    VStack(spacing: 16) {
                        Text("You haven't ranked this yet")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        Text("See where it lands on your list")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                        
                        Button {
                            showLogGame = true
                        } label: {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text("Rank This Game")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color.primaryBlue.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primaryBlue.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }
                
                // Friend rankings
                if !friendRankings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How friends ranked this")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        VStack(spacing: 0) {
                            ForEach(Array(friendRankings.enumerated()), id: \.offset) { index, ranking in
                                HStack(spacing: 12) {
                                    if let avatarURL = ranking.avatarURL, let url = URL(string: avatarURL) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            initialsCircle(ranking.username, size: 32)
                                        }
                                        .frame(width: 32, height: 32)
                                        .clipShape(Circle())
                                    } else {
                                        initialsCircle(ranking.username, size: 32)
                                    }
                                    
                                    Text(ranking.username)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                    
                                    Spacer()
                                    
                                    Text("#\(ranking.rank)")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(ranking.rank <= 3 ? .accentOrange : .primaryBlue)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                
                                if index < friendRankings.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .background(Color.cardBackground)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    }
                    .padding(.horizontal, 16)
                }
                
                Spacer(minLength: 40)
            }
            .padding(.vertical, 16)
        }
    }
    
    // MARK: - Helpers
    
    private func initialsCircle(_ name: String, size: CGFloat) -> some View {
        Circle()
            .fill(Color.primaryBlue.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.primaryBlue)
            )
    }
    
    // MARK: - Load Game
    private func loadGame() async {
        do {
            // 1. Look up game in our DB by rawg_id
            struct GameRow: Decodable {
                let id: Int
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let release_date: String?
                let description: String?
                let metacritic_score: Int?
            }
            
            let gameRows: [GameRow] = try await supabase.client
                .from("games")
                .select("id, rawg_id, title, cover_url, release_date, description, metacritic_score")
                .eq("rawg_id", value: gameId)
                .limit(1)
                .execute()
                .value
            
            // 2. If not in DB, try fetching from RAWG
            if gameRows.isEmpty {
                do {
                    let details = try await RAWGService.shared.getGameDetails(id: gameId)
                    gameTitle = details.title
                    gameCoverURL = details.coverURL
                    gameReleaseDate = details.releaseDate
                    gameDescription = details.gameDescription ?? details.gameDescriptionHtml
                    metacriticScore = details.metacriticScore
                } catch {
                    debugLog("❌ RAWG lookup failed for gameId \(gameId): \(error)")
                    gameNotFound = true
                    isLoading = false
                    return
                }
                
                isLoading = false
                async let f: () = fetchFriendRankings()
                async let m: () = fetchMyGame()
                _ = await (f, m)
                return
            }
            
            let game = gameRows[0]
            localGameId = game.id
            gameTitle = game.title
            gameCoverURL = game.cover_url
            gameReleaseDate = game.release_date
            metacriticScore = game.metacritic_score
            
            // 3. Fetch description if not cached
            if let desc = game.description, !desc.isEmpty {
                gameDescription = desc
            } else {
                do {
                    let details = try await RAWGService.shared.getGameDetails(id: gameId)
                    gameDescription = details.gameDescription ?? details.gameDescriptionHtml
                    
                    if let desc = gameDescription, !desc.isEmpty {
                        _ = try? await supabase.client
                            .from("games")
                            .update(["description": desc])
                            .eq("rawg_id", value: gameId)
                            .execute()
                    }
                } catch {
                    debugLog("⚠️ Could not fetch RAWG description: \(error)")
                }
            }
            
            isLoading = false
            async let f: () = fetchFriendRankings()
            async let m: () = fetchMyGame()
            _ = await (f, m)
            
        } catch {
            debugLog("❌ Error loading game: \(error)")
            gameNotFound = true
            isLoading = false
        }
    }
    
    // MARK: - Fetch Friend Rankings
    private func fetchFriendRankings() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct FriendshipRow: Decodable {
                let user_id: String
                let friend_id: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("user_id, friend_id")
                .eq("status", value: "accepted")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .execute()
                .value
            
            let friendIds = friendships.map { f in
                f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
            }
            
            guard !friendIds.isEmpty else { return }
            
            struct RankingRow: Decodable {
                let user_id: String
                let rank_position: Int
                let game_id: Int
                let canonical_game_id: Int?
            }
            
            // Search by rawg_id — need to find matching game_ids first
            let allUserIds = friendIds + [userId.uuidString]
            
            var rankings: [RankingRow] = []
            
            if let localId = localGameId {
                rankings = try await supabase.client
                    .from("user_games")
                    .select("user_id, rank_position, game_id, canonical_game_id")
                    .in("user_id", values: allUserIds)
                    .or("game_id.eq.\(localId),canonical_game_id.eq.\(localId)")
                    .not("rank_position", operator: .is, value: "null")
                    .order("rank_position", ascending: true)
                    .execute()
                    .value
            }
            
            guard !rankings.isEmpty else { return }
            
            let rankedUserIds = Array(Set(rankings.map { $0.user_id }))
            
            struct UserInfo: Decodable {
                let id: String
                let username: String?
                let avatar_url: String?
            }
            
            let users: [UserInfo] = try await supabase.client
                .from("users")
                .select("id, username, avatar_url")
                .in("id", values: rankedUserIds)
                .execute()
                .value
            
            let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id.lowercased(), $0) })
            
            var results: [(username: String, rank: Int, avatarURL: String?)] = []
            
            for ranking in rankings {
                if let user = userMap[ranking.user_id.lowercased()] {
                    let displayName = ranking.user_id.lowercased() == userId.uuidString.lowercased()
                        ? "You"
                        : (user.username ?? "Unknown")
                    results.append((username: displayName, rank: ranking.rank_position, avatarURL: user.avatar_url))
                }
            }
            
            friendRankings = results.sorted { a, b in
                if a.username == "You" { return true }
                if b.username == "You" { return false }
                return a.rank < b.rank
            }
            
        } catch {
            debugLog("❌ Error fetching friend rankings: \(error)")
        }
    }
    
    // MARK: - Fetch My Game
    private func fetchMyGame() async {
        guard let userId = supabase.currentUser?.id, let localId = localGameId else { return }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let canonical_game_id: Int?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                    let rawg_id: Int?
                }
            }
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .or("game_id.eq.\(localId),canonical_game_id.eq.\(localId)")
                .not("rank_position", operator: .is, value: "null")
                .limit(1)
                .execute()
                .value
            
            if let row = rows.first {
                myUserGame = UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    canonicalGameId: row.canonical_game_id,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date,
                    gameRawgId: row.games.rawg_id
                )
            }
        } catch {
            debugLog("❌ Error fetching my game: \(error)")
        }
    }
    
    // MARK: - Refresh after logging
    private func refreshMyGame() async {
        await fetchMyGame()
        await fetchFriendRankings()
    }
}
