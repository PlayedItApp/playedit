import SwiftUI
import Supabase

struct GameDetailFromFriendView: View {
    let userGame: UserGame          // The friend's UserGame entry
    let friend: Friend              // The friend whose list we came from
    let myGames: [UserGame]         // Current user's games (passed from FriendProfileView)
    
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
    @State private var myUserGame: UserGame? = nil
    @State private var isLoadingFriendRankings = true
    @State private var showLogGame = false
    @State private var metacriticScore: Int? = nil
    @State private var showReportSheet = false
    @State private var gameDescription: String? = nil
    @State private var prediction: GamePrediction? = nil
    @State private var curatedGenres: [String]? = nil
    @State private var curatedTags: [String]? = nil
    @State private var curatedPlatforms: [String]? = nil
    @State private var curatedReleaseYear: Int? = nil
    @State private var showGameDataReport = false
    
    // Check if current user has this game ranked
    private var iHaveThisGame: Bool {
        myUserGame != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
            // MARK: - Hero Section
            heroSection
            
            VStack(spacing: 12) {
                Divider()
                    .padding(.horizontal, 20)
                
                // MARK: - Friend's Perspective
                friendPerspectiveSection
            }
                // MARK: - My Perspective
                myPerspectiveSection
                
                // MARK: - Social Context
                if !friendRankings.isEmpty {
                    socialContextSection
                }
                // Report bad game data
                Button {
                    showGameDataReport = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13))
                        Text("Report incorrect game info")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color.adaptiveGray)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.adaptiveGray.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await GameShareService.shared.shareGame(
                                gameTitle: userGame.gameTitle,
                                coverURL: userGame.gameCoverURL,
                                gameId: userGame.gameRawgId ?? userGame.gameId
                            )
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.primaryBlue)
                    }
                    
                    if userGame.userId.lowercased() != (supabase.currentUser?.id.uuidString.lowercased() ?? "") {
                        Menu {
                            Button(role: .destructive) {
                                showReportSheet = true
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.primaryBlue)
                        }
                    }
                }
            }
        }
        .task {
            resolveMyGame()
            async let meta: () = fetchMetacriticScore()
            async let desc: () = fetchGameDescription()
            async let friends: () = fetchFriendRankings()
            async let pred: () = fetchPredictionIfNeeded()
            _ = await (meta, desc, friends, pred)
        }
        .sheet(isPresented: $showLogGame, onDismiss: {
            Task {
                await refreshMyGame()
            }
        }) {
            GameLogView(game: userGame.toGame(), source: "friend_list")
                .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showGameDataReport) {
            ReportGameDataView(
                gameId: userGame.gameId,
                rawgId: userGame.gameRawgId ?? userGame.gameId,
                gameTitle: userGame.gameTitle
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showReportSheet) {
            ReportView(
                contentType: .note,
                contentId: UUID(uuidString: userGame.id),
                contentText: userGame.notes,
                reportedUserId: UUID(uuidString: userGame.userId) ?? UUID()
            )
            .presentationDetents([.large])
        }
    }
    
    // MARK: - Hero Section
    private var heroSection: some View {
        GameInfoHeroView(
            title: userGame.gameTitle,
            coverURL: userGame.gameCoverURL,
            releaseDate: curatedReleaseYear.map { String($0) } ?? userGame.gameReleaseDate,
            metacriticScore: metacriticScore,
            gameDescription: gameDescription,
            curatedGenres: curatedGenres,
            curatedTags: curatedTags,
curatedPlatforms: curatedPlatforms
        )
        .padding(.top, 20)
    }
    
    // MARK: - Friend's Perspective
    private var friendPerspectiveSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Section header
            HStack(spacing: 8) {
                friendAvatar(size: 28)
                
                Text("\(friend.username)'s Take")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // Rank
                HStack(spacing: 12) {
                    Image(systemName: "number")
                        .font(.system(size: 14))
                        .foregroundColor(.accentOrange)
                        .frame(width: 20)
                    
                    Text("Ranked #\(userGame.rankPosition)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(userGame.rankPosition <= 3 ? .accentOrange : .slate)
                }
                
                // Platform
                if !userGame.platformPlayed.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 14))
                            .foregroundColor(.primaryBlue)
                            .frame(width: 20)
                        
                        Text(userGame.platformPlayed.joined(separator: ", "))
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                    }
                }
                
                // Date logged
                if let loggedAt = userGame.loggedAt {
                    HStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 14))
                            .foregroundColor(.primaryBlue)
                            .frame(width: 20)
                        
                        Text("Logged \(formatDate(loggedAt))")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
                
                // Notes / Review
                if let notes = userGame.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        
                        SpoilerTextView(notes, font: .system(size: 15, design: .rounded), color: .slate)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - My Perspective
    private var myPerspectiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your Take")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            if let myGame = myUserGame {
                // User has this game ranked
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "number")
                            .font(.system(size: 14))
                            .foregroundColor(.primaryBlue)
                            .frame(width: 20)
                        
                        Text("You ranked this #\(myGame.rankPosition)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(myGame.rankPosition <= 3 ? .accentOrange : .slate)
                    }
                    
                    // Rank difference callout
                    let diff = abs(myGame.rankPosition - userGame.rankPosition)
                    if diff >= 5 {
                        HStack(spacing: 8) {
                            Text("🔥")
                            Text("±\(diff) rank difference. One of your biggest debates!")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundColor(.accentOrange)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentOrange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // My notes
                    if let notes = myGame.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                            
                            SpoilerTextView(notes, font: .system(size: 15, design: .rounded), color: .slate)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground) 
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
            } else {
                // User hasn't ranked this game
                VStack(spacing: 16) {
                    Text("You haven't ranked this yet")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    if let pred = prediction {
                        let range = pred.estimatedRank(inListOf: myGames.count)
                        VStack(spacing: 8) {
                            HStack(spacing: 6) {
                                Text(pred.emoji)
                                Text("PlayedIt Prediction: \(pred.summaryText)")
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                            }
                            
                            Text("Estimated rank: ~#\(range.lower)–\(range.upper)")
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
                    
                    HStack(spacing: 10) {
                        Button {
                            showLogGame = true
                        } label: {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text("Log This Game")
                            }
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentOrange)
                            .cornerRadius(12)
                        }
                        
                        BookmarkButton(
                            gameId: userGame.gameRawgId ?? userGame.gameId,
                            gameTitle: userGame.gameTitle,
                            gameCoverUrl: userGame.gameCoverURL,
                            source: "friend_profile",
                            sourceFriendId: friend.userId
                        )
                        .frame(width: 48, height: 48)
                        .background(Color.primaryBlue.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primaryBlue.opacity(0.3), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)
                        .background(Color.accentOrange.opacity(0.1))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.accentOrange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(Color.primaryBlue.opacity(0.05))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primaryBlue.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Social Context
    private var socialContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How friends ranked this")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            if isLoadingFriendRankings {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(friendRankings.enumerated()), id: \.offset) { index, ranking in
                        HStack(spacing: 12) {
                            // Avatar
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
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helpers
    
    private func resolveMyGame() {
        let targetGameId = userGame.canonicalGameId ?? userGame.gameId
        myUserGame = myGames.first(where: {
            ($0.canonicalGameId ?? $0.gameId) == targetGameId
        })
    }
    
    private func fetchGameDescription() async {
        debugLog("📖 DESC DEBUG: gameId=\(userGame.gameId), gameRawgId=\(String(describing: userGame.gameRawgId)), title=\(userGame.gameTitle)")
        
        if let cached = GameMetadataCache.shared.get(gameId: userGame.gameId) {
            metacriticScore = cached.metacriticScore
            gameDescription = cached.description
            curatedGenres = cached.curatedGenres
            curatedTags = cached.curatedTags
            curatedPlatforms = cached.curatedPlatforms
            curatedReleaseYear = cached.curatedReleaseYear
            if gameDescription != nil { return }
        }
        
        do {
            struct GameDesc: Decodable { let rawg_id: Int; let description: String?; let curated_description: String?; let curated_genres: [String]?; let curated_tags: [String]?; let curated_platforms: [String]?; let curated_release_year: Int? }
            let results: [GameDesc] = try await supabase.client
                .from("games")
                .select("rawg_id, description, curated_description, curated_genres, curated_tags, curated_platforms, curated_release_year")
                .eq("rawg_id", value: userGame.gameRawgId ?? userGame.gameId)
                .limit(1)
                .execute()
                .value
            
            guard let result = results.first else { return }
                        
            curatedGenres = result.curated_genres
            curatedTags = result.curated_tags
            curatedPlatforms = result.curated_platforms
            curatedReleaseYear = result.curated_release_year
            
            if let desc = result.curated_description ?? result.description, !desc.isEmpty {
                gameDescription = desc
                GameMetadataCache.shared.set(gameId: userGame.gameId, description: desc, metacriticScore: metacriticScore, releaseDate: userGame.gameReleaseDate, curatedGenres: result.curated_genres, curatedTags: result.curated_tags, curatedPlatforms: result.curated_platforms, curatedReleaseYear: result.curated_release_year)
                return
            }
            
            debugLog("📖 Fetching RAWG details for rawg_id: \(result.rawg_id)")
            let details = try await RAWGService.shared.getGameDetails(id: result.rawg_id)
            debugLog("📖 RAWG returned title: \(details.title), desc prefix: \(String((details.gameDescription ?? "nil").prefix(60)))")
            gameDescription = details.gameDescription ?? details.gameDescriptionHtml
            
            if let desc = gameDescription, !desc.isEmpty {
                GameMetadataCache.shared.set(gameId: userGame.gameId, description: desc, metacriticScore: metacriticScore, releaseDate: userGame.gameReleaseDate, curatedGenres: curatedGenres, curatedTags: curatedTags,
curatedPlatforms: curatedPlatforms, curatedReleaseYear: curatedReleaseYear)
                    _ = try? await SupabaseManager.shared.client
                    .from("games")
                    .update(["description": desc])
                    .eq("rawg_id", value: result.rawg_id)
                    .execute()
            }
        } catch {
            debugLog("⚠️ Could not fetch game description: \(error)")
        }
    }
    
    private func resolveMetacriticFromGame() -> Int? {
        // The UserGame doesn't carry metacritic, so return nil
        // We'll fetch it from RAWG in fetchMetacriticScore
        return nil
    }
    
    private func fetchMetacriticScore() async {
        // Try to get metacritic from the games table first
        do {
            struct GameMeta: Decodable {
                let metacritic_score: Int?
            }
            
            let results: [GameMeta] = try await supabase.client
                .from("games")
                .select("metacritic_score")
                .eq("rawg_id", value: userGame.gameRawgId ?? userGame.gameId)
                .limit(1)
                .execute()
                .value
            
            guard let result = results.first else { return }
            
            if let score = result.metacritic_score, score > 0 {
                metacriticScore = score
            }
        } catch {
            debugLog("⚠️ Could not fetch metacritic score: \(error)")
        }
    }
    
    private func quickTasteMatch(myGames: [(canonicalId: Int, rank: Int)], theirGames: [(canonicalId: Int, rank: Int)]) -> Int {
            // Find shared games
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
            
            // Re-rank shared games relative to each other
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
    
    private func fetchFriendRankings() async {
        guard let userId = supabase.currentUser?.id else {
            isLoadingFriendRankings = false
            return
        }
        
        do {
            // 1. Get all accepted friendships for current user
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
            
            // Include current user's ID too
            let allUserIds = friendIds + [userId.uuidString]
            
            // 2. Fetch rankings for this game from all friends + self
            // We need to match on game_id or canonical_game_id
            let targetGameId = userGame.gameId
            let targetCanonicalId = userGame.canonicalGameId ?? userGame.gameId
            
            struct RankingRow: Decodable {
                let user_id: String
                let rank_position: Int
                let game_id: Int
                let canonical_game_id: Int?
            }
            
            let rankings: [RankingRow] = try await supabase.client
                .from("user_games")
                .select("user_id, rank_position, game_id, canonical_game_id")
                .in("user_id", values: allUserIds)
                .or("game_id.eq.\(targetGameId),canonical_game_id.eq.\(targetCanonicalId)")
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            // Filter to only include rankings that actually match this game
            let matchedRankings = rankings.filter { r in
                r.game_id == targetGameId ||
                r.game_id == targetCanonicalId ||
                (r.canonical_game_id != nil && r.canonical_game_id == targetCanonicalId)
            }
            
            // 3. Get usernames for all relevant users
            let rankedUserIds = Array(Set(matchedRankings.map { $0.user_id }))
            
            guard !rankedUserIds.isEmpty else {
                isLoadingFriendRankings = false
                return
            }
            
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
            
            // Fetch current user's games for taste match calculation
            struct MyGameRow: Decodable {
                let game_id: Int
                let rank_position: Int
                let canonical_game_id: Int?
                let user_id: String
            }
            let myGameRows: [MyGameRow] = try await supabase.client
                .from("user_games")
                .select("game_id, rank_position, canonical_game_id")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            
            // Fetch all friends' games for taste match in a single batch query
            let friendIdsForTaste = rankedUserIds.filter { $0.lowercased() != userId.uuidString.lowercased() }
            var friendGameCache: [String: [MyGameRow]] = [:]
            if !friendIdsForTaste.isEmpty {
                let allFriendGames: [MyGameRow] = try await supabase.client
                    .from("user_games")
                    .select("game_id, rank_position, canonical_game_id, user_id")
                    .in("user_id", values: friendIdsForTaste)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .value
                for game in allFriendGames {
                    let key = game.user_id.lowercased()
                    friendGameCache[key, default: []].append(game)
                }
            }
            
            var results: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
            
            for ranking in matchedRankings {
                if let user = userMap[ranking.user_id.lowercased()] {
                    let displayName: String
                    let tasteMatch: Int
                    if ranking.user_id.lowercased() == userId.uuidString.lowercased() {
                        displayName = "You"
                        tasteMatch = 100
                    } else {
                        displayName = user.username ?? "Unknown"
                        let theirGames = friendGameCache[ranking.user_id.lowercased()] ?? []
                        let myMapped = myGameRows.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
                        let theirMapped = theirGames.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
                        tasteMatch = quickTasteMatch(myGames: myMapped, theirGames: theirMapped)
                    }
                    results.append((
                        username: displayName,
                        rank: ranking.rank_position,
                        avatarURL: user.avatar_url,
                        tasteMatch: tasteMatch
                    ))
                }
            }
            
            friendRankings = results.sorted { $0.rank < $1.rank }
            
        } catch {
            debugLog("❌ Error fetching friend rankings: \(error)")
        }
        
        isLoadingFriendRankings = false
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            return displayFormatter.string(from: date)
        }
        
        // Fallback: just show the date part
        return String(dateString.prefix(10))
    }
    
    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return .success
        case 50...74: return .accentOrange
        default: return .error
        }
    }
    
    private func friendAvatar(size: CGFloat) -> some View {
        Group {
            if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsCircle(friend.username, size: size)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                initialsCircle(friend.username, size: size)
            }
        }
    }
    
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
    
    private func fetchPredictionIfNeeded() async {
        if myUserGame == nil {
            await fetchPrediction()
        }
    }
    
    // MARK: - Prediction
    private func fetchPrediction() async {
        guard let context = await PredictionEngine.buildContext() else { return }
        
        // Get game genres/tags/metacritic from Supabase
        do {
            struct GameInfo: Decodable {
                let rawg_id: Int
                let genres: [String]?
                let tags: [String]?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let metacritic_score: Int?
                let description: String?
            }
            
            let infos: [GameInfo] = try await supabase.client
                .from("games")
                .select("rawg_id, genres, tags, curated_genres, curated_tags, metacritic_score")
                .eq("rawg_id", value: userGame.gameRawgId ?? userGame.gameId)
                .limit(1)
                .execute()
                .value
            
            guard let info = infos.first else { return }
            
            let target = PredictionTarget(
                rawgId: info.rawg_id,
                canonicalGameId: userGame.canonicalGameId,
                genres: info.curated_genres ?? info.genres ?? [],
                tags: info.curated_tags ?? info.tags ?? [],
                metacriticScore: info.metacritic_score
            )
            
            prediction = PredictionEngine.shared.predict(game: target, context: context)
        } catch {
            debugLog("⚠️ Could not fetch prediction data: \(error)")
        }
    }

    private func refreshMyGame() async {
        guard let userId = supabase.currentUser?.id else { return }
        let targetGameId = userGame.canonicalGameId ?? userGame.gameId
        
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
                .or("game_id.eq.\(targetGameId),canonical_game_id.eq.\(targetGameId)")
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
            debugLog("❌ Error refreshing my game: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        GameDetailFromFriendView(
            userGame: UserGame(
                id: "preview-1",
                gameId: 1,
                userId: "friend-1",
                rankPosition: 5,
                platformPlayed: ["PlayStation 5"],
                notes: "One of the best open-world games I've ever played. The sense of discovery is unmatched.",
                loggedAt: "2025-01-15T10:30:00Z",
                canonicalGameId: nil,
                gameTitle: "The Legend of Zelda: Breath of the Wild",
                gameCoverURL: nil,
                gameReleaseDate: "2017-03-03",
                gameRawgId: nil
            ),
            friend: Friend(
                id: "f-1",
                friendshipId: "fs-1",
                username: "Alex",
                userId: "friend-1"
            ),
            myGames: []
        )
    }
}
