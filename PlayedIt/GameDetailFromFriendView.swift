import SwiftUI
import Supabase

struct GameDetailFromFriendView: View {
    let userGame: UserGame          // The friend's UserGame entry
    let friend: Friend              // The friend whose list we came from
    let myGames: [UserGame]         // Current user's games (passed from FriendProfileView)
    
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?)] = []
    @State private var myUserGame: UserGame? = nil
    @State private var isLoadingFriendRankings = true
    @State private var showLogGame = false
    @State private var metacriticScore: Int? = nil
    @State private var showReportSheet = false
    @State private var gameDescription: String? = nil
    @State private var prediction: GamePrediction? = nil
    
    // Check if current user has this game ranked
    private var iHaveThisGame: Bool {
        myUserGame != nil
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Hero Section
                heroSection
                
                Divider()
                    .padding(.horizontal, 20)
                
                // MARK: - Friend's Perspective
                friendPerspectiveSection
                
                // MARK: - Your Perspective
                myPerspectiveSection
                
                // MARK: - Social Context
                if !friendRankings.isEmpty {
                    socialContextSection
                }
            }
            .padding(.vertical, 16)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
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
        .task {
            resolveMyGame()
            await fetchMetacriticScore()
            await fetchGameDescription()
            await fetchFriendRankings()
            if myUserGame == nil {
                await fetchPrediction()
            }
        }
        .sheet(isPresented: $showLogGame, onDismiss: {
            Task {
                await refreshMyGame()
            }
        }) {
            GameLogView(game: userGame.toGame())
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
        VStack(spacing: 16) {
            // Large cover art
            AsyncImage(url: URL(string: userGame.gameCoverURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondaryBackground)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.adaptiveSilver)
                    )
            }
            .frame(width: 160, height: 213)
            .cornerRadius(12)
            .clipped()
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            // Title
            Text(userGame.gameTitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Release year + Metacritic
            HStack(spacing: 16) {
                if let year = userGame.gameReleaseDate?.prefix(4) {
                    Label(String(year), systemImage: "calendar")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                if let score = metacriticScore ?? resolveMetacriticFromGame() {
                    HStack(spacing: 4) {
                        Text("Metacritic")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                        
                        Text("\(score)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(metacriticColor(score))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(metacriticColor(score).opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
                        
            // Game description
            if let desc = gameDescription, !desc.isEmpty {
                GameDescriptionView(text: desc)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Friend's Perspective
    private var friendPerspectiveSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .padding(16)
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
                    
                    Button {
                        showLogGame = true
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text("Log This Game")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
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
        do {
            struct GameRawgId: Decodable { let rawg_id: Int }
            let result: GameRawgId = try await supabase.client
                .from("games")
                .select("rawg_id")
                .eq("id", value: userGame.gameId)
                .single()
                .execute()
                .value
            let game = try await RAWGService.shared.getGameDetails(id: result.rawg_id)
            gameDescription = game.gameDescription
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
            
            let result: GameMeta = try await supabase.client
                .from("games")
                .select("metacritic_score")
                .eq("id", value: userGame.gameId)
                .single()
                .execute()
                .value
            
            if let score = result.metacritic_score, score > 0 {
                metacriticScore = score
            }
        } catch {
            debugLog("⚠️ Could not fetch metacritic score: \(error)")
        }
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
            
            var results: [(username: String, rank: Int, avatarURL: String?)] = []
            
            for ranking in matchedRankings {
                if let user = userMap[ranking.user_id.lowercased()] {
                    let displayName: String
                    if ranking.user_id.lowercased() == userId.uuidString.lowercased() {
                        displayName = "You"
                    } else {
                        displayName = user.username ?? "Unknown"
                    }
                    results.append((
                        username: displayName,
                        rank: ranking.rank_position,
                        avatarURL: user.avatar_url
                    ))
                }
            }
            
            // Sort: "You" first, then by rank
            friendRankings = results.sorted { a, b in
                if a.username == "You" { return true }
                if b.username == "You" { return false }
                return a.rank < b.rank
            }
            
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
    
    // MARK: - Prediction
    private func fetchPrediction() async {
        guard let context = await PredictionEngine.buildContext() else { return }
        
        // Get game genres/tags/metacritic from Supabase
        do {
            struct GameInfo: Decodable {
                let rawg_id: Int
                let genres: [String]?
                let tags: [String]?
                let metacritic_score: Int?
                let description: String?
            }
            
            let info: GameInfo = try await supabase.client
                .from("games")
                .select("rawg_id, genres, tags, metacritic_score")
                .eq("id", value: userGame.gameId)
                .single()
                .execute()
                .value
            
            let target = PredictionTarget(
                rawgId: info.rawg_id,
                canonicalGameId: userGame.canonicalGameId,
                genres: info.genres ?? [],
                tags: info.tags ?? [],
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
