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
    case reviewingMatches
    case ranking
    case complete
    case error(String)
}

struct SteamImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager
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
    @State private var currentGameId: Int?
    @State private var currentRankingItem: RankingItem?
    @State private var confirmedForRanking: [MatchedSteamGame] = []
    @State private var selectedForReview: Set<Int> = []
    @State private var showMatchSwapSearch = false
    @State private var swappingGameIndex: Int?
    
    // UI state
    @State private var showSelectAll = true
    @State private var authContext: SteamAuthPresentationContext?
    @State private var showDiscardConfirmation = false
    
    // Resume state
    var resumingImport: PendingImport? = nil
    
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
                case .reviewingMatches:
                    matchReviewView
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
            .onAppear {
                if let pending = resumingImport {
                    gamesToRank = pending.games.map { g in
                        MatchedSteamGame(
                            steamAppId: Int(g.sourceMetadata["steam_app_id"] ?? "0") ?? 0,
                            steamName: g.sourceMetadata["steam_name"] ?? g.title,
                            playtimeMinutes: Int(g.sourceMetadata["steam_playtime_minutes"] ?? "0") ?? 0,
                            rawgId: g.rawgId,
                            rawgTitle: g.title,
                            rawgCoverUrl: g.coverUrl,
                            rawgGenres: g.genres,
                            rawgPlatforms: g.platforms,
                            rawgReleaseDate: g.releaseDate,
                            rawgMetacriticScore: g.metacriticScore,
                            matchConfidence: 100
                        )
                    }
                    currentRankIndex = pending.currentIndex
                    Task {
                        await refreshExistingGames()
                        selectedForReview = Set(gamesToRank.map { $0.id })
                        phase = .ranking
                    }
                }
            }
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
    
    // MARK: - Match Review View
    private var matchReviewView: some View {
        VStack(spacing: 0) {
            // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Matches")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        Text("\(selectedForReview.count) selected to rank")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    Spacer()
                    Button {
                        if selectedForReview.count == confirmedForRanking.count {
                            selectedForReview.removeAll()
                        } else {
                            selectedForReview = Set(confirmedForRanking.map { $0.id })
                        }
                    } label: {
                        Text(selectedForReview.count == confirmedForRanking.count ? "Deselect All" : "Select All")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.primaryBlue)
                    }
                }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(confirmedForRanking.enumerated()), id: \.element.id) { index, game in
                        matchReviewRow(game: game, index: index)
                    }
                    
                    // Unmatched games
                    let unmatchedGames = matchedGames.filter {
                        selectedForRanking.contains($0.steamAppId) && !$0.isMatched
                    }
                    if !unmatchedGames.isEmpty {
                        HStack {
                            Text("No Match Found")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                        
                        ForEach(Array(unmatchedGames.enumerated()), id: \.element.id) { _, game in
                            unmatchedReviewRow(game: game)
                        }
                    }
                }
            }
            
            // Bottom bar
            VStack(spacing: 12) {
                Divider()
                Button {
                    startRankingFromReview()
                } label: {
                    Text("Start Ranking (\(selectedForReview.count) games)")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedForReview.isEmpty)
                .opacity(selectedForReview.isEmpty ? 0.4 : 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showMatchSwapSearch) {
            matchSwapSearchSheet
        }
    }
    
    private func matchReviewRow(game: MatchedSteamGame, index: Int) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: selectedForReview.contains(game.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(selectedForReview.contains(game.id) ? .primaryBlue : .silver)

            // RAWG cover art
            if let coverUrl = game.rawgCoverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.secondaryBackground)
                }
                .frame(width: 48, height: 64)
                .cornerRadius(6)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondaryBackground)
                    .frame(width: 48, height: 64)
                    .cornerRadius(6)
                    .overlay(Image(systemName: "gamecontroller").foregroundStyle(Color.adaptiveSilver).font(.system(size: 14)))
            }
            
            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                
                if game.rawgTitle != nil && game.steamName.lowercased() != game.rawgTitle!.lowercased() {
                    Text("Steam: \(game.steamName)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .lineLimit(1)
                }
                
                Text(game.playtimeFormatted)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            Spacer()
            
            // Swap button
            Button {
                swappingGameIndex = index
                showMatchSwapSearch = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14))
                    .foregroundColor(.primaryBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedForReview.contains(game.id) {
                selectedForReview.remove(game.id)
            } else {
                selectedForReview.insert(game.id)
            }
        }
    }

    private func unmatchedReviewRow(game: MatchedSteamGame) -> some View {
        HStack(spacing: 12) {
            // Warning icon placeholder
            Rectangle()
                .fill(Color.secondaryBackground)
                .frame(width: 48, height: 64)
                .cornerRadius(6)
                .overlay(
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.accentOrange)
                        .font(.system(size: 16))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(game.steamName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                Text("No match found")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.accentOrange)
            }
            
            Spacer()
            
            // Search button
            Button {
                // Add to confirmed list temporarily so swap can target it
                let placeholder = game
                confirmedForRanking.append(placeholder)
                swappingGameIndex = confirmedForRanking.count - 1
                showMatchSwapSearch = true
            } label: {
                Text("Search")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primaryBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    private var matchSwapSearchSheet: some View {
        NavigationStack {
            MatchSwapSearchView { selectedGame in
                if let index = swappingGameIndex, index < confirmedForRanking.count {
                    let original = confirmedForRanking[index]
                    let swapped = MatchedSteamGame(
                        steamAppId: original.steamAppId,
                        steamName: original.steamName,
                        playtimeMinutes: original.playtimeMinutes,
                        rawgId: selectedGame.rawgId,
                        rawgTitle: selectedGame.title,
                        rawgCoverUrl: selectedGame.coverURL,
                        rawgGenres: selectedGame.genres,
                        rawgPlatforms: selectedGame.platforms,
                        rawgReleaseDate: selectedGame.releaseDate,
                        rawgMetacriticScore: selectedGame.metacriticScore,
                        matchConfidence: 100
                    )
                    confirmedForRanking[index] = swapped
                }
                showMatchSwapSearch = false
                swappingGameIndex = nil
            }
            .navigationTitle("Find Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .complete {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.primaryBlue)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Ranking View
    private var rankingView: some View {
        VStack {
            if currentRankIndex < gamesToRank.count {
                rankingComparisonView
                    .id(currentRankIndex)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }
    
    private var rankingComparisonView: some View {
        let game = gamesToRank[currentRankIndex]
        return ComparisonView(
            newGame: game.toGame(),
            existingGames: existingUserGames,
            skipCelebration: true,
            hideCancel: true,
            suppressDismiss: true,
            onComplete: { position in
                Task {
                    let saved = await saveImportedGame(game: game, position: position)
                    guard saved else {
                        await MainActor.run {
                            phase = .error("Failed to save \(game.displayTitle). Please try again.")
                        }
                        return
                    }
                    await refreshExistingGames()
                    await MainActor.run {
                        currentRankIndex += 1
                        debugLog("🎮 Ranked game \(currentRankIndex) of \(gamesToRank.count): \(game.displayTitle)")
                    }
                    await PendingImportManager.shared.updateIndex(source: "steam_import", currentIndex: currentRankIndex)
                    if currentRankIndex >= gamesToRank.count {
                        await PendingImportManager.shared.delete(source: "steam_import")
                        if let userId = supabase.currentUser?.id {
                            _ = try? await supabase.client
                                .rpc("renormalize_ranks", params: [
                                    "p_user_id": AnyJSON.string(userId.uuidString)
                                ])
                                .execute()
                        }
                        AnalyticsService.shared.track(.steamImportCompleted, properties: [
                            "games_ranked": currentRankIndex
                        ])
                        await MainActor.run {
                            phase = .complete
                        }
                        NotificationCenter.default.post(name: .didCompleteRanking, object: nil)
                    }
                }
            }
        )
        .interactiveDismissDisabled()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
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

                Button {
                    showDiscardConfirmation = true
                } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 8)
            }
            .confirmationDialog("Discard this import?", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard Import", role: .destructive) {
                    Task {
                        await PendingImportManager.shared.delete(source: "steam_import")
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your progress will be lost and the remaining games won't be ranked.")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
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
            debugLog("❌ Error fetching existing games: \(error)")
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
            confirmedForRanking = matchedGames.filter {
                selectedForRanking.contains($0.steamAppId) && $0.isMatched
            }
            selectedForReview = Set(confirmedForRanking.map { $0.id })
            
            if confirmedForRanking.isEmpty && bookmarkedGames.isEmpty {
                phase = .error("Couldn't match any of your selected games. Try different ones?")
                return
            }
            
            if confirmedForRanking.isEmpty {
                // Only bookmarks, no ranking needed
                phase = .complete
                return
            }
            
            phase = .reviewingMatches
            
        } catch {
            debugLog("❌ Steam matching error: \(error)")
            phase = .error("Couldn't match your games right now. Check your connection and try again.")
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
            debugLog("❌ Error refreshing games: \(error)")
        }
    }
    
    private func pendingGamesFromConfirmed() -> [PendingImportGame] {
        confirmedForRanking.compactMap { game in
            guard let rawgId = game.rawgId else { return nil }
            return PendingImportGame(
                rawgId: rawgId,
                title: game.displayTitle,
                coverUrl: game.rawgCoverUrl,
                genres: game.rawgGenres,
                platforms: game.rawgPlatforms,
                releaseDate: game.rawgReleaseDate,
                metacriticScore: game.rawgMetacriticScore,
                sourceMetadata: [
                    "steam_app_id": String(game.steamAppId),
                    "steam_playtime_minutes": String(game.playtimeMinutes),
                    "steam_name": game.steamName
                ]
            )
        }
    }
    
    private func startRankingFromReview() {
        gamesToRank = confirmedForRanking.filter { selectedForReview.contains($0.id) }
        
        if gamesToRank.isEmpty {
            phase = .complete
            return
        }
        
        Task {
            await PendingImportManager.shared.save(
                source: "steam_import",
                games: pendingGamesFromConfirmed(),
                currentIndex: 0
            )
            await refreshExistingGames()
            currentRankIndex = 0
            AnalyticsService.shared.track(.steamImportStarted, properties: [
                "game_count": gamesToRank.count
            ])
            phase = .ranking
        }
    }
    
    private func saveImportedGame(game: MatchedSteamGame, position: Int) async -> Bool {
        guard let userId = supabase.currentUser?.id,
              let rawgId = game.rawgId else { return false }
        
        do {
            struct GameInsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String?
                let metacritic_score: Int
            }
            
            let gameInsert = GameInsert(
                rawg_id: rawgId,
                title: game.displayTitle,
                cover_url: game.rawgCoverUrl ?? "",
                genres: game.rawgGenres,
                platforms: game.rawgPlatforms,
                release_date: game.rawgReleaseDate,
                metacritic_score: game.rawgMetacriticScore ?? 0
            )
            
            try await supabase.client.from("games")
                .upsert(gameInsert, onConflict: "rawg_id")
                .execute()
            
            struct GameIdResponse: Decodable { let id: Int }
            let gameRecord: GameIdResponse = try await supabase.client.from("games")
                .select("id")
                .eq("rawg_id", value: rawgId)
                .single()
                .execute()
                .value
            
            let canonicalId = await RAWGService.shared.getParentGameId(for: rawgId) ?? rawgId
            
            try await supabase.client
                .rpc("insert_game_at_rank", params: [
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_game_id": AnyJSON.integer(gameRecord.id),
                    "p_rank": AnyJSON.integer(position),
                    "p_platform_played": AnyJSON.array([AnyJSON.string("PC")]),
                    "p_notes": AnyJSON.string(""),
                    "p_canonical_game_id": AnyJSON.integer(canonicalId),
                    "p_batch_source": AnyJSON.string("steam_import"),
                    "p_steam_appid": AnyJSON.integer(game.steamAppId),
                    "p_steam_playtime_minutes": AnyJSON.integer(game.playtimeMinutes)
                ])
                .execute()
            
            debugLog("✅ Imported \(game.displayTitle) at position \(position)")
            return true
            
        } catch {
            debugLog("❌ Error saving imported game: \(error)")
            return false
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
                Image(systemName: isSelectedForRanking ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelectedForRanking ? .primaryBlue : .silver)
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
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(isAlreadyRanked ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isAlreadyRanked {
                onToggleRank()
            }
        }
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

// MARK: - Match Swap Search View
struct MatchSwapSearchView: View {
    let onSelect: (Game) -> Void
    
    @State private var searchText = ""
    @State private var searchResults: [Game] = []
    @State private var isSearching = false
    @State private var searchError = false
    @State private var debounceTask: Task<Void, Never>? = nil
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color.adaptiveGray)
                TextField("Search for the correct game…", text: $searchText)
                    .font(.system(size: 16, design: .rounded))
                    .focused($isSearchFocused)
                    .onSubmit { search() }
                    .submitLabel(.search)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondaryBackground)
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            if isSearching {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                Spacer()
            } else if searchResults.isEmpty && !searchText.isEmpty {
                Spacer()
                Text(searchError ? "Can't reach the game database right now. Check your connection and try again." : "No results")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { game in
                            Button {
                                onSelect(game)
                            } label: {
                                HStack(spacing: 12) {
                                    if let coverUrl = game.coverURL, let url = URL(string: coverUrl) {
                                        AsyncImage(url: url) { image in
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } placeholder: {
                                            Rectangle().fill(Color.secondaryBackground)
                                        }
                                        .frame(width: 48, height: 64)
                                        .cornerRadius(6)
                                        .clipped()
                                    } else {
                                        Rectangle()
                                            .fill(Color.secondaryBackground)
                                            .frame(width: 48, height: 64)
                                            .cornerRadius(6)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(game.title)
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.adaptiveSlate)
                                            .lineLimit(1)
                                        if let date = game.releaseDate?.prefix(4) {
                                            Text(String(date))
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(Color.adaptiveGray)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            
                            Divider().padding(.leading, 80)
                        }
                    }
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) {
            search()
        }
    }
    
    private func search() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            do {
                let results = try await RAWGService.shared.searchGames(query: query)
                await MainActor.run {
                    searchResults = results
                    searchError = false
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                    searchError = true
                    isSearching = false
                }
            }
        }
    }
}

struct RankingItem: Identifiable {
    let id: Int
    let game: MatchedSteamGame
}

// MARK: - Safe Array Access
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
