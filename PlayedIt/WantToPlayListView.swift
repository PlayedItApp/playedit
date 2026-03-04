import SwiftUI
internal import PostgREST
import Supabase

extension Notification.Name {
    static let wantToPlayShouldRefresh = Notification.Name("wantToPlayShouldRefresh")
}

struct WantToPlayListView: View {
    @ObservedObject private var manager = WantToPlayManager.shared
    @State private var rankedGames: [WantToPlayGame] = []
    @State private var unrankedGames: [WantToPlayGame] = []
    @State private var isLoading = true
    @State private var showResetAlert = false
    @State private var showRankAll = false
    @State private var gameToRank: WantToPlayGame? = nil
    @State private var rankAllQueue: [WantToPlayGame] = []
    @State private var isRankingAll = false
    @State private var gameToPlace: WantToPlayGame? = nil
    @State private var gameToReorder: WantToPlayGame? = nil
    @State private var showRankAllSheet = false
    @State private var predictions: [String: GamePrediction] = [:]  // keyed by WantToPlayGame.id
    @State private var gameMetadata: [Int: (releaseYear: Int?, platforms: [String]?)] = [:]  // keyed by gameId
    @State private var predictionContext: PredictionContext? = nil
    @State private var showRecommendations = false
    @State private var rankedGameCount: Int = 0
    @State private var selectedGame: WantToPlayGame? = nil
    @State private var gameToLog: WantToPlayGame? = nil
    @State private var lastLoggedGame: WantToPlayGame? = nil
    @State private var gameToLogResolved: Game? = nil
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    .padding(.top, 40)
            } else if rankedGames.isEmpty && unrankedGames.isEmpty {
                emptyState
            } else {
                gameListContent
            }
        }
        .task {
            await loadGames()
            await fetchMetadata()
            await fetchPredictions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .wantToPlayShouldRefresh)) { _ in
            Task { await loadGames() }
        }
        .sheet(isPresented: $showRankAllSheet, onDismiss: {
            isRankingAll = false
            rankAllQueue = []
        }) {
            RankAllFlowView(
                unrankedGames: unrankedGames,
                initialRankedGames: rankedGames,
                manager: manager,
                onAllComplete: {
                    showRankAllSheet = false
                    Task { await loadGames() }
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $gameToRank) { game in
            let mgr = manager
            WantToPlayComparisonView(
                newGame: game,
                existingRankedGames: rankedGames,
                onComplete: { position in
                    Task {
                        debugLog("🎯 onComplete fired: placing \(game.gameTitle) (id: \(game.id)) at position \(position)")
                        let _ = await mgr.placeGameAtPosition(gameId: game.id, position: position)
                        await loadGames()
                    }
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $gameToReorder) { game in
            ReorderPositionSheet(game: game, rankedGames: rankedGames) { newPosition in
                Task {
                    if let oldPosition = game.sortPosition {
                        let _ = await manager.moveGame(gameId: game.id, from: oldPosition, to: newPosition)
                    }
                    await loadGames()
                }
            }
        }
        .sheet(item: $gameToPlace) { game in
            PlaceAtPositionSheet(game: game, rankedGames: rankedGames) { position in
                Task {
                    let _ = await manager.placeGameAtPosition(gameId: game.id, position: position)
                    await loadGames()
                }
            }
        }
        .alert("Reset priority list?", isPresented: $showResetAlert) {
            Button("Reset", role: .destructive) {
                Task {
                    let _ = await manager.resetAllRankings()
                    await loadGames()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all priority ordering. Your games stay, just the order gets wiped.")
        }
        .sheet(item: $selectedGame) { game in
            WantToPlayDetailSheet(game: game, prediction: predictions[game.id], myGameCount: predictionContext?.myGameCount ?? 0)
        }
        .sheet(item: $gameToLog, onDismiss: {
            Task {
                if let game = lastLoggedGame {
                    let _ = await manager.removeGame(gameId: game.gameId)
                }
                await loadGames()
                NotificationCenter.default.post(name: NSNotification.Name("profileShouldRefresh"), object: nil)
            }
        }) { game in
            GameLogView(game: gameToLogResolved ?? game.toGame(), source: "want_to_play")
                .presentationBackground(Color.appBackground)
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            if rankedGameCount >= 10 {
                recommendationsBanner
                    .padding(.horizontal, 16)
            }
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Bookmark games from your friends' lists or search to get started.")
                .font(.subheadline)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }
    
    // MARK: - Game List Content
    private var gameListContent: some View {
        VStack(spacing: 12) {
            // Recommendations banner
            if rankedGameCount >= 10 {
                recommendationsBanner
            }
            
            // Ranked section
            if !rankedGames.isEmpty {
                rankedSection
            }
            
            // Unranked section
            if !unrankedGames.isEmpty {
                unrankedSection
            }
        }
    }
    
    // MARK: - Ranked Section
    private var rankedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primaryBlue)
                Text("Prioritized")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("(\(rankedGames.count))")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                Spacer()
                
                Menu {
                    if unrankedGames.count >= 2 {
                        Button {
                            startRankAll()
                        } label: {
                            Label("Rank all unranked", systemImage: "list.number")
                        }
                    }
                    
                    if !rankedGames.isEmpty {
                        Button(role: .destructive) {
                            showResetAlert = true
                        } label: {
                            Label("Reset priority order", systemImage: "arrow.counterclockwise")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundColor(.primaryBlue)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            
            ForEach(rankedGames) { game in
                WantToPlayRankedRow(game: game, isReordering: false, onRemove: {
                    Task {
                        await loadGames()
                    }
                }, onUnrank: {
                    Task {
                        let _ = await manager.unrankGame(gameId: game.id)
                        await loadGames()
                    }
                }, onReorder: {
                    gameToReorder = game
                }, prediction: predictions[game.id], myGameCount: predictionContext?.myGameCount ?? 0, releaseYear: gameMetadata[game.gameId]?.releaseYear, platforms: gameMetadata[game.gameId]?.platforms, onTap: {
                        selectedGame = game
                    })
            }
        }
    }
    
    // MARK: - Recommendations Banner
    private var recommendationsBanner: some View {
        Button {
            showRecommendations = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.accentOrange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommended For You")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    Text("Based on your taste")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.adaptiveSilver)
            }
            .padding(14)
            .background(Color.cardBackground) 
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .sheet(isPresented: $showRecommendations, onDismiss: {
            Task {
                await loadGames()
                await fetchPredictions()
            }
        }) {
            RecommendationsView()
        }
    }
    
    // MARK: - Controls Bar
    private var controlsBar: some View {
        HStack {
            Spacer()
            
            Menu {
                if unrankedGames.count >= 2 {
                    Button {
                        startRankAll()
                    } label: {
                        Label("Rank all unranked", systemImage: "list.number")
                    }
                }
                
                if !rankedGames.isEmpty {
                    Button(role: .destructive) {
                        showResetAlert = true
                    } label: {
                        Label("Reset priority order", systemImage: "arrow.counterclockwise")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.primaryBlue)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
    }
    
    // MARK: - Unranked Section
        private var unrankedSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.adaptiveGray)
                    Text("Backlog")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text("(\(unrankedGames.count))")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                ForEach(unrankedGames) { game in
                    WantToPlayUnrankedRow(game: game, hasRankedGames: !rankedGames.isEmpty, prediction: predictions[game.id], myGameCount: predictionContext?.myGameCount ?? 0, releaseYear: gameMetadata[game.gameId]?.releaseYear, platforms: gameMetadata[game.gameId]?.platforms, onRemove: {
                        Task {
                            let _ = await manager.removeGame(gameId: game.gameId)
                            await loadGames()
                        }
                    }, onRank: {
                        debugLog("🎯 Ranking: \(game.gameTitle), against \(rankedGames.map { $0.gameTitle })")
                        if rankedGames.isEmpty {
                            // First game - just place at #1, no sheet
                            Task {
                                let _ = await manager.placeGameAtPosition(gameId: game.id, position: 1)
                                await loadGames()
                            }
                        } else {
                            gameToRank = game
                        }
                    }, onPlaceAtPosition: {
                        gameToPlace = game
                    }, onPlaceAtBottom: {
                        Task {
                            let nextPosition = (rankedGames.last?.sortPosition ?? 0) + 1
                            let _ = await manager.placeGameAtPosition(gameId: game.id, position: nextPosition)
                            await loadGames()
                        }
                    }, onRankGame: {
                        lastLoggedGame = game
                        gameToLog = game
                        Task {
                            gameToLogResolved = await resolveGame(from: game)
                        }
                    }, onTap: {
                        selectedGame = game
                    })
                }
            }
        }
    
    // MARK: - Resolve Game
    private func resolveGame(from wtpGame: WantToPlayGame) async -> Game {
        struct GameRow: Decodable { let id: Int; let rawg_id: Int }
        let rows: [GameRow] = (try? await SupabaseManager.shared.client
            .from("games")
            .select("id, rawg_id")
            .eq("id", value: wtpGame.gameId)
            .limit(1)
            .execute()
            .value) ?? []
        let rawgId = rows.first?.rawg_id ?? wtpGame.gameId
        return Game(
            id: wtpGame.gameId,
            rawgId: rawgId,
            title: wtpGame.gameTitle,
            coverURL: wtpGame.gameCoverUrl,
            genres: [], platforms: [], releaseDate: nil,
            metacriticScore: nil, added: nil, rating: nil,
            gameDescription: nil, gameDescriptionHtml: nil, tags: []
        )
    }
    
    // MARK: - Rank All
    private func startRankAll() {
        showRankAllSheet = true
    }
    
    // MARK: - Metadata
    private func fetchMetadata() async {
        let allGames = rankedGames + unrankedGames
        guard !allGames.isEmpty else { return }
        let gameIds = allGames.map { $0.gameId }
        
        struct GameMeta: Decodable {
            let id: Int
            let curated_release_year: Int?
            let curated_platforms: [String]?
        }
        
        do {
            let rows: [GameMeta] = try await SupabaseManager.shared.client
                .from("games")
                .select("id, curated_release_year, curated_platforms")
                .in("id", values: gameIds)
                .execute()
                .value
            
            for row in rows {
                gameMetadata[row.id] = (releaseYear: row.curated_release_year, platforms: row.curated_platforms)
            }
        } catch {
            debugLog("⚠️ Metadata fetch failed: \(error)")
        }
    }
    
    // MARK: - Predictions
    private func fetchPredictions() async {
        guard let context = await PredictionEngine.buildContext() else { return }
        predictionContext = context
        
        let allGames = rankedGames + unrankedGames
            guard !allGames.isEmpty else { return }
            
            let gameIds = allGames.map { $0.gameId }
            
            struct GameInfo: Decodable {
                let id: Int
                let rawg_id: Int
                let genres: [String]?
                let tags: [String]?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let metacritic_score: Int?
            }
            
            do {
                let infos: [GameInfo] = try await SupabaseManager.shared.client
                    .from("games")
                    .select("id, rawg_id, genres, tags, curated_genres, curated_tags, metacritic_score")
                    .in("id", values: gameIds)
                    .execute()
                    .value
                
                let infoMap = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })
                
                for game in allGames {
                    guard let info = infoMap[game.gameId] else { continue }
                    
                    let target = PredictionTarget(
                        rawgId: info.rawg_id,
                        canonicalGameId: nil,
                        genres: info.curated_genres ?? info.genres ?? [],
                        tags: info.curated_tags ?? info.tags ?? [],
                        metacriticScore: info.metacritic_score
                    )
                    
                    if let pred = PredictionEngine.shared.predict(game: target, context: context) {
                        predictions[game.id] = pred
                        debugLog("🎯 WTP prediction: \(game.gameTitle) = \(Int(pred.predictedPercentile))% [\(pred.confidenceLabel)]")
                    }
                }
            } catch {
                debugLog("⚠️ Batch prediction fetch failed: \(error)")
            }
    }
    
    // MARK: - Load Games
    func loadGames() async {
        rankedGames = await manager.fetchRankedList()
        unrankedGames = await manager.fetchUnrankedList()
        
        // Prefetch cover art
        let allCovers = (rankedGames + unrankedGames).compactMap { $0.gameCoverUrl }
        ImageCache.shared.prefetch(urls: allCovers)
        
        isLoading = false
        
        // Check ranked game count for recommendations eligibility
        if let userId = SupabaseManager.shared.currentUser?.id {
            struct CountRow: Decodable { let game_id: Int }
            if let rows = try? await SupabaseManager.shared.client
                .from("user_games")
                .select("game_id")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value as [CountRow] {
                rankedGameCount = rows.count
            }
        }
    }
}

// MARK: - Ranked Row
struct WantToPlayRankedRow: View {
    let game: WantToPlayGame
    let isReordering: Bool
    let onRemove: () -> Void
    let onUnrank: () -> Void
    var onReorder: () -> Void = {}
    var prediction: GamePrediction? = nil
    var myGameCount: Int = 0
    var releaseYear: Int? = nil
    var platforms: [String]? = nil
    
    var onTap: () -> Void = {}
        
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            CachedAsyncImage(url: game.gameCoverUrl) {
                GameArtworkPlaceholder(genre: nil, size: .medium)
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(2)
                
                if releaseYear != nil || (platforms != nil && !platforms!.isEmpty) {
                    Text([
                        releaseYear.map { String($0) == "9999" ? "TBA" : String($0) },
                        platforms?.prefix(3).joined(separator: " · ")
                    ].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .lineLimit(1)
                }
                
                if let pred = prediction, myGameCount >= 5, pred.predictedPercentile >= 65 || pred.predictedPercentile < 40 {
                    Text("PlayedIt Prediction: \(pred.summaryText)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(predictionColor(pred))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(predictionColor(pred).opacity(0.4), lineWidth: 1)
                        )
                }
            }
            
            Spacer()
            
            if !isReordering {
                Menu {
                    Button {
                        onReorder()
                    } label: {
                        Label("Change position", systemImage: "arrow.up.arrow.down")
                    }
                    
                    Button {
                        onUnrank()
                    } label: {
                        Label("Move to backlog", systemImage: "arrow.down.to.line")
                    }
                    
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.adaptiveGray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(Color.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
        
        private func predictionColor(_ pred: GamePrediction) -> Color {
        switch pred.predictedPercentile {
        case 65...100: return Color(red: 0.25, green: 0.55, blue: 0.42)
        case 40..<65: return .silver
        default: return .slate
        }
    }
}

// MARK: - Unranked Row
struct WantToPlayUnrankedRow: View {
    let game: WantToPlayGame
    let hasRankedGames: Bool
    var prediction: GamePrediction? = nil
    var myGameCount: Int = 0
    var releaseYear: Int? = nil
    var platforms: [String]? = nil
    let onRemove: () -> Void
    let onRank: () -> Void
    let onPlaceAtPosition: () -> Void
    let onPlaceAtBottom: () -> Void
    var onRankGame: () -> Void = {}
    
    var onTap: () -> Void = {}
        
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            CachedAsyncImage(url: game.gameCoverUrl) {
                GameArtworkPlaceholder(genre: nil, size: .medium)
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info + rank button
            VStack(alignment: .leading, spacing: 6) {
                Text(game.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(2)
                
                if let year = releaseYear {
                    Text(year == 9999 ? "TBA" : String(year))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                if let platforms = platforms, !platforms.isEmpty {
                    let used = (SupabaseManager.shared.currentUser?.id).map { GameLogView.usedPlatforms(for: $0) } ?? []
                    let sorted = platforms.sorted { a, b in
                        let aUsed = used.contains(a)
                        let bUsed = used.contains(b)
                        if aUsed != bUsed { return aUsed }
                        return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
                    }
                    Text(sorted.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray.opacity(0.7))
                        .lineLimit(1)
                }
                
                if let pred = prediction, myGameCount >= 5, pred.predictedPercentile >= 65 || pred.predictedPercentile < 40 {
                        Text("PlayedIt Prediction: \(pred.summaryText)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(predictionColor(pred))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(predictionColor(pred).opacity(0.4), lineWidth: 1)
                            )
                    }
                    
                    HStack(spacing: 6) {
                        Button(action: onRank) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Prioritize")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.primaryBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primaryBlue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        Button(action: onRankGame) {
                            HStack(spacing: 4) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Rank It")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.accentOrange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentOrange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
            
            Spacer()
            
            // More options
            Menu {
                if hasRankedGames {
                    Button {
                        onPlaceAtPosition()
                    } label: {
                        Label("Place at position...", systemImage: "arrow.right.to.line")
                    }
                    
                    Button {
                        onPlaceAtBottom()
                    } label: {
                        Label("Add to end of priority list", systemImage: "text.append")
                    }
                }
                
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.adaptiveGray)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(Color.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func predictionColor(_ pred: GamePrediction) -> Color {
        switch pred.predictedPercentile {
        case 65...100: return Color(red: 0.25, green: 0.55, blue: 0.42)
        case 40..<65: return .silver
        default: return .slate
        }
    }
}

// MARK: - Want to Play Comparison View
struct WantToPlayComparisonView: View {
    let newGame: WantToPlayGame
    let existingRankedGames: [WantToPlayGame]
    let onComplete: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var lowIndex = 0
    @State private var highIndex = 0
    @State private var currentOpponent: WantToPlayGame?
    @State private var comparisonCount = 0
    @State private var finalPosition: Int?
    @State private var showCards = false
    @State private var selectedSide: String? = nil
    @State private var comparisonHistory: [ComparisonState] = []
    @State private var showCancelAlert = false
    
    struct ComparisonState {
        let lowIndex: Int
        let highIndex: Int
        let comparisonCount: Int
    }
    
    private let maxComparisons = 10
    
    private let prompts = [
        "Which do you want to play more?",
        "Tough call... which one first?",
        "If you could only play one next...",
        "Priority check: your pick?"
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) { }
                    .padding(.top, 12)
                
                if finalPosition == nil {
                    Text(prompts[comparisonCount % prompts.count])
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                
                if let opponent = currentOpponent {
                    HStack(spacing: 8) {
                        // New game (left)
                        GameComparisonCard(
                            title: newGame.gameTitle,
                            coverURL: newGame.gameCoverUrl,
                            year: "",
                            isHighlighted: selectedSide == "left"
                        ) {
                            selectGame(side: "left")
                        }
                        .opacity(showCards ? 1 : 0)
                        .offset(x: showCards ? 0 : -50)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showCards)
                        
                        PixelVS()
                            .opacity(showCards ? 1 : 0)
                            .scaleEffect(showCards ? 1 : 0.5)
                            .animation(.spring(response: 0.4).delay(0.2), value: showCards)
                        
                        // Existing game (right)
                        GameComparisonCard(
                            title: opponent.gameTitle,
                            coverURL: opponent.gameCoverUrl,
                            year: "",
                            isHighlighted: selectedSide == "right"
                        ) {
                            selectGame(side: "right")
                        }
                        .opacity(showCards ? 1 : 0)
                        .offset(x: showCards ? 0 : 50)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: showCards)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    Text("Tap the game you want to play first")
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                        .padding(.bottom, 24)
                    
                } else if finalPosition != nil {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    Spacer()
                }
            }
            .navigationTitle("Prioritize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if finalPosition == nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showCancelAlert = true
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            undoLastComparison()
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .foregroundColor(comparisonHistory.isEmpty ? .gray : .primaryBlue)
                        .disabled(comparisonHistory.isEmpty)
                    }
                }
            }
            .alert("Cancel?", isPresented: $showCancelAlert) {
                Button("Keep Going", role: .cancel) { }
                Button("Cancel", role: .destructive) { dismiss() }
            } message: {
                Text("This game won't be added to your priority list.")
            }
            .onAppear {
                setupComparison()
            }
        }
    }
    
    private func setupComparison() {
        guard !existingRankedGames.isEmpty else {
            finalPosition = 1
            currentOpponent = nil
            return
        }
        
        lowIndex = 0
        highIndex = existingRankedGames.count - 1
        comparisonCount = 0
        nextComparison()
    }
    
    private func nextComparison() {
        showCards = false
        selectedSide = nil
        
        if lowIndex > highIndex || comparisonCount >= maxComparisons {
            let position = lowIndex + 1
            finalPosition = position
            currentOpponent = nil
            onComplete(position)
            dismiss()
            return
        }
        
        let midIndex = (lowIndex + highIndex) / 2
        currentOpponent = existingRankedGames[midIndex]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showCards = true
        }
    }
    
    private func selectGame(side: String) {
        selectedSide = side
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            comparisonHistory.append(ComparisonState(
                lowIndex: lowIndex,
                highIndex: highIndex,
                comparisonCount: comparisonCount
            ))
            
            let midIndex = (lowIndex + highIndex) / 2
            if side == "left" {
                highIndex = midIndex - 1
            } else {
                lowIndex = midIndex + 1
            }
            comparisonCount += 1
            nextComparison()
        }
    }
    
    private func undoLastComparison() {
        guard let lastState = comparisonHistory.popLast() else { return }
        lowIndex = lastState.lowIndex
        highIndex = lastState.highIndex
        comparisonCount = lastState.comparisonCount
        finalPosition = nil
        nextComparison()
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

// MARK: - Place at Position Sheet
struct PlaceAtPositionSheet: View {
    let game: WantToPlayGame
    let rankedGames: [WantToPlayGame]
    let onPlace: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var orderedGames: [WantToPlayGame] = []
    @State private var hasPlaced = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    CachedAsyncImage(url: game.gameCoverUrl) {
                        GameArtworkPlaceholder(genre: nil, size: .small)
                    }
                    .frame(width: 40, height: 53)
                    .cornerRadius(4)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.gameTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        Text("Drag to your desired position")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.accentOrange.opacity(0.08))
                
                // Drag-to-reorder list
                List {
                    ForEach(orderedGames) { item in
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: item.gameCoverUrl) {
                                GameArtworkPlaceholder(genre: nil, size: .small)
                            }
                            .frame(width: 40, height: 53)
                            .cornerRadius(4)
                            .clipped()
                            
                            Text(item.gameTitle)
                                .font(.system(size: 15, weight: item.id == game.id ? .bold : .regular, design: .rounded))
                                .foregroundColor(item.id == game.id ? .accentOrange : .slate)
                                .lineLimit(2)
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(item.id == game.id ? Color.accentOrange.opacity(0.08) : Color.clear)
                    }
                    .onMove(perform: moveGame)
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
                
                // Save button
                Button {
                    if let newIndex = orderedGames.firstIndex(where: { $0.id == game.id }) {
                        onPlace(newIndex + 1)
                    }
                    dismiss()
                } label: {
                    Text("Save Position")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .navigationTitle("Choose Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            // Insert the new game at the end of the ranked list
            orderedGames = rankedGames + [game]
        }
    }
    
    private func moveGame(from source: IndexSet, to destination: Int) {
        orderedGames.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - Reorder Position Sheet
struct ReorderPositionSheet: View {
    let game: WantToPlayGame
    let rankedGames: [WantToPlayGame]
    let onPlace: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var orderedGames: [WantToPlayGame] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CachedAsyncImage(url: game.gameCoverUrl) {
                        GameArtworkPlaceholder(genre: nil, size: .small)
                    }
                    .frame(width: 40, height: 53)
                    .cornerRadius(4)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.gameTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        Text("Drag to new position")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.primaryBlue.opacity(0.08))
                
                List {
                    ForEach(orderedGames) { item in
                        HStack(spacing: 12) {
                            CachedAsyncImage(url: item.gameCoverUrl) {
                                GameArtworkPlaceholder(genre: nil, size: .small)
                            }
                            .frame(width: 40, height: 53)
                            .cornerRadius(4)
                            .clipped()
                            
                            Text(item.gameTitle)
                                .font(.system(size: 15, weight: item.id == game.id ? .bold : .regular, design: .rounded))
                                .foregroundColor(item.id == game.id ? .primaryBlue : .slate)
                                .lineLimit(2)
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(item.id == game.id ? Color.primaryBlue.opacity(0.08) : Color.clear)
                    }
                    .onMove(perform: moveGame)
                }
                .listStyle(.plain)
                .environment(\.editMode, .constant(.active))
                
                Button {
                    if let newIndex = orderedGames.firstIndex(where: { $0.id == game.id }) {
                        onPlace(newIndex + 1)
                    }
                    dismiss()
                } label: {
                    Text("Save Position")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
            .navigationTitle("Change Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            orderedGames = rankedGames
        }
    }
    
    private func moveGame(from source: IndexSet, to destination: Int) {
        orderedGames.move(fromOffsets: source, toOffset: destination)
    }
}

// MARK: - First Two Comparison View
struct FirstTwoComparisonView: View {
    let game1: WantToPlayGame
    let game2: WantToPlayGame
    let onComplete: (WantToPlayGame, WantToPlayGame) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var showCards = false
    @State private var selectedSide: String? = nil
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Which do you want to play more?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                
                HStack(spacing: 8) {
                    GameComparisonCard(
                        title: game1.gameTitle,
                        coverURL: game1.gameCoverUrl,
                        year: "",
                        isHighlighted: selectedSide == "left"
                    ) {
                        selectGame(side: "left")
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(x: showCards ? 0 : -50)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showCards)
                    
                    PixelVS()
                        .opacity(showCards ? 1 : 0)
                        .scaleEffect(showCards ? 1 : 0.5)
                        .animation(.spring(response: 0.4).delay(0.2), value: showCards)
                    
                    GameComparisonCard(
                        title: game2.gameTitle,
                        coverURL: game2.gameCoverUrl,
                        year: "",
                        isHighlighted: selectedSide == "right"
                    ) {
                        selectGame(side: "right")
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(x: showCards ? 0 : 50)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: showCards)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                
                Spacer()
                
                Text("This sets your #1 and #2 priority")
                    .font(.caption)
                    .foregroundStyle(Color.adaptiveGray)
                    .padding(.bottom, 24)
            }
            .navigationTitle("Prioritize")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showCards = true
            }
        }
    }
    
    private func selectGame(side: String) {
            selectedSide = side
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if side == "left" {
                    onComplete(game1, game2)
                } else {
                    onComplete(game2, game1)
                }
                dismiss()
            }
        }
    }

    // MARK: - Rank All Flow View
    struct RankAllFlowView: View {
        let unrankedGames: [WantToPlayGame]
        let initialRankedGames: [WantToPlayGame]
        let manager: WantToPlayManager
        let onAllComplete: () -> Void
        
        @Environment(\.dismiss) var dismiss
        @State private var queue: [WantToPlayGame] = []
        @State private var rankedGames: [WantToPlayGame] = []
        @State private var currentGame: WantToPlayGame?
        @State private var phase: Phase = .loading
        @State private var showCancelAlert = false
        
        // Comparison state
        @State private var lowIndex = 0
        @State private var highIndex = 0
        @State private var comparisonCount = 0
        @State private var currentOpponent: WantToPlayGame?
        @State private var showCards = false
        @State private var selectedSide: String? = nil
        @State private var comparisonHistory: [ComparisonState] = []
        
        struct ComparisonState {
            let lowIndex: Int
            let highIndex: Int
            let comparisonCount: Int
        }
        
        enum Phase {
            case loading
            case firstTwo(WantToPlayGame, WantToPlayGame)
            case comparing
            case done
        }
        
        private let maxComparisons = 10
        
        private let prompts = [
            "Which do you want to play more?",
            "Tough call... which one first?",
            "If you could only play one next...",
            "Priority check: your pick?"
        ]
        
        var body: some View {
            NavigationStack {
                VStack(spacing: 16) {
                    // Progress bar
                    if case .done = phase { } else {
                        let total = unrankedGames.count
                        let remaining = queue.count + (currentGame != nil ? 1 : 0)
                        let completed = total - remaining
                        
                        VStack(spacing: 4) {
                            ProgressView(value: Double(completed), total: Double(total))
                                .tint(.primaryBlue)
                                .padding(.horizontal, 20)
                            
                            Text("\(completed)/\(total) ranked")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                        }
                        .padding(.top, 12)
                    }
                    
                    switch phase {
                    case .loading:
                        Spacer()
                        ProgressView()
                        Spacer()
                        
                    case .firstTwo(let game1, let game2):
                        firstTwoView(game1: game1, game2: game2)
                        
                    case .comparing:
                        comparisonView
                        
                    case .done:
                        doneView
                    }
                }
                .navigationTitle("Rank All")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if case .done = phase {
                            EmptyView()
                        } else {
                            Button("Cancel") {
                                showCancelAlert = true
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if case .comparing = phase {
                            Button {
                                undoLastComparison()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .foregroundColor(comparisonHistory.isEmpty ? .gray : .primaryBlue)
                            .disabled(comparisonHistory.isEmpty)
                        }
                    }
                }
                .alert("Stop ranking?", isPresented: $showCancelAlert) {
                    Button("Keep Going", role: .cancel) { }
                    Button("Stop", role: .destructive) { dismiss() }
                } message: {
                    Text("Games you've already ranked will keep their positions.")
                }
            }
            .onAppear {
                setupFlow()
            }
        }
        
        // MARK: - First Two View
        private func firstTwoView(game1: WantToPlayGame, game2: WantToPlayGame) -> some View {
            VStack(spacing: 16) {
                Text("Which do you want to play more?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                
                HStack(spacing: 8) {
                    GameComparisonCard(
                        title: game1.gameTitle,
                        coverURL: game1.gameCoverUrl,
                        year: "",
                        isHighlighted: selectedSide == "left"
                    ) {
                        selectFirstTwo(side: "left", game1: game1, game2: game2)
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(x: showCards ? 0 : -50)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showCards)
                    
                    PixelVS()
                        .opacity(showCards ? 1 : 0)
                        .scaleEffect(showCards ? 1 : 0.5)
                        .animation(.spring(response: 0.4).delay(0.2), value: showCards)
                    
                    GameComparisonCard(
                        title: game2.gameTitle,
                        coverURL: game2.gameCoverUrl,
                        year: "",
                        isHighlighted: selectedSide == "right"
                    ) {
                        selectFirstTwo(side: "right", game1: game1, game2: game2)
                    }
                    .opacity(showCards ? 1 : 0)
                    .offset(x: showCards ? 0 : 50)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: showCards)
                }
                .padding(.horizontal, 12)
                .padding(.top, 16)
                
                Spacer()
                
                Text("This sets your #1 and #2 priority")
                    .font(.caption)
                    .foregroundStyle(Color.adaptiveGray)
                    .padding(.bottom, 24)
            }
        }
        
        // MARK: - Comparison View
        private var comparisonView: some View {
            VStack(spacing: 16) {
                if let opponent = currentOpponent, let game = currentGame {
                    Text(prompts[comparisonCount % prompts.count])
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    HStack(spacing: 8) {
                        GameComparisonCard(
                            title: game.gameTitle,
                            coverURL: game.gameCoverUrl,
                            year: "",
                            isHighlighted: selectedSide == "left"
                        ) {
                            selectGame(side: "left")
                        }
                        .opacity(showCards ? 1 : 0)
                        .offset(x: showCards ? 0 : -50)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showCards)
                        
                        PixelVS()
                            .opacity(showCards ? 1 : 0)
                            .scaleEffect(showCards ? 1 : 0.5)
                            .animation(.spring(response: 0.4).delay(0.2), value: showCards)
                        
                        GameComparisonCard(
                            title: opponent.gameTitle,
                            coverURL: opponent.gameCoverUrl,
                            year: "",
                            isHighlighted: selectedSide == "right"
                        ) {
                            selectGame(side: "right")
                        }
                        .opacity(showCards ? 1 : 0)
                        .offset(x: showCards ? 0 : 50)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.15), value: showCards)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    
                    Spacer()
                    
                    Text("Tap the game you want to play first")
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                        .padding(.bottom, 24)
                } else {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    Spacer()
                }
            }
        }
        
        // MARK: - Done View
        private var doneView: some View {
            VStack(spacing: 16) {
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.success)
                
                Text("All ranked!")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("\(unrankedGames.count) games prioritized")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                Button("Done") {
                    onAllComplete()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 60)
                .padding(.top, 12)
                
                Spacer()
            }
        }
        
        // MARK: - Flow Logic
        private func setupFlow() {
            queue = unrankedGames
            rankedGames = initialRankedGames
            
            if rankedGames.isEmpty && queue.count >= 2 {
                let game1 = queue.removeFirst()
                let game2 = queue.removeFirst()
                phase = .firstTwo(game1, game2)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showCards = true
                }
            } else if rankedGames.isEmpty && queue.count == 1 {
                // Only one game, just place it
                let game = queue.removeFirst()
                Task {
                    let _ = await manager.placeGameAtPosition(gameId: game.id, position: 1)
                    rankedGames = await manager.fetchRankedList()
                    phase = .done
                }
            } else {
                startNextComparison()
            }
        }
        
        private func selectFirstTwo(side: String, game1: WantToPlayGame, game2: WantToPlayGame) {
            selectedSide = side
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let winner = side == "left" ? game1 : game2
                let loser = side == "left" ? game2 : game1
                
                Task {
                    let _ = await manager.placeGameAtPosition(gameId: winner.id, position: 1)
                    let _ = await manager.placeGameAtPosition(gameId: loser.id, position: 2)
                    rankedGames = await manager.fetchRankedList()
                    
                    startNextComparison()
                }
            }
        }
        
        private func startNextComparison() {
            guard !queue.isEmpty else {
                phase = .done
                return
            }
            
            let next = queue.removeFirst()
            currentGame = next
            comparisonHistory = []
            lowIndex = 0
            highIndex = rankedGames.count - 1
            comparisonCount = 0
            phase = .comparing
            nextComparison()
        }
        
        private func nextComparison() {
            showCards = false
            selectedSide = nil
            
            if lowIndex > highIndex || comparisonCount >= maxComparisons {
                let position = lowIndex + 1
                
                guard let game = currentGame else { return }
                Task {
                    let _ = await manager.placeGameAtPosition(gameId: game.id, position: position)
                    rankedGames = await manager.fetchRankedList()
                    
                    startNextComparison()
                }
                return
            }
            
            let midIndex = (lowIndex + highIndex) / 2
            currentOpponent = rankedGames[midIndex]
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showCards = true
            }
        }
        
        private func selectGame(side: String) {
            selectedSide = side
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                comparisonHistory.append(ComparisonState(
                    lowIndex: lowIndex,
                    highIndex: highIndex,
                    comparisonCount: comparisonCount
                ))
                
                let midIndex = (lowIndex + highIndex) / 2
                if side == "left" {
                    highIndex = midIndex - 1
                } else {
                    lowIndex = midIndex + 1
                }
                comparisonCount += 1
                nextComparison()
            }
        }
        
        private func undoLastComparison() {
            guard let lastState = comparisonHistory.popLast() else { return }
            lowIndex = lastState.lowIndex
            highIndex = lastState.highIndex
            comparisonCount = lastState.comparisonCount
            nextComparison()
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

    // MARK: - Want to Play Detail Sheet
    struct WantToPlayDetailSheet: View {
        let game: WantToPlayGame
        var prediction: GamePrediction? = nil
        var myGameCount: Int = 0
        
        @Environment(\.dismiss) private var dismiss
        @State private var gameDescription: String? = nil
        @State private var metacriticScore: Int? = nil
        @State private var curatedGenres: [String]? = nil
        @State private var curatedTags: [String]? = nil
        @State private var curatedPlatforms: [String]? = nil
        @State private var curatedReleaseYear: Int? = nil
        @State private var sourceFriendName: String? = nil
        @State private var releaseDate: String? = nil
        @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
        @State private var isLoadingFriendRankings = true
        @State private var showLogGame = false
        @State private var isAlreadyRanked = false
        @State private var showGameDataReport = false
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        GameInfoHeroView(
                            title: game.gameTitle,
                            coverURL: game.gameCoverUrl,
                            releaseDate: curatedReleaseYear.map { String($0) } ?? releaseDate,
                            metacriticScore: metacriticScore,
                            gameDescription: gameDescription,
                            curatedGenres: curatedGenres,
                            curatedTags: curatedTags,
                            curatedPlatforms: curatedPlatforms
                        )
                        
                        // Priority position
                        if let position = game.sortPosition {
                            Text("Priority #\(position)")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                        } else {
                            Text("In your backlog")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                        }
                        
                        // Prediction
                        if let pred = prediction, myGameCount >= 5, pred.predictedPercentile >= 65 || pred.predictedPercentile < 40 {
                            VStack(spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(pred.emoji)
                                    Text("PlayedIt Prediction: \(pred.summaryText)")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                }
                                
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
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.primaryBlue.opacity(0.08))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)
                        }
                        
                        // Source info
                        if let friendName = sourceFriendName ?? game.sourceFriendName {
                            HStack(spacing: 8) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.adaptiveGray)
                                Text("Bookmarked from \(friendName)'s list")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                            .padding(.horizontal, 24)
                        } else if game.source == "search" {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.adaptiveGray)
                                Text("Added from search")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        // Note
                        if let note = game.note, !note.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Note", systemImage: "note.text")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                                Text(note)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                        }
                        
                        // MARK: - Rank / Bookmark Actions
                        if !isAlreadyRanked {
                            VStack(spacing: 12) {
                                Text("Played it?")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                                
                                HStack(spacing: 10) {
                                    Button {
                                        showLogGame = true
                                    } label: {
                                        HStack {
                                            Image(systemName: "gamecontroller.fill")
                                            Text("Rank This Game")
                                        }
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.primaryBlue)
                                        .cornerRadius(12)
                                    }
                                    
                                    BookmarkButton(
                                        gameId: game.gameId,
                                        gameTitle: game.gameTitle,
                                        gameCoverUrl: game.gameCoverUrl,
                                        source: "want_to_play_detail"
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
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Color.primaryBlue.opacity(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.primaryBlue.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 16)
                        }
                        
                        // MARK: - Friends' Rankings
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
                                                    friendInitialsCircle(ranking.username, size: 32)
                                                }
                                                .frame(width: 32, height: 32)
                                                .clipShape(Circle())
                                            } else {
                                                friendInitialsCircle(ranking.username, size: 32)
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
                        } else if isLoadingFriendRankings {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                                .padding(.vertical, 12)
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
                        
                        Spacer()
                    }
                    .padding(.top, 24)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.adaptiveSilver)
                        }
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            Task {
                                await GameShareService.shared.shareGame(
                                    gameTitle: game.gameTitle,
                                    coverURL: game.gameCoverUrl,
                                    gameId: game.gameId
                                )
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundColor(.primaryBlue)
                        }
                    }
                }
                .sheet(isPresented: $showGameDataReport) {
                    ReportGameDataView(
                        gameId: game.gameId,
                        rawgId: game.gameId,
                        gameTitle: game.gameTitle
                    )
                    .presentationDetents([.medium, .large])
                }
                .sheet(isPresented: $showLogGame, onDismiss: {
                    Task {
                        await checkIfAlreadyRanked()
                        NotificationCenter.default.post(name: .wantToPlayShouldRefresh, object: nil)
                        if isAlreadyRanked {
                            NotificationCenter.default.post(name: NSNotification.Name("profileShouldRefresh"), object: nil)
                            dismiss()
                        }
                    }
                }) {
                    GameLogView(game: game.toGame(), source: "want_to_play")
                        .presentationBackground(Color.appBackground)
                }
                .task {
                    async let details: () = fetchGameDetails()
                    async let source: () = fetchSourceFriend()
                    async let friends: () = fetchFriendRankings()
                    async let ranked: () = checkIfAlreadyRanked()
                    _ = await (details, source, friends, ranked)
                }
            }
            .presentationBackground(Color.appBackground)
        }
        
        private func fetchGameDetails() async {
        debugLog("🔍 WTP Detail: fetching gameId=\(game.gameId), title=\(game.gameTitle)")
        debugLog("🔍 WTP Detail: cached? \(GameMetadataCache.shared.get(gameId: game.gameId)?.description?.prefix(50) ?? "nil")")
        
        // Instantly apply cached metadata if available
        if let cached = GameMetadataCache.shared.get(gameId: game.gameId) {
            metacriticScore = cached.metacriticScore
            gameDescription = cached.description
            releaseDate = cached.releaseDate
            curatedGenres = cached.curatedGenres
            curatedTags = cached.curatedTags
            curatedPlatforms = cached.curatedPlatforms
            curatedReleaseYear = cached.curatedReleaseYear
            if gameDescription != nil { return }
        }
        
        do {
            struct GameInfo: Decodable {
                let rawg_id: Int
                let metacritic_score: Int?
                let description: String?
                let curated_description: String?
                let release_date: String?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let curated_platforms: [String]?
                let curated_release_year: Int?
            }
            var infos: [GameInfo] = try await SupabaseManager.shared.client
                .from("games")
                .select("rawg_id, metacritic_score, description, curated_description, release_date, curated_genres, curated_tags, curated_platforms, curated_release_year")
                .eq("id", value: game.gameId)
                .limit(1)
                .execute()
                .value
            
            if infos.isEmpty {
                infos = try await SupabaseManager.shared.client
                    .from("games")
                    .select("rawg_id, metacritic_score, description, curated_description, release_date, curated_genres, curated_tags, curated_platforms, curated_release_year")
                    .eq("rawg_id", value: game.gameId)
                    .limit(1)
                    .execute()
                    .value
            }
            
            guard let info = infos.first else {
                debugLog("⚠️ No games row found for gameId \(game.gameId), fetching directly from RAWG")
                let details = try await RAWGService.shared.getGameDetails(id: game.gameId)
                gameDescription = details.gameDescription ?? details.gameDescriptionHtml
                return
            }
            
            debugLog("🔍 WTP Detail: DB returned rawg_id=\(info.rawg_id), desc prefix=\(String((info.curated_description ?? info.description ?? "nil").prefix(50)))")
                
            metacriticScore = info.metacritic_score
            releaseDate = info.release_date
            curatedGenres = info.curated_genres
            curatedTags = info.curated_tags
            curatedPlatforms = info.curated_platforms
            curatedReleaseYear = info.curated_release_year
            
            // Use cached description if available — skip RAWG entirely
            if let desc = info.curated_description ?? info.description, !desc.isEmpty {
                gameDescription = desc
                GameMetadataCache.shared.set(gameId: game.gameId, description: desc, metacriticScore: info.metacritic_score, releaseDate: info.release_date, curatedGenres: info.curated_genres, curatedTags: info.curated_tags, curatedPlatforms: info.curated_platforms, curatedReleaseYear: info.curated_release_year)
                return
            }
            
            // Only call RAWG if we don't have a description yet
            let details = try await RAWGService.shared.getGameDetails(id: info.rawg_id)
            gameDescription = details.gameDescription ?? details.gameDescriptionHtml

            if let desc = gameDescription, !desc.isEmpty {
                GameMetadataCache.shared.set(gameId: game.gameId, description: desc, metacriticScore: info.metacritic_score, releaseDate: info.release_date, curatedGenres: info.curated_genres, curatedTags: info.curated_tags, curatedPlatforms: info.curated_platforms, curatedReleaseYear: info.curated_release_year)
                    _ = try? await SupabaseManager.shared.client
                    .from("games")
                    .update(["description": desc])
                    .eq("rawg_id", value: info.rawg_id)
                    .execute()
            }
            } catch {
                debugLog("⚠️ Could not fetch game details: \(error)")
            }
        }
        
        private func fetchSourceFriend() async {
            guard let friendId = game.sourceFriendId, game.sourceFriendName == nil else { return }
            do {
                struct UserInfo: Decodable { let username: String? }
                let info: UserInfo = try await SupabaseManager.shared.client
                    .from("users")
                    .select("username")
                    .eq("id", value: friendId)
                    .single()
                    .execute()
                    .value
                sourceFriendName = info.username
            } catch {
                debugLog("⚠️ Could not fetch source friend: \(error)")
            }
        }
        
        private func metacriticColor(_ score: Int) -> Color {
            switch score {
            case 75...100: return .success
            case 50...74: return .accentOrange
            default: return .error
            }
        }
        
        private func checkIfAlreadyRanked() async {
            guard let userId = SupabaseManager.shared.currentUser?.id else { return }
            do {
                struct RankedCheck: Decodable { let game_id: Int; let games: GameRawg?; struct GameRawg: Decodable { let rawg_id: Int } }
                let rows: [RankedCheck] = try await SupabaseManager.shared.client
                    .from("user_games")
                    .select("game_id, games(rawg_id)")
                    .eq("user_id", value: userId.uuidString)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .value
                let rankedGameIds = Set(rows.map { $0.game_id })
                isAlreadyRanked = rankedGameIds.contains(game.gameId)
            } catch {
                debugLog("⚠️ Error checking ranked status: \(error)")
            }
        }
        
        private func fetchFriendRankings() async {
            guard let userId = SupabaseManager.shared.currentUser?.id else {
                isLoadingFriendRankings = false
                return
            }
            
            do {
                // 1. Get friend IDs
                struct Friendship: Decodable {
                    let user_id: String
                    let friend_id: String
                }
                let friendships: [Friendship] = try await SupabaseManager.shared.client
                    .from("friendships")
                    .select("user_id, friend_id")
                    .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                    .eq("status", value: "accepted")
                    .execute()
                    .value
                
                let friendIds = friendships.map { f in
                    f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
                }
                let allUserIds = friendIds + [userId.uuidString]
                
                // 2. Find the game's canonical ID
                struct GameLookup: Decodable { let id: Int; let rawg_id: Int }
                let gameLookups: [GameLookup] = try await SupabaseManager.shared.client
                    .from("games")
                    .select("id, rawg_id")
                    .eq("rawg_id", value: game.gameId)
                    .limit(1)
                    .execute()
                    .value
                
                // Also check if game.gameId is a local ID
                let localLookups: [GameLookup] = try await SupabaseManager.shared.client
                    .from("games")
                    .select("id, rawg_id")
                    .eq("id", value: game.gameId)
                    .limit(1)
                    .execute()
                    .value
                
                let allGameIds = Set((gameLookups + localLookups).map { $0.id })
                let _ = Set((gameLookups + localLookups).map { $0.rawg_id })
                
                guard !allGameIds.isEmpty else {
                    isLoadingFriendRankings = false
                    return
                }
                
                // 3. Fetch rankings from friends + self
                struct RankingRow: Decodable {
                    let user_id: String
                    let rank_position: Int
                    let game_id: Int
                    let canonical_game_id: Int?
                }
                
                // Build OR filter for game matching
                let gameIdFilters = allGameIds.map { "game_id.eq.\($0)" }
                let canonicalFilters = allGameIds.map { "canonical_game_id.eq.\($0)" }
                let allFilters = (gameIdFilters + canonicalFilters).joined(separator: ",")
                
                let rankings: [RankingRow] = try await SupabaseManager.shared.client
                    .from("user_games")
                    .select("user_id, rank_position, game_id, canonical_game_id")
                    .in("user_id", values: allUserIds)
                    .or(allFilters)
                    .not("rank_position", operator: .is, value: "null")
                    .order("rank_position", ascending: true)
                    .execute()
                    .value
                
                // Filter to actual matches
                let matchedRankings = rankings.filter { r in
                    allGameIds.contains(r.game_id) ||
                    (r.canonical_game_id != nil && allGameIds.contains(r.canonical_game_id!))
                }
                
                guard !matchedRankings.isEmpty else {
                    isLoadingFriendRankings = false
                    return
                }
                
                // 4. Get usernames
                let rankedUserIds = Array(Set(matchedRankings.map { $0.user_id }))
                struct UserInfo: Decodable {
                    let id: String
                    let username: String?
                    let avatar_url: String?
                }
                let users: [UserInfo] = try await SupabaseManager.shared.client
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
                let myGameRows: [MyGameRow] = try await SupabaseManager.shared.client
                    .from("user_games")
                    .select("game_id, rank_position, canonical_game_id")
                    .eq("user_id", value: userId.uuidString)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .value
                let myMapped = myGameRows.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
                
                let rankedFriendIds = Array(Set(matchedRankings.map { $0.user_id })).filter { $0.lowercased() != userId.uuidString.lowercased() }
                var friendGameCache: [String: [(canonicalId: Int, rank: Int)]] = [:]
                for friendId in rankedFriendIds {
                    let fGames: [MyGameRow] = try await SupabaseManager.shared.client
                        .from("user_games")
                        .select("game_id, rank_position, canonical_game_id")
                        .eq("user_id", value: friendId)
                        .not("rank_position", operator: .is, value: "null")
                        .execute()
                        .value
                    friendGameCache[friendId.lowercased()] = fGames.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
                }
                
                var results: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
                for ranking in matchedRankings {
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
                debugLog("⚠️ Error fetching friend rankings: \(error)")
            }
            
            isLoadingFriendRankings = false
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
        
        private func friendInitialsCircle(_ name: String, size: CGFloat) -> some View {
            Circle()
                .fill(Color.primaryBlue.opacity(0.2))
                .frame(width: size, height: size)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                )
        }
    }
