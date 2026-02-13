import SwiftUI

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
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 40))
                .foregroundColor(.silver)
            
            Text("Nothing here yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.slate)
            
            Text("Bookmark games from your friends' lists or search to get started.")
                .font(.subheadline)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }
    
    // MARK: - Game List Content
    private var gameListContent: some View {
        VStack(spacing: 12) {
            // Controls bar
            if !rankedGames.isEmpty || !unrankedGames.isEmpty {
                controlsBar
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
                    .foregroundColor(.slate)
                
                Text("(\(rankedGames.count))")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(.grayText)
            }
            
            ForEach(rankedGames) { game in
                WantToPlayRankedRow(game: game, isReordering: false, onRemove: {
                    Task {
                        let _ = await manager.removeGame(gameId: game.gameId)
                        await loadGames()
                    }
                }, onUnrank: {
                    Task {
                        let _ = await manager.unrankGame(gameId: game.id)
                        await loadGames()
                    }
                }, onReorder: {
                    gameToReorder = game
                })
            }
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
                    .font(.system(size: 16))
                    .foregroundColor(.primaryBlue)
            }
        }
    }
    
    // MARK: - Unranked Section
        private var unrankedSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.grayText)
                    Text("Backlog")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                    
                    Text("(\(unrankedGames.count))")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.grayText)
                }
                
                ForEach(unrankedGames) { game in
                    WantToPlayUnrankedRow(game: game, hasRankedGames: !rankedGames.isEmpty, onRemove: {
                        Task {
                            let _ = await manager.removeGame(gameId: game.gameId)
                            await loadGames()
                        }
                    }, onRank: {
                        print("🎯 Ranking: \(game.gameTitle), against \(rankedGames.map { $0.gameTitle })")
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
                    })
                }
            }
        }
    
    // MARK: - Rank All
    private func startRankAll() {
        showRankAllSheet = true
    }
    
    // MARK: - Load Games
    func loadGames() async {
        rankedGames = await manager.fetchRankedList()
        unrankedGames = await manager.fetchUnrankedList()
        isLoading = false
    }
}

// MARK: - Ranked Row
struct WantToPlayRankedRow: View {
    let game: WantToPlayGame
    let isReordering: Bool
    let onRemove: () -> Void
    let onUnrank: () -> Void
    var onReorder: () -> Void = {}
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.lightGray)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.silver)
                    )
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
                    .lineLimit(2)
                
                if let createdAt = game.createdAt {
                    Text(timeAgo(from: createdAt))
                        .font(.caption)
                        .foregroundColor(.grayText)
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
                        .foregroundColor(.grayText)
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else { return "" }
        
        let interval = Date().timeIntervalSince(date)
        if interval < 86400 { return "Today" }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
    }
}

// MARK: - Unranked Row
struct WantToPlayUnrankedRow: View {
    let game: WantToPlayGame
    let hasRankedGames: Bool
    let onRemove: () -> Void
    let onRank: () -> Void
    let onPlaceAtPosition: () -> Void
    let onPlaceAtBottom: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.lightGray)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundColor(.silver)
                    )
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
                    .lineLimit(2)
                
                if let createdAt = game.createdAt {
                    Text(timeAgo(from: createdAt))
                        .font(.caption)
                        .foregroundColor(.grayText)
                }
            }
            
            Spacer()
            
            // Rank button
            Button(action: onRank) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Rank")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.primaryBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primaryBlue.opacity(0.1))
                .cornerRadius(8)
            }
            
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
                    .foregroundColor(.grayText)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else { return "" }
        
        let interval = Date().timeIntervalSince(date)
        if interval < 86400 { return "Today" }
        let days = Int(interval / 86400)
        if days == 1 { return "Yesterday" }
        return "\(days)d ago"
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
                        .foregroundColor(.slate)
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
                        .foregroundColor(.grayText)
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
                    AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.lightGray)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .foregroundColor(.silver)
                            )
                    }
                    .frame(width: 40, height: 53)
                    .cornerRadius(4)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.gameTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        Text("Drag to your desired position")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.grayText)
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
                            AsyncImage(url: URL(string: item.gameCoverUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.lightGray)
                                    .overlay(
                                        Image(systemName: "gamecontroller")
                                            .foregroundColor(.silver)
                                            .font(.system(size: 12))
                                    )
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
                    AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.lightGray)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .foregroundColor(.silver)
                            )
                    }
                    .frame(width: 40, height: 53)
                    .cornerRadius(4)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.gameTitle)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        Text("Drag to new position")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.grayText)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.primaryBlue.opacity(0.08))
                
                List {
                    ForEach(orderedGames) { item in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: item.gameCoverUrl ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.lightGray)
                                    .overlay(
                                        Image(systemName: "gamecontroller")
                                            .foregroundColor(.silver)
                                            .font(.system(size: 12))
                                    )
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
                    .foregroundColor(.slate)
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
                    .foregroundColor(.grayText)
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
                                .foregroundColor(.grayText)
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
                    .foregroundColor(.slate)
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
                    .foregroundColor(.grayText)
                    .padding(.bottom, 24)
            }
        }
        
        // MARK: - Comparison View
        private var comparisonView: some View {
            VStack(spacing: 16) {
                if let opponent = currentOpponent, let game = currentGame {
                    Text(prompts[comparisonCount % prompts.count])
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.slate)
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
                        .foregroundColor(.grayText)
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
                    .foregroundColor(.slate)
                
                Text("\(unrankedGames.count) games prioritized")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundColor(.grayText)
                
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
