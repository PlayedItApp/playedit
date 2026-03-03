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
    @State private var curatedGenres: [String]? = nil
    @State private var curatedTags: [String]? = nil
    @State private var curatedPlatforms: [String]? = nil
    @State private var curatedReleaseYear: Int? = nil
    @State private var localGameId: Int? = nil
    @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
    @State private var myUserGame: UserGame? = nil
    @State private var showLogGame = false
    @State private var prediction: GamePrediction? = nil
    @State private var myGameCount: Int = 0
    
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
            ), source: "deep_link")
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
                    releaseDate: curatedReleaseYear.map { String($0) } ?? gameReleaseDate,
                    metacriticScore: metacriticScore,
                    gameDescription: gameDescription,
                    curatedGenres: curatedGenres,
                    curatedTags: curatedTags,
curatedPlatforms: curatedPlatforms
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
                        
                        if let pred = prediction, myGameCount > 0 {
                            let range = pred.estimatedRank(inListOf: myGameCount)
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(pred.emoji)
                                    Text("PlayedIt Prediction: \(pred.summaryText)")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                }
                                
                                Text("Estimated rank: ~#\(range.lower)-\(range.upper)")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                                
                                HStack(spacing: 4) {
                                    Text(pred.confidenceDots)
                                        .font(.system(size: 12))
                                        .foregroundColor(.primaryBlue)
                                    Text(pred.confidenceLabel)
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                }
                                
                                if !pred.friendSignals.isEmpty {
                                    let names = pred.friendSignals.map { $0.friendName }.joined(separator: ", ")
                                    Text("Based on \(names)'s rankings & your taste")
                                        .font(.system(size: 12, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.primaryBlue.opacity(0.08))
                            .cornerRadius(10)
                        } else {
                            Text("See where it lands on your list")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                        }
                        
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
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ranking.username)
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.adaptiveSlate)
                                        
                                        if ranking.username != "You",
                                           friendRankings.filter({ $0.username != "You" }).count >= 2,
                                           ranking.tasteMatch == friendRankings.filter({ $0.username != "You" }).map({ $0.tasteMatch }).max(),
                                           ranking.tasteMatch >= 50 {
                                            Text("Closest taste · \(ranking.tasteMatch)%")
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(.teal)
                                        }
                                    }
                                    
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
            // 1. Check in-memory cache first
            if let cached = GameMetadataCache.shared.get(gameId: gameId) {
                gameDescription = cached.description
                metacriticScore = cached.metacriticScore
                curatedGenres = cached.curatedGenres
                curatedTags = cached.curatedTags
                curatedPlatforms = cached.curatedPlatforms
                curatedReleaseYear = cached.curatedReleaseYear
            }
            
            // 2. Look up game in our DB by rawg_id
            struct GameRow: Decodable {
                let id: Int
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let release_date: String?
                let description: String?
                let curated_description: String?
                let metacritic_score: Int?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let curated_platforms: [String]?
                let curated_release_year: Int?
            }
            
            let gameRows: [GameRow] = try await supabase.client
                .from("games")
                .select("id, rawg_id, title, cover_url, release_date, description, curated_description, metacritic_score, curated_genres, curated_tags, curated_platforms, curated_release_year")
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
            curatedGenres = game.curated_genres
            curatedTags = game.curated_tags
            curatedPlatforms = game.curated_platforms
            curatedReleaseYear = game.curated_release_year
            
            // Cache the metadata
            let resolvedDesc = game.curated_description ?? game.description
            if resolvedDesc != nil || game.metacritic_score != nil {
                GameMetadataCache.shared.set(gameId: gameId, description: resolvedDesc, metacriticScore: game.metacritic_score, releaseDate: game.release_date, curatedGenres: game.curated_genres, curatedTags: game.curated_tags, curatedPlatforms: game.curated_platforms, curatedReleaseYear: game.curated_release_year)
            }
            
            // 3. Fetch description if not cached
            if let desc = game.curated_description ?? game.description, !desc.isEmpty {
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
            async let p: () = fetchPredictionIfNeeded()
            _ = await (f, m, p)
            
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
            
            // Fetch my games for taste match
            struct MyGameRow: Decodable {
                let game_id: Int
                let rank_position: Int
                let canonical_game_id: Int?
            }
            let myGameRows: [MyGameRow] = try await supabase.client
                .from("user_games")
                .select("game_id, rank_position, canonical_game_id")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            let myMapped = myGameRows.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
            
            let rankedFriendIds = Array(Set(rankings.map { $0.user_id })).filter { $0.lowercased() != userId.uuidString.lowercased() }
            var friendGameCache: [String: [(canonicalId: Int, rank: Int)]] = [:]
            for friendId in rankedFriendIds {
                let fGames: [MyGameRow] = try await supabase.client
                    .from("user_games")
                    .select("game_id, rank_position, canonical_game_id")
                    .eq("user_id", value: friendId)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .value
                friendGameCache[friendId.lowercased()] = fGames.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
            }
            
            var results: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
            
            for ranking in rankings {
                if let user = userMap[ranking.user_id.lowercased()] {
                    let displayName: String
                    let tm: Int
                    if ranking.user_id.lowercased() == userId.uuidString.lowercased() {
                        displayName = "You"
                        tm = 100
                    } else {
                        displayName = user.username ?? "Unknown"
                        let theirMapped = friendGameCache[ranking.user_id.lowercased()] ?? []
                        tm = quickTasteMatch(myGames: myMapped, theirGames: theirMapped)
                    }
                    results.append((username: displayName, rank: ranking.rank_position, avatarURL: user.avatar_url, tasteMatch: tm))
                }
            }
            
            friendRankings = results.sorted { $0.rank < $1.rank }
            
        } catch {
            debugLog("❌ Error fetching friend rankings: \(error)")
        }
    }
    
    private func quickTasteMatch(myGames: [(canonicalId: Int, rank: Int)], theirGames: [(canonicalId: Int, rank: Int)]) -> Int {
        let theirDict = Dictionary(theirGames.map { ($0.canonicalId, $0.rank) }, uniquingKeysWith: { first, _ in first })
        var shared: [(myRank: Int, theirRank: Int)] = []
        for myGame in myGames {
            if let theirRank = theirDict[myGame.canonicalId] {
                shared.append((myRank: myGame.rank, theirRank: theirRank))
            }
        }
        
        guard shared.count >= 2 else {
            if shared.count == 1 {
                let maxDiff = max(myGames.count, theirGames.count)
                guard maxDiff > 0 else { return 100 }
                let diff = abs(shared[0].myRank - shared[0].theirRank)
                return max(0, min(100, 100 - Int((Double(diff) / Double(maxDiff)) * 100)))
            }
            return 0
        }
        
        let sortedByMine = shared.indices.sorted { shared[$0].myRank < shared[$1].myRank }
        let sortedByTheirs = shared.indices.sorted { shared[$0].theirRank < shared[$1].theirRank }
        
        var myRelative = Array(repeating: 0, count: shared.count)
        var theirRelative = Array(repeating: 0, count: shared.count)
        
        for (rank, idx) in sortedByMine.enumerated() { myRelative[idx] = rank + 1 }
        for (rank, idx) in sortedByTheirs.enumerated() { theirRelative[idx] = rank + 1 }
        
        let n = Double(shared.count)
        var sumDSquared: Double = 0
        for i in shared.indices {
            let d = Double(myRelative[i] - theirRelative[i])
            sumDSquared += d * d
        }
        
        let denom = n * (n * n - 1)
        guard denom != 0 else { return 50 }
        let rho = 1 - (6 * sumDSquared) / denom
        return max(0, min(100, Int(((rho + 1) / 2) * 100)))
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
    
    // MARK: - Prediction
    private func fetchPredictionIfNeeded() async {
        // Only show prediction if user hasn't ranked it
        guard myUserGame == nil else { return }
        
        // Get game count
        if let userId = supabase.currentUser?.id {
            myGameCount = (try? await supabase.client
                .from("user_games")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .count) ?? 0
        }
        
        guard let context = await PredictionEngine.buildContext() else { return }
        
        do {
            struct GameInfo: Decodable {
                let rawg_id: Int
                let genres: [String]?
                let tags: [String]?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let metacritic_score: Int?
            }
            
            let infos: [GameInfo] = try await supabase.client
                .from("games")
                .select("rawg_id, genres, tags, curated_genres, curated_tags, metacritic_score")
                .eq("rawg_id", value: gameId)
                .limit(1)
                .execute()
                .value
            
            guard let info = infos.first else { return }
            
            let target = PredictionTarget(
                rawgId: info.rawg_id,
                canonicalGameId: nil,
                genres: info.curated_genres ?? info.genres ?? [],
                tags: info.curated_tags ?? info.tags ?? [],
                metacriticScore: info.metacritic_score
            )
            
            prediction = PredictionEngine.shared.predict(game: target, context: context)
        } catch {
            debugLog("⚠️ Could not fetch prediction data: \(error)")
        }
    }
    // MARK: - Refresh after logging
    private func refreshMyGame() async {
        await fetchMyGame()
        await fetchFriendRankings()
        if myUserGame != nil {
            prediction = nil // Clear prediction once ranked
        }
    }
}
