import SwiftUI
import UniformTypeIdentifiers
import Supabase

// MARK: - Import State
enum CSVImportPhase: Equatable {
    case ready
    case matching
    case reviewingMatches
    case ranking
    case complete
    case error(String)
}

struct CSVImportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager
    
    @State private var phase: CSVImportPhase = .ready
    @State private var parsedEntries: [CSVGameEntry] = []
    @State private var matchedGames: [MatchedCSVGame] = []
    @State private var matchProgress: (Int, Int) = (0, 0)
    @State private var existingRawgIds: Set<Int> = []
    @State private var existingGameTitles: Set<String> = []
    @State private var existingUserGames: [UserGame] = []
    
    // Review state
    @State private var confirmedForRanking: [MatchedCSVGame] = []
    @State private var selectedGameIds: Set<UUID> = []
    @State private var showMatchSwapSearch = false
    @State private var swappingGameIndex: Int?
    
    // Ranking state
    @State private var gamesToRank: [MatchedCSVGame] = []
    @State private var currentRankIndex = 0
    @State private var showDiscardConfirmation = false
    
    // File picker
    @State private var showFilePicker = false
        
    // Resume state
    var resumingImport: PendingImport? = nil
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    readyView
                case .matching:
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
            .navigationTitle("Import from CSV")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let pending = resumingImport {
                    debugLog("📋 Resuming import: \(pending.games.count) games, source=\(pending.source)")
                    for g in pending.games {
                        debugLog("📋 Pending game: '\(g.title)' metadata=\(g.sourceMetadata)")
                    }
                    gamesToRank = pending.games.map { g in
                        MatchedCSVGame(
                            csvTitle: g.sourceMetadata["csv_title"] ?? g.title,
                            csvPlatforms: g.sourceMetadata["csv_platforms"].map { $0.split(separator: ",").map(String.init) } ?? [],
                            csvNotes: g.sourceMetadata["csv_notes"],
                            rawgId: g.rawgId,
                            rawgTitle: g.title,
                            rawgCoverUrl: g.coverUrl,
                            rawgGenres: g.genres,
                            rawgPlatforms: g.platforms,
                            rawgReleaseDate: g.releaseDate,
                            rawgMetacriticScore: g.metacriticScore
                        )
                    }
                    currentRankIndex = pending.currentIndex
                    Task {
                        await refreshExistingGames()
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
        .background(Color(.systemGroupedBackground))
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    // MARK: - Ready View
    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.primaryBlue)
            
            Text("Import Games")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Got a list of games? Upload a CSV and rank them all at once.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Link(destination: URL(string: "https://playedit.app/template")!) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 14))
                    Text("Grab the template at playedit.app/template")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundColor(.primaryBlue)
            }
            
            Spacer()
            
            Button {
                showFilePicker = true
            } label: {
                Text("Choose CSV File")
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
    
    // MARK: - Matching View
    private var matchingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                .scaleEffect(1.5)
            Text("Matching games… \(matchProgress.0) of \(matchProgress.1)")
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
                    Text("Review Games")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    Text("\(selectedGameIds.count) selected to rank")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                Spacer()
                Button {
                    toggleSelectAll()
                } label: {
                    Text(selectedGameIds.count == selectableGames.count ? "Deselect All" : "Select All")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Matched games
                    ForEach(Array(confirmedForRanking.enumerated()), id: \.element.id) { index, game in
                        csvMatchReviewRow(game: game, index: index)
                    }
                    
                    // Already in library
                    let alreadyRanked = matchedGames.filter {
                        $0.isMatched && existingRawgIds.contains($0.rawgId!)
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
                            alreadyRankedRow(game: game)
                        }
                    }
                    
                    // Unmatched games
                    let unmatched = matchedGames.filter { !$0.isMatched }
                    if !unmatched.isEmpty {
                        HStack {
                            Text("No Match Found")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.secondaryBackground)
                        
                        ForEach(unmatched) { game in
                            unmatchedReviewRow(game: game)
                        }
                    }
                }
            }
            
            // Bottom bar
            VStack(spacing: 12) {
                Divider()
                
                // Summary
                let alreadyCount = matchedGames.filter { $0.isMatched && existingRawgIds.contains($0.rawgId!) }.count
                if alreadyCount > 0 {
                    Text("\(alreadyCount) already in your library")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                Button {
                    startRanking()
                } label: {
                    Text("Rank \(selectedGameIds.count) Games")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedGameIds.isEmpty)
                .opacity(selectedGameIds.isEmpty ? 0.4 : 1.0)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showMatchSwapSearch) {
            matchSwapSearchSheet
        }
    }
    
    // MARK: - Review Row (Matched)
    private func csvMatchReviewRow(game: MatchedCSVGame, index: Int) -> some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: selectedGameIds.contains(game.id) ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22))
                .foregroundColor(selectedGameIds.contains(game.id) ? .primaryBlue : .silver)
            
            // Cover art
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
                
                if !game.csvPlatforms.isEmpty {
                    Text(game.csvPlatforms.joined(separator: ", "))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                if let notes = game.csvNotes {
                    Text("📝 \(notes)")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .lineLimit(1)
                }
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
            toggleSelection(game)
        }
    }
    
    // MARK: - Review Row (Already Ranked)
    private func alreadyRankedRow(game: MatchedCSVGame) -> some View {
        HStack(spacing: 12) {
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
            
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                Text("Already ranked")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.teal)
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .opacity(0.5)
    }
    
    // MARK: - Review Row (Unmatched)
    private func unmatchedReviewRow(game: MatchedCSVGame) -> some View {
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
                Text(game.csvTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                Text("Not found — tap to search")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.accentOrange)
            }
            
            Spacer()
            
            Button {
                // Add placeholder so swap can target it
                confirmedForRanking.append(game)
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
    
    // MARK: - Match Swap Search Sheet
    private var matchSwapSearchSheet: some View {
        NavigationStack {
            MatchSwapSearchView { selectedGame in
                if let index = swappingGameIndex, index < confirmedForRanking.count {
                    let original = confirmedForRanking[index]
                    let swapped = MatchedCSVGame(
                        csvTitle: original.csvTitle,
                        csvPlatforms: original.csvPlatforms,
                        csvNotes: original.csvNotes,
                        rawgId: selectedGame.rawgId,
                        rawgTitle: selectedGame.title,
                        rawgCoverUrl: selectedGame.coverURL,
                        rawgGenres: selectedGame.genres,
                        rawgPlatforms: selectedGame.platforms,
                        rawgReleaseDate: selectedGame.releaseDate,
                        rawgMetacriticScore: selectedGame.metacriticScore
                    )
                    // Remove old selection, add new
                    selectedGameIds.remove(original.id)
                    confirmedForRanking[index] = swapped
                    selectedGameIds.insert(swapped.id)
                }
                showMatchSwapSearch = false
                swappingGameIndex = nil
            }
            .navigationTitle("Find Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // If we added an unmatched placeholder, remove it
                        if let index = swappingGameIndex, index < confirmedForRanking.count,
                           confirmedForRanking[index].rawgId == nil {
                            confirmedForRanking.remove(at: index)
                        }
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
                let game = gamesToRank[currentRankIndex]
                ComparisonView(
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
                                debugLog("🎮 CSV ranked game \(currentRankIndex) of \(gamesToRank.count): \(game.displayTitle)")
                            }
                            await PendingImportManager.shared.updateIndex(source: "csv_import", currentIndex: currentRankIndex)
                            if currentRankIndex >= gamesToRank.count {
                                await PendingImportManager.shared.delete(source: "csv_import")
                                if let userId = supabase.currentUser?.id {
                                    _ = try? await supabase.client
                                        .rpc("renormalize_ranks", params: [
                                            "p_user_id": AnyJSON.string(userId.uuidString)
                                        ])
                                        .execute()
                                }
                                AnalyticsService.shared.track(.csvImportCompleted, properties: [
                                    "games_ranked": currentRankIndex
                                ])
                                await MainActor.run {
                                    phase = .complete
                                    NotificationCenter.default.post(name: .didCompleteRanking, object: nil)
                                }
                            }
                        }
                    }
                )
                .id(currentRankIndex)
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
                                await PendingImportManager.shared.delete(source: "csv_import")
                                dismiss()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Your progress will be lost and the remaining games won't be ranked.")
                    }
                }
            } else {
                ProgressView()
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
            
            Text("\(gamesToRank.count) games imported and ranked")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            
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
    
    // MARK: - Helpers
    
    private var selectableGames: [MatchedCSVGame] {
        confirmedForRanking.filter { $0.isMatched }
    }
    
    private func toggleSelection(_ game: MatchedCSVGame) {
        if selectedGameIds.contains(game.id) {
            selectedGameIds.remove(game.id)
        } else {
            selectedGameIds.insert(game.id)
        }
    }
    
    private func toggleSelectAll() {
        if selectedGameIds.count == selectableGames.count {
            selectedGameIds.removeAll()
        } else {
            selectedGameIds = Set(selectableGames.map { $0.id })
        }
    }
    
    // MARK: - Pending Import Helpers
        
    private func pendingGamesFromConfirmed() -> [PendingImportGame] {
        gamesToRank.compactMap { game in
            guard let rawgId = game.rawgId else { return nil }
            var metadata: [String: String] = [
                "csv_title": game.csvTitle
            ]
            if !game.csvPlatforms.isEmpty {
                metadata["csv_platforms"] = game.csvPlatforms.joined(separator: ",")
            }
            if let notes = game.csvNotes {
                metadata["csv_notes"] = notes
            }
            return PendingImportGame(
                rawgId: rawgId,
                title: game.displayTitle,
                coverUrl: game.rawgCoverUrl,
                genres: game.rawgGenres,
                platforms: game.rawgPlatforms,
                releaseDate: game.rawgReleaseDate,
                metacriticScore: game.rawgMetacriticScore,
                sourceMetadata: metadata
            )
        }
    }
    
    // MARK: - Actions
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let fileURL = urls.first else { return }
            
            do {
                debugLog("📋 Parsing CSV from: \(fileURL.lastPathComponent)")
                parsedEntries = try CSVImportService.shared.parseCSV(from: fileURL)
                debugLog("📋 Parsed \(parsedEntries.count) entries: \(parsedEntries.map { "\($0.title) | \($0.platforms.isEmpty ? "no platform" : $0.platforms.joined(separator: ", "))" })")
                Task {
                    await fetchExistingRankedIds()
                    await startMatching()
                }
            } catch let error as CSVImportError {
                phase = .error(error.localizedDescription)
            } catch {
                phase = .error("Couldn't read this file. Make sure you're using the PlayedIt template.")
            }
            
        case .failure:
            // User cancelled the picker
            break
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
            existingGameTitles = Set(rows.compactMap { $0.games?.title.lowercased() })
        } catch {
            debugLog("❌ Error fetching existing games: \(error)")
        }
    }
    
    private func startMatching() async {
        phase = .matching
        
        do {
            matchedGames = try await CSVImportService.shared.matchGames(
                entries: parsedEntries,
                progressCallback: { completed, total in
                    matchProgress = (completed, total)
                }
            )
            
            // Build confirmed list: matched games NOT already in library
            confirmedForRanking = matchedGames.filter {
                $0.isMatched && !existingRawgIds.contains($0.rawgId!)
            }
            
            // Auto-select all matched games
            selectedGameIds = Set(confirmedForRanking.map { $0.id })
            
            if confirmedForRanking.isEmpty && matchedGames.allSatisfy({ !$0.isMatched }) {
                phase = .error("Couldn't match any of your games. Check the titles in your CSV and try again?")
                return
            }
            
            if confirmedForRanking.isEmpty {
                phase = .error("All games from this file are already in your library. Nothing new to rank!")
                return
            }
            
            phase = .reviewingMatches
            
        } catch {
            debugLog("❌ CSV matching error: \(error)")
            phase = .error("Couldn't match your games right now. Check your connection and try again.")
        }
    }
    
    private func startRanking() {
        gamesToRank = confirmedForRanking.filter { selectedGameIds.contains($0.id) }
        
        if gamesToRank.isEmpty {
            phase = .complete
            return
        }
        
        Task {
            await PendingImportManager.shared.save(
                source: "csv_import",
                games: pendingGamesFromConfirmed(),
                currentIndex: 0
            )
            await refreshExistingGames()
            currentRankIndex = 0
            AnalyticsService.shared.track(.csvImportStarted, properties: [
                "game_count": gamesToRank.count
            ])
            phase = .ranking
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
    
    private func saveImportedGame(game: MatchedCSVGame, position: Int) async -> Bool {
        debugLog("💾 saveImportedGame START: \(game.displayTitle) at position \(position)")
        guard let userId = supabase.currentUser?.id,
              let rawgId = game.rawgId else {
            debugLog("❌ saveImportedGame GUARD FAILED: userId=\(supabase.currentUser?.id.uuidString ?? "nil"), rawgId=\(game.rawgId?.description ?? "nil")")
            return false
        }
        debugLog("💾 userId=\(userId.uuidString), rawgId=\(rawgId), csvPlatforms=\(game.csvPlatforms), csvNotes=\(game.csvNotes ?? "nil")")
        
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
            
            debugLog("💾 Upserting game into games table...")
            try await supabase.client.from("games")
                .upsert(gameInsert, onConflict: "rawg_id")
                .execute()
            debugLog("💾 Upsert complete")
            
            struct GameIdResponse: Decodable { let id: Int }
            let gameRecord: GameIdResponse = try await supabase.client.from("games")
                .select("id")
                .eq("rawg_id", value: rawgId)
                .single()
                .execute()
                .value
            
            debugLog("💾 games table id=\(gameRecord.id), fetching canonical id...")
            let canonicalId = await RAWGService.shared.getParentGameId(for: rawgId) ?? rawgId
            debugLog("💾 canonicalId=\(canonicalId)")
            
            // Platform from CSV as array, or empty array if none
            let platformArray: [AnyJSON] = game.csvPlatforms.map { AnyJSON.string($0) }
            
            debugLog("💾 platformArray=\(platformArray)")
            
            try await supabase.client
                .rpc("insert_game_at_rank", params: [
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_game_id": AnyJSON.integer(gameRecord.id),
                    "p_rank": AnyJSON.integer(position),
                    "p_platform_played": AnyJSON.array(platformArray),
                    "p_notes": AnyJSON.string(game.csvNotes ?? ""),
                    "p_canonical_game_id": AnyJSON.integer(canonicalId),
                    "p_batch_source": AnyJSON.string("csv_import")
                ])
                .execute()
            
            debugLog("✅ CSV imported \(game.displayTitle) at position \(position)")
            return true
            
        } catch {
            debugLog("❌ Error saving CSV imported game: \(error)")
            debugLog("❌ Full error: \(String(describing: error))")
            return false
        }
    }
}
