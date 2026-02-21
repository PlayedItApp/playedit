import SwiftUI
import AuthenticationServices
import Supabase

// MARK: - Import State
enum SteamImportPhase: Equatable {
    case ready
    case authenticating
    case fetchingLibrary
    case selectingGames
    case matchingGames
    case ranking
    case complete
    case error(String)
}

struct SteamImportView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    @ObservedObject var wantToPlayManager = WantToPlayManager.shared
    
    @State private var phase: SteamImportPhase = .ready
    @State private var steamId: String?
    @State private var libraryGames: [SteamLibraryGame] = []
    @State private var selectedForRanking: Set<Int> = []
    @State private var bookmarkedGames: Set<Int> = []
    @State private var matchedGames: [MatchedSteamGame] = []
    @State private var matchProgress: (Int, Int) = (0, 0)
    @State private var existingRawgIds: Set<Int> = []
    @State private var existingGameTitles: Set<String> = []
    @State private var existingUserGames: [UserGame] = []
    
    // Ranking state
    @State private var gamesToRank: [MatchedSteamGame] = []
    @State private var currentRankIndex = 0
    @State private var showComparison = false
    @State private var currentGameId: Int?
    
    // UI state
    @State private var showSelectAll = true
    @State private var authContext: SteamAuthPresentationContext?
    
    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    readyView
                case .authenticating:
                    loadingView("Connecting to Steam…")
                case .fetchingLibrary:
                    loadingView("Fetching your Steam library…")
                case .selectingGames:
                    gameSelectionView
                case .matchingGames:
                    matchingView
                case .ranking:
                    rankingView
                case .complete:
                    completeView
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Import from Steam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
    }
    
    // MARK: - Ready View (Pre-Auth)
    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 60))
                .foregroundColor(.primaryBlue)
            
            Text("Import Steam Library")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Heads up! If you've got a big Steam library, ranking all those games takes time. Make sure you're ready to settle in. 🎮")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button {
                Task { await startAuth() }
            } label: {
                Text("I'm Ready, Let's Go")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            
            Button {
                dismiss()
            } label: {
                Text("Maybe Later")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Loading View
    private func loadingView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                .scaleEffect(1.5)
            Text(message)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            Spacer()
        }
    }
    
    // MARK: - Game Selection View
    private var gameSelectionView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Steam Games")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    Text("\(selectedForRanking.count) to rank • \(bookmarkedGames.count) bookmarked")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                Spacer()
                Button {
                    toggleSelectAll()
                } label: {
                    Text(showSelectAll ? "Select All" : "Deselect All")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    let substantialGames = libraryGames.filter { $0.isSubstantialPlaytime }
                    let lightGames = libraryGames.filter { !$0.isSubstantialPlaytime }
                    
                    // Games with 1+ hours
                    ForEach(substantialGames) { game in
                        SteamGameRow(
                            game: game,
                            isSelectedForRanking: selectedForRanking.contains(game.appid),
                            isBookmarked: bookmarkedGames.contains(game.appid),
                            isAlreadyRanked: isGameAlreadyRanked(game.name),
                            isDimmed: false,
                            onToggleRank: { toggleRanking(game) },
                            onToggleBookmark: { toggleBookmark(game) }
                        )
                    }
                    
                    // Section divider
                    if !lightGames.isEmpty {
                        HStack {
                            Text("Under 1 Hour")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                    }
                    
                    // Games with less than 1 hour
                    ForEach(lightGames) { game in
                        SteamGameRow(
                            game: game,
                            isSelectedForRanking: selectedForRanking.contains(game.appid),
                            isBookmarked: bookmarkedGames.contains(game.appid),
                            isAlreadyRanked: isGameAlreadyRanked(game.name),
                            isDimmed: true,
                            onToggleRank: { toggleRanking(game) },
                            onToggleBookmark: { toggleBookmark(game) }
                        )
                    }
                }
            }
            
            // Bottom bar
            VStack(spacing: 12) {
                Divider()
                Button {
                    Task { await startMatching() }
                } label: {
                    Text("Import \(selectedForRanking.count + bookmarkedGames.count) Games")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedForRanking.isEmpty && bookmarkedGames.isEmpty)
                .opacity(selectedForRanking.isEmpty && bookmarkedGames.isEmpty ? 0.4 : 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .background(Color.cardBackground) 
        }
    }
    
    // MARK: - Matching View
    private var matchingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                .scaleEffect(1.5)
            Text("Matching your games… (\(matchProgress.0) of \(matchProgress.1))")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            
            ProgressView(value: Double(matchProgress.0), total: Double(max(matchProgress.1, 1)))
                .tint(.primaryBlue)
                .padding(.horizontal, 60)
            
            Spacer()
        }
    }
    
    // MARK: - Ranking View
    private var rankingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
            Spacer()
        }
        .sheet(isPresented: $showComparison, onDismiss: {
            // If comparison was cancelled (not completed), dismiss back to profile
            if currentRankIndex < gamesToRank.count && phase == .ranking {
                dismiss()
            }
        }) {
            if let index = gamesToRank.indices.contains(currentRankIndex) ? currentRankIndex : nil {
                let game = gamesToRank[index]
                ComparisonView(
                    newGame: game.toGame(),
                    existingGames: existingUserGames,
                    skipCelebration: true,
                    hideCancel: true,
                    onComplete: { position in
                        Task {
                            await saveImportedGame(game: game, position: position)
                            await refreshExistingGames()
                            currentRankIndex += 1
                            if currentRankIndex >= gamesToRank.count {
                                showComparison = false
                                dismiss()
                            } else {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                showComparison = true
                            }
                        }
                    }
                )
                .interactiveDismissDisabled()
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Button {
                            showComparison = false
                            dismiss()
                        } label: {
                            Text("Save & Finish Later (\(currentRankIndex)/\(gamesToRank.count) ranked)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.primaryBlue, lineWidth: 1.5)
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                    }
                    .background(Color.cardBackground) 
                }
            }
        }
        .onAppear {
            if !gamesToRank.isEmpty {
                showComparison = true
            }
        }
    }
    
    // MARK: - Complete View
    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Text("🙌")
                .font(.system(size: 60))
            
            Text("All done!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            let rankedCount = min(currentRankIndex, gamesToRank.count)
            let bookmarkCount = bookmarkedGames.count
            
            if rankedCount > 0 && bookmarkCount > 0 {
                Text("\(rankedCount) games ranked, \(bookmarkCount) bookmarked")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            } else if rankedCount > 0 {
                Text("\(rankedCount) games imported and ranked")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            } else if bookmarkCount > 0 {
                Text("\(bookmarkCount) games added to Want to Play")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Error View
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.accentOrange)
            
            Text(message)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                phase = .ready
            } label: {
                Text("Try Again")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private func isGameAlreadyRanked(_ steamName: String) -> Bool {
        let normalized = steamName.lowercased()
            .replacingOccurrences(of: "™", with: "")
            .replacingOccurrences(of: "®", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        for title in existingGameTitles {
            if title == normalized { return true }
            if title.contains(normalized) || normalized.contains(title) { return true }
        }
        return false
    }
    
    // MARK: - Actions
    private func startAuth() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        // Check if already connected
        if let existingSteamId = await SteamService.shared.getSteamId() {
            steamId = existingSteamId
            phase = .fetchingLibrary
            await fetchLibrary()
            return
        }
        
        phase = .authenticating
        
        do {
            let loginUrl = try await SteamService.shared.getLoginURL(userId: userId.uuidString)
            
            // Open Steam login in ASWebAuthenticationSession
            let callbackURL: URL? = await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    let session = ASWebAuthenticationSession(
                        url: URL(string: loginUrl)!,
                        callbackURLScheme: "playedit"
                    ) { callbackURL, error in
                        continuation.resume(returning: callbackURL)
                    }
                    
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        let context = SteamAuthPresentationContext(windowScene: windowScene)
                        self.authContext = context
                        session.presentationContextProvider = context
                    }
                    session.prefersEphemeralWebBrowserSession = true
                    session.start()
                }
            }
            
            // Parse the callback
            if let url = callbackURL {
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let params = Dictionary(uniqueKeysWithValues:
                    (components?.queryItems ?? []).compactMap { item in
                        item.value.map { (item.name, $0) }
                    }
                )
                
                if let error = params["error"] {
                    phase = .error("Steam login failed: \(error)")
                    return
                }
                
                if let returnedSteamId = params["steam_id"] {
                    steamId = returnedSteamId
                    phase = .fetchingLibrary
                    await fetchLibrary()
                } else {
                    phase = .error("Couldn't connect to Steam. Try again?")
                }
            } else {
                // User cancelled
                phase = .ready
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
    
    private func fetchLibrary() async {
        guard let steamId = steamId else {
            phase = .error("No Steam ID found")
            return
        }
        
        do {
            libraryGames = try await SteamService.shared.fetchLibrary(steamId: steamId)
            
            if libraryGames.isEmpty {
                phase = .error("Your Steam library is empty! Try logging some games manually?")
                return
            }
            
            // Fetch existing ranked game IDs to filter
            await fetchExistingRankedIds()
            
            phase = .selectingGames
        } catch let error as SteamError {
            phase = .error(error.localizedDescription)
        } catch {
            phase = .error("Couldn't load your Steam library. Check your connection and try again?")
        }
    }
    
    private func fetchExistingRankedIds() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct Row: Decodable {
                let game_id: Int
                let games: GameInfo?
                struct GameInfo: Decodable {
                    let rawg_id: Int
                    let title: String
                    let description: String?
                }
            }
            
            let rows: [Row] = try await supabase.client
                .from("user_games")
                .select("game_id, games(rawg_id, title)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            existingRawgIds = Set(rows.compactMap { $0.games?.rawg_id })
            existingGameTitles = Set(rows.compactMap { $0.games?.title.lowercased() })
        } catch {
            print("❌ Error fetching existing games: \(error)")
        }
    }
    
    private func toggleRanking(_ game: SteamLibraryGame) {
        if selectedForRanking.contains(game.appid) {
            selectedForRanking.remove(game.appid)
        } else {
            selectedForRanking.insert(game.appid)
            // Remove from bookmarks if it was bookmarked
            bookmarkedGames.remove(game.appid)
        }
    }
    
    private func toggleBookmark(_ game: SteamLibraryGame) {
        if bookmarkedGames.contains(game.appid) {
            bookmarkedGames.remove(game.appid)
        } else {
            bookmarkedGames.insert(game.appid)
            // Remove from ranking if it was selected
            selectedForRanking.remove(game.appid)
        }
    }
    
    private func toggleSelectAll() {
        let substantialGames = libraryGames.filter { $0.isSubstantialPlaytime && !existingRawgIds.contains($0.appid) }
        
        if showSelectAll {
            for game in substantialGames {
                selectedForRanking.insert(game.appid)
                bookmarkedGames.remove(game.appid)
            }
        } else {
            for game in substantialGames {
                selectedForRanking.remove(game.appid)
            }
        }
        showSelectAll.toggle()
    }
    
    private func startMatching() async {
        phase = .matchingGames
        
        // Combine both sets for matching
        let allSelectedAppIds = selectedForRanking.union(bookmarkedGames)
        let gamesToMatch = libraryGames.filter { allSelectedAppIds.contains($0.appid) }
        
        do {
            matchedGames = try await SteamService.shared.matchGames(
                games: gamesToMatch,
                progressCallback: { completed, total in
                    matchProgress = (completed, total)
                }
            )
            
            // Save bookmarked games to Want to Play
            let bookmarkMatches = matchedGames.filter { bookmarkedGames.contains($0.steamAppId) }
            for game in bookmarkMatches {
                if game.isMatched {
                    _ = await wantToPlayManager.addGame(
                        gameId: game.rawgId!,
                        gameTitle: game.displayTitle,
                        gameCoverUrl: game.displayCoverUrl,
                        source: "steam_import"
                    )
                }
            }
            // Refresh the Want to Play list
            await WantToPlayManager.shared.refreshMyIds()
            
            // Filter to only games selected for ranking that have RAWG matches
            gamesToRank = matchedGames.filter {
                selectedForRanking.contains($0.steamAppId) && $0.isMatched
            }
            
            if gamesToRank.isEmpty && bookmarkedGames.isEmpty {
                phase = .error("Couldn't match any of your selected games. Try different ones?")
                return
            }
            
            if gamesToRank.isEmpty {
                // Only bookmarks, no ranking needed
                phase = .complete
                return
            }
            
            // Load existing user games for comparison
            await refreshExistingGames()
            
            currentRankIndex = 0
            phase = .ranking
            
        } catch {
            phase = .error("Matching failed: \(error.localizedDescription)")
        }
    }
    
    private func refreshExistingGames() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
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
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            existingUserGames = rows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    canonicalGameId: nil,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date,
                    gameRawgId: row.games.rawg_id
                )
            }
        } catch {
            print("❌ Error refreshing games: \(error)")
        }
    }
    
    private func saveImportedGame(game: MatchedSteamGame, position: Int) async {
        guard let userId = supabase.currentUser?.id,
              let rawgId = game.rawgId else { return }
        
        do {
            // Upsert game into games table
            struct GameInsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String
                let metacritic_score: Int
            }
            
            let gameInsert = GameInsert(
                rawg_id: rawgId,
                title: game.displayTitle,
                cover_url: game.rawgCoverUrl ?? "",
                genres: game.rawgGenres,
                platforms: game.rawgPlatforms,
                release_date: game.rawgReleaseDate ?? "",
                metacritic_score: game.rawgMetacriticScore ?? 0
            )
            
            try await supabase.client.from("games")
                .upsert(gameInsert, onConflict: "rawg_id")
                .execute()
            
            // Get the game ID
            struct GameIdResponse: Decodable { let id: Int }
            let gameRecord: GameIdResponse = try await supabase.client.from("games")
                .select("id")
                .eq("rawg_id", value: rawgId)
                .single()
                .execute()
                .value
            
            // Shift existing games at or below position
            struct GameToShift: Decodable { let id: String; let rank_position: Int }
            let gamesToShift: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .gte("rank_position", value: position)
                .order("rank_position", ascending: false)
                .execute()
                .value
            
            for g in gamesToShift {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position + 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            // Resolve canonical game ID
            let canonicalId = await RAWGService.shared.getParentGameId(for: rawgId) ?? rawgId
            
            // Insert user_game
            struct UserGameInsert: Encodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let platform_played: [String]
                let notes: String
                let canonical_game_id: Int
                let steam_appid: Int
                let steam_playtime_minutes: Int
                let batch_source: String
            }
            
            try await supabase.client.from("user_games")
                .insert(UserGameInsert(
                    user_id: userId.uuidString,
                    game_id: gameRecord.id,
                    rank_position: position,
                    platform_played: ["PC"],
                    notes: "",
                    canonical_game_id: canonicalId,
                    steam_appid: game.steamAppId,
                    steam_playtime_minutes: game.playtimeMinutes,
                    batch_source: "steam_import"
                ))
                .execute()
            
            print("✅ Imported \(game.displayTitle) at position \(position)")
            
        } catch {
            print("❌ Error saving imported game: \(error)")
        }
    }
}

