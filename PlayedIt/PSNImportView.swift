import SwiftUI
import Supabase

// MARK: - PSN Import Phase

enum PSNImportPhase: Equatable {
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

// MARK: - PSN Import View

struct PSNImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    @State private var phase: PSNImportPhase = .ready
    @State private var psnAuthResult: PSNAuthResult?
    @State private var libraryGames: [PSNLibraryGame] = []
    @State private var selectedForRanking: Set<String> = []
    @State private var matchedGames: [MatchedPSNGame] = []
    @State private var matchProgress: (Int, Int) = (0, 0)
    @State private var existingRawgIds: Set<Int> = []
    @State private var existingGameTitles: Set<String> = []
    @State private var existingUserGames: [UserGame] = []

    // Match review state
    @State private var confirmedForRanking: [MatchedPSNGame] = []
    @State private var selectedForReview: Set<String> = []
    @State private var showMatchSwapSearch = false
    @State private var swappingGameIndex: Int?

    // Ranking state
    @State private var gamesToRank: [MatchedPSNGame] = []
    @State private var currentRankIndex = 0

    // UI state
    @State private var showSelectAll = false
    @State private var showPSNAuth = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    readyView
                case .authenticating:
                    loadingView("Connecting to PlayStation…")
                case .fetchingLibrary:
                    loadingView("Fetching your PSN library…")
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
            .navigationTitle("Import from PlayStation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if phase == .ready || phase == .complete {
                            dismiss()
                        } else {
                            showDiscardConfirmation = true
                        }
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
        .interactiveDismissDisabled(phase != .ready && phase != .complete)
        .confirmationDialog(
            "Cancel import?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Import", role: .destructive) {
                Task {
                    await PendingImportManager.shared.delete(source: "psn_import")
                    dismiss()
                }
            }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Your progress will be lost.")
        }
        .sheet(isPresented: $showPSNAuth) {
            PSNAuthView(
                onSuccess: { npsso in
                    showPSNAuth = false
                    Task { await handleNPSSO(npsso) }
                },
                onCancel: {
                    showPSNAuth = false
                    phase = .ready
                }
            )
        }
    }

    // MARK: - Ready View

    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 60))
                .foregroundColor(.primaryBlue)

            Text("Import PSN Library")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)

            Text("Sign in to PlayStation to import your played games. You'll pick which ones to rank, we'll do the rest. 🎮")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                Task { await startAuth() }
            } label: {
                Text("Connect PlayStation")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)

            Button { dismiss() } label: {
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your PSN Games")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    Text("\(selectedForRanking.count) selected to rank")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                Spacer()
                Button { toggleSelectAll() } label: {
                    Text(showSelectAll ? "Deselect All" : "Select All")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    let sortByPlatformThenDate: (PSNLibraryGame, PSNLibraryGame) -> Bool = { a, b in
                        if a.platform != b.platform { return platformOrder(a.platform) < platformOrder(b.platform) }
                        let aDate = a.lastPlayedAt ?? ""
                        let bDate = b.lastPlayedAt ?? ""
                        if aDate != bDate { return aDate > bDate }
                        return a.name < b.name
                    }
                    let alreadyRankedGames = libraryGames
                        .filter { isGameAlreadyRanked($0.name) }
                        .sorted { $0.name < $1.name }
                    let substantialGames = libraryGames
                        .filter { $0.isSubstantialPlaytime && !isGameAlreadyRanked($0.name) }
                        .sorted(by: sortByPlatformThenDate)
                    let lightGames = libraryGames
                        .filter { !$0.isSubstantialPlaytime && !isGameAlreadyRanked($0.name) }
                        .sorted(by: sortByPlatformThenDate)

                    ForEach(substantialGames) { game in
                        PSNGameRow(
                            game: game,
                            isSelected: selectedForRanking.contains(game.titleId),
                            isAlreadyRanked: isGameAlreadyRanked(game.name),
                            isDimmed: false,
                            onToggle: { toggleRanking(game) }
                        )
                    }

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

                        ForEach(lightGames) { game in
                            PSNGameRow(
                                game: game,
                                isSelected: selectedForRanking.contains(game.titleId),
                                isAlreadyRanked: false,
                                isDimmed: true,
                                onToggle: { toggleRanking(game) }
                            )
                        }
                    }

                    if !alreadyRankedGames.isEmpty {
                        HStack {
                            Text("Already Ranked")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)

                        ForEach(alreadyRankedGames) { game in
                            PSNGameRow(
                                game: game,
                                isSelected: false,
                                isAlreadyRanked: true,
                                isDimmed: false,
                                onToggle: {}
                            )
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                Divider()
                Button {
                    Task { await startMatching() }
                } label: {
                    Text("Import \(selectedForRanking.count) Games")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedForRanking.isEmpty)
                .opacity(selectedForRanking.isEmpty ? 0.4 : 1.0)
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
                    let alreadyRanked = confirmedForRanking.filter { isGameAlreadyRanked($0.displayTitle) }
                    let unranked = confirmedForRanking
                        .filter { !isGameAlreadyRanked($0.displayTitle) }
                        .sorted {
                            if $0.platform != $1.platform { return platformOrder($0.platform) < platformOrder($1.platform) }
                            return $0.playtimeMinutes > $1.playtimeMinutes
                        }
                    let platforms = unranked.reduce(into: [String]()) {
                        if !$0.contains($1.platform) { $0.append($1.platform) }
                    }

                    ForEach(platforms, id: \.self) { platform in
                        HStack {
                            Text(platform)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)

                        ForEach(unranked.filter { $0.platform == platform }) { game in
                            if let index = confirmedForRanking.firstIndex(where: { $0.id == game.id }) {
                                matchReviewRow(game: game, index: index)
                            }
                        }
                    }

                    if !alreadyRanked.isEmpty {
                        HStack {
                            Text("Already Ranked")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)

                        ForEach(alreadyRanked) { game in
                            if let index = confirmedForRanking.firstIndex(where: { $0.id == game.id }) {
                                matchReviewRow(game: game, index: index)
                                    .opacity(0.5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }

                    let unmatchedGames = matchedGames.filter {
                        selectedForRanking.contains($0.titleId) && !$0.isMatched
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

            VStack(spacing: 12) {
                Divider()
                Button { startRankingFromReview() } label: {
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

    private func matchReviewRow(game: MatchedPSNGame, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedForReview.contains(game.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(selectedForReview.contains(game.id) ? .primaryBlue : .silver)

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
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(Color.adaptiveSilver)
                            .font(.system(size: 14))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)

                if game.rawgTitle != nil && game.psnName.lowercased() != game.rawgTitle!.lowercased() {
                    Text("PSN: \(game.psnName)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(game.playtimeFormatted)
                    Text("•")
                    Text(game.platform)
                }
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            }

            Spacer()

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

    private func unmatchedReviewRow(game: MatchedPSNGame) -> some View {
        HStack(spacing: 12) {
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
                Text(game.psnName)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                Text("No match found")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.accentOrange)
            }

            Spacer()

            Button {
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
                    let swapped = MatchedPSNGame(
                        titleId: original.titleId,
                        psnName: original.psnName,
                        playtimeMinutes: original.playtimeMinutes,
                        platform: original.platform,
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
                    selectedForReview.insert(swapped.id)
                }
                showMatchSwapSearch = false
                swappingGameIndex = nil
            }
            .navigationTitle("Find Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showMatchSwapSearch = false
                        swappingGameIndex = nil
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
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
                    await MainActor.run { currentRankIndex += 1 }
                    await PendingImportManager.shared.updateIndex(
                        source: "psn_import",
                        currentIndex: currentRankIndex
                    )
                    if currentRankIndex >= gamesToRank.count {
                        await PendingImportManager.shared.delete(source: "psn_import")
                        if let userId = supabase.currentUser?.id {
                            _ = try? await supabase.client
                                .rpc("renormalize_ranks", params: [
                                    "p_user_id": AnyJSON.string(userId.uuidString)
                                ])
                                .execute()
                        }
                        AnalyticsService.shared.track(.psnImportCompleted, properties: [
                            "games_ranked": currentRankIndex
                        ])
                        debugLog("📊 PSN import complete: \(currentRankIndex) games ranked")
                        await MainActor.run { phase = .complete }
                        NotificationCenter.default.post(name: .didCompleteRanking, object: nil)
                    }
                }
            }
        )
        .interactiveDismissDisabled()
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button { dismiss() } label: {
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

                Button { showDiscardConfirmation = true } label: {
                    Text("Discard")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 8)
            }
            .confirmationDialog(
                "Discard this import?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard Import", role: .destructive) {
                    Task {
                        await PendingImportManager.shared.delete(source: "psn_import")
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
            Text("\(min(currentRankIndex, gamesToRank.count)) games imported and ranked")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            Spacer()
            Button { dismiss() } label: {
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
            Button { phase = .ready } label: {
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

    // MARK: - Helpers

    private func platformOrder(_ p: String) -> Int {
            switch p {
            case "PS5": return 0
            case "PS4": return 1
            case "PS3": return 2
            case "PS2": return 3
            case "PS Vita": return 4
            case "PSP": return 5
            default: return 6
            }
        }

    private func isGameAlreadyRanked(_ name: String) -> Bool {
        let normalize: (String) -> String = { str in
            str.lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)
                .replacingOccurrences(of: "™", with: "")
                .replacingOccurrences(of: "®", with: "")
                .replacingOccurrences(of: "3", with: "iii")
                .replacingOccurrences(of: "2", with: "ii")
                .replacingOccurrences(of: "4", with: "iv")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let normalized = normalize(name)
        for title in existingGameTitles {
            let normalizedTitle = normalize(title)
            if normalizedTitle == normalized { return true }
            if normalizedTitle.contains(normalized) || normalized.contains(normalizedTitle) { return true }
        }
        return false
    }

    // MARK: - Actions

    private func startAuth() async {
        // If already connected, skip straight to library fetch
        if let existingPsnId = await PSNService.shared.getPSNId() {
            // We still need a fresh access token — can't reuse from DB
            // Show the auth sheet so they can get a new NPSSO
            debugLog("ℹ️ PSN already connected (\(existingPsnId)), re-authenticating for fresh token")
            await MainActor.run {
                phase = .authenticating
                showPSNAuth = true
            }
            return
        }

        await MainActor.run {
            phase = .authenticating
            showPSNAuth = true
        }
    }

    private func handleNPSSO(_ npsso: String) async {
        do {
            let authResult = try await PSNService.shared.authenticate(npsso: npsso)
            psnAuthResult = authResult
            phase = .fetchingLibrary
            await fetchLibrary(authResult: authResult)
        } catch let error as PSNError {
            phase = .error(error.localizedDescription)
        } catch {
            phase = .error("Couldn't connect to PlayStation. Try again?")
        }
    }

    private func fetchLibrary(authResult: PSNAuthResult) async {
        do {
            libraryGames = try await PSNService.shared.fetchLibrary(
                accessToken: authResult.accessToken,
                psnAccountId: authResult.psnAccountId
            )

            if libraryGames.isEmpty {
                phase = .error("No played games found on your PSN account. Try logging some games manually?")
                return
            }

            await fetchExistingRankedIds()
            phase = .selectingGames

            // Auto-select games with substantial playtime
            let substantial = libraryGames.filter { $0.isSubstantialPlaytime && !isGameAlreadyRanked($0.name) }
            selectedForRanking = Set(substantial.map { $0.titleId })
        } catch let error as PSNError {
            phase = .error(error.localizedDescription)
        } catch {
            phase = .error("Couldn't load your PSN library. Check your connection and try again?")
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
                }
            }
            let rows: [Row] = try await supabase.client
                .from("user_games")
                .select("game_id, games(rawg_id, title)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            existingRawgIds = Set(rows.compactMap { $0.games?.rawg_id })
            existingGameTitles = Set(rows.compactMap {
                $0.games?.title.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            })
        } catch {
            debugLog("❌ Error fetching existing games: \(error)")
        }
    }

    private func toggleRanking(_ game: PSNLibraryGame) {
        if selectedForRanking.contains(game.titleId) {
            selectedForRanking.remove(game.titleId)
        } else {
            selectedForRanking.insert(game.titleId)
        }
    }

    private func toggleSelectAll() {
        let eligible = libraryGames.filter { !isGameAlreadyRanked($0.name) }
        if showSelectAll {
            for game in eligible { selectedForRanking.remove(game.titleId) }
        } else {
            for game in eligible { selectedForRanking.insert(game.titleId) }
        }
        showSelectAll.toggle()
    }

    private func startMatching() async {
        phase = .matchingGames
        let gamesToMatch = libraryGames.filter { selectedForRanking.contains($0.titleId) }

        do {
            matchedGames = try await PSNService.shared.matchGames(
                games: gamesToMatch,
                progressCallback: { completed, total in
                    matchProgress = (completed, total)
                }
            )

            confirmedForRanking = matchedGames.filter {
                selectedForRanking.contains($0.titleId) && $0.isMatched
            }
            selectedForReview = Set(
                confirmedForRanking
                    .filter { !isGameAlreadyRanked($0.displayTitle) && !isGameAlreadyRanked($0.psnName) }
                    .map { $0.id }
            )

            if confirmedForRanking.isEmpty {
                phase = .error("Couldn't match any of your selected games. Try different ones?")
                return
            }

            phase = .reviewingMatches
        } catch {
            debugLog("❌ PSN matching error: \(error)")
            phase = .error("Couldn't match your games right now. Check your connection and try again.")
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
                source: "psn_import",
                games: pendingGamesFromConfirmed(),
                currentIndex: 0
            )
            await refreshExistingGames()
            currentRankIndex = 0
            AnalyticsService.shared.track(.psnImportStarted, properties: [
                "game_count": gamesToRank.count
            ])
            phase = .ranking
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
                    "psn_title_id": game.titleId,
                    "psn_name": game.psnName,
                    "psn_playtime_minutes": String(game.playtimeMinutes),
                    "psn_platform": game.platform
                ]
            )
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
                let status: String?
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
                    status: GameStatus(rawValue: row.status ?? "played") ?? .played,
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

    private func saveImportedGame(game: MatchedPSNGame, position: Int) async -> Bool {
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
                    "p_platform_played": AnyJSON.array([AnyJSON.string(game.platform)]),
                    "p_notes": AnyJSON.string(""),
                    "p_canonical_game_id": AnyJSON.integer(canonicalId),
                    "p_batch_source": AnyJSON.string("psn_import")
                ])
                .execute()

            debugLog("✅ Imported \(game.displayTitle) at position \(position)")
            return true
        } catch {
            debugLog("❌ Error saving PSN game: \(error)")
            return false
        }
    }
}

// MARK: - PSN Game Row

struct PSNGameRow: View {
    let game: PSNLibraryGame
    let isSelected: Bool
    let isAlreadyRanked: Bool
    let isDimmed: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if !isAlreadyRanked {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .primaryBlue : .silver)
            }

            if let iconUrl = game.iconUrl, let url = URL(string: iconUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.secondaryBackground)
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(Color.adaptiveSilver)
                                .font(.system(size: 12))
                        )
                }
                .frame(width: 40, height: 40)
                .cornerRadius(6)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondaryBackground)
                    .frame(width: 40, height: 40)
                    .cornerRadius(6)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(Color.adaptiveSilver)
                            .font(.system(size: 12))
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(game.name)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)

                if isAlreadyRanked {
                    Text("Already ranked")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.teal)
                } else {
                    HStack(spacing: 4) {
                        Text(isDimmed ? "Under 1 hour" : game.playtimeFormatted)
                        Text("·")
                        Text(game.platform)
                    }
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(isAlreadyRanked ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isAlreadyRanked { onToggle() }
        }
        .allowsHitTesting(!isAlreadyRanked)
    }
}