// MARK: - Steam Game Row
struct SteamGameRow: View {
    let game: SteamLibraryGame
    let isSelectedForRanking: Bool
    let isBookmarked: Bool
    let isAlreadyRanked: Bool
    let isDimmed: Bool
    let onToggleRank: () -> Void
    let onToggleBookmark: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox for ranking
            if !isAlreadyRanked {
                Button(action: onToggleRank) {
                    Image(systemName: isSelectedForRanking ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(isSelectedForRanking ? .primaryBlue : .silver)
                }
                .buttonStyle(.plain)
            }
            
            // Game icon
            if let iconUrl = game.iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.secondaryBackground)
                        .overlay(Image(systemName: "gamecontroller").foregroundStyle(Color.adaptiveSilver).font(.system(size: 12)))
                }
                .frame(width: 40, height: 40)
                .cornerRadius(6)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondaryBackground)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                    .overlay(Image(systemName: "gamecontroller").foregroundStyle(Color.adaptiveSilver).font(.system(size: 12)))
            }
            
            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                
                if isAlreadyRanked {
                    Text("Already ranked")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.teal)
                } else if isDimmed {
                    Text("Under 1 hour")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                } else {
                    Text(game.playtimeFormatted)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
            }
            
            Spacer()
            
            // Bookmark button
            if !isAlreadyRanked {
                Button(action: onToggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16))
                        .foregroundColor(isBookmarked ? .accentOrange : .silver)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(isAlreadyRanked ? 0.5 : 1.0)
        .allowsHitTesting(!isAlreadyRanked)
    }
}

// MARK: - Auth Presentation Context
class SteamAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    let windowScene: UIWindowScene
    
    init(windowScene: UIWindowScene) {
        self.windowScene = windowScene
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        windowScene.windows.first { $0.isKeyWindow } ?? UIWindow(windowScene: windowScene)
    }
}

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
