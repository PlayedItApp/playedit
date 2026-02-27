import SwiftUI
import Supabase

private nonisolated struct ResetParams: Encodable, Sendable {
    let p_user_id: String
}

struct ResetRankingsView: View {
    let games: [UserGame]
    var resuming: Bool = false
    let onComplete: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var shuffledGames: [UserGame] = []
    @State private var rankedSoFar: [UserGame] = []
    @State private var currentGameIndex = 0
    @State private var showIntro = true
    @State private var isResetting = false
    @State private var isComplete = false
    @State private var showCancelAlert = false
    @State private var errorMessage: String?
    
    // Inline comparison state
    @State private var isComparing = false
    @State private var lowIndex = 0
    @State private var highIndex = 0
    @State private var comparisonCount = 0
    @State private var currentOpponent: UserGame?
    @State private var showCards = false
    @State private var selectedSide: String? = nil
    @State private var comparisonHistory: [ComparisonState] = []
    @State private var gameHistory: [GameSnapshot] = []
    
    private let maxComparisons = 10
    
    private let prompts = [
        "Which did you enjoy more?",
        "Tough call... which one wins?",
        "Head to head: your pick?",
        "If you could only replay one..."
    ]
    
    struct ComparisonState {
        let lowIndex: Int
        let highIndex: Int
        let comparisonCount: Int
    }

    struct GameSnapshot {
        let gameIndex: Int
        let rankedSoFar: [UserGame]
        let lastPlacedPosition: Int
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if showIntro {
                    introView
                } else if isComplete {
                    completionView
                } else if isComparing, let opponent = currentOpponent, let currentGame = currentGame {
                    comparisonView(currentGame: currentGame, opponent: opponent)
                } else if let currentGame = currentGame {
                    // Brief transition showing which game is next
                    waitingView(currentGame: currentGame)
                }
            }
            .navigationTitle(showIntro ? "" : "Reset Rankings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isComplete {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showCancelAlert = true
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        if isComparing && !(comparisonHistory.isEmpty && gameHistory.isEmpty) {
                            Button {
                                undoLastComparison()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                            }
                            .foregroundColor(.primaryBlue)
                        }
                    }
                }
            }
            .onAppear {
                if resuming {
                    let ranked = games.filter { $0.rankPosition > 0 }.sorted { $0.rankPosition < $1.rankPosition }
                    let unranked = games.filter { $0.rankPosition == 0 }.shuffled()
                    
                    rankedSoFar = ranked
                    shuffledGames = ranked + unranked
                    currentGameIndex = ranked.count
                    showIntro = false
                    
                    if currentGameIndex < shuffledGames.count {
                        startComparisonForCurrentGame()
                    } else {
                        isComplete = true
                    }
                }
            }
            .alert("Cancel Re-ranking?", isPresented: $showCancelAlert) {
                Button("Keep Ranking", role: .cancel) { }
                Button("Cancel", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Your rankings have been wiped. If you cancel now, your games will be unranked until you finish.")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var introView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("🎮")
                .font(.system(size: 60))
            
            Text("Round two!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Same games, fresh rankings. Let's see if your opinions have changed.")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Text("\(games.count) games to rank")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.primaryBlue)
            
            Spacer()
            
            Button {
                Task { await startReset() }
            } label: {
                if isResetting {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Text("Let's rank 'em!")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isResetting)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("✨")
                .font(.system(size: 60))
            
            Text("All done!")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Your rankings have been rebuilt from scratch.")
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            Button {
                onComplete()
                dismiss()
            } label: {
                Text("See My Rankings")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
    
    private func comparisonView(currentGame: UserGame, opponent: UserGame) -> some View {
        VStack(spacing: 16) {
            // Progress
            VStack(spacing: 4) {
                Text("Ranking game \(currentGameIndex + 1) of \(shuffledGames.count)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondaryBackground)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentOrange)
                            .frame(width: geo.size.width * CGFloat(currentGameIndex) / CGFloat(shuffledGames.count), height: 6)
                            .animation(.easeInOut(duration: 0.3), value: currentGameIndex)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            .padding(.top, 12)
            
            // Prompt
            Text(prompts[comparisonCount % prompts.count])
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.top, 8)
            
            // Head-to-head cards
            HStack(spacing: 8) {
                GameComparisonCard(
                    title: currentGame.gameTitle,
                    coverURL: currentGame.gameCoverURL,
                    year: String(currentGame.gameReleaseDate?.prefix(4) ?? ""),
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
                    coverURL: opponent.gameCoverURL,
                    year: String(opponent.gameReleaseDate?.prefix(4) ?? ""),
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
            
            Text("Tap the game you liked better")
                .font(.caption)
                .foregroundStyle(Color.adaptiveGray)
                .padding(.bottom, 24)
        }
    }
    
    private func waitingView(currentGame: UserGame) -> some View {
        VStack(spacing: 12) {
            // Progress
            VStack(spacing: 4) {
                Text("Ranking game \(min(currentGameIndex + 1, shuffledGames.count)) of \(shuffledGames.count)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondaryBackground)
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentOrange)
                            .frame(width: geo.size.width * CGFloat(currentGameIndex) / CGFloat(shuffledGames.count), height: 6)
                            .animation(.easeInOut(duration: 0.3), value: currentGameIndex)
                    }
                }
                .frame(height: 6)
                .padding(.horizontal, 40)
            }
            .padding(.top, 16)
            
            Spacer()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
            
            Spacer()
            
            if let error = errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundColor(.error)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Current Game
    
    private var currentGame: UserGame? {
        guard currentGameIndex < shuffledGames.count else { return nil }
        return shuffledGames[currentGameIndex]
    }
    
    // MARK: - Comparison Logic
    
    private func startComparisonForCurrentGame() {
        guard let _ = currentGame else { return }
        
        comparisonHistory = []
        
        if rankedSoFar.isEmpty && currentGameIndex == 0 {
            // First two games — show head-to-head, winner gets #1, loser gets #2
            guard shuffledGames.count >= 2 else {
                // Only 1 game total, just place it
                Task { await placeGame(shuffledGames[0], at: 1) }
                return
            }
            
            currentOpponent = shuffledGames[1]
            comparisonCount = 0
            isComparing = true
            showCards = false
            selectedSide = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                showCards = true
            }
            return
        }
        
        lowIndex = 0
        highIndex = rankedSoFar.count - 1
        comparisonCount = 0
        isComparing = true
        
        nextComparison()
    }
    
    private func nextComparison() {
        showCards = false
        selectedSide = nil
        
        if lowIndex > highIndex || comparisonCount >= maxComparisons {
            let position = lowIndex + 1
            isComparing = false
            currentOpponent = nil
            Task { await placeGame(shuffledGames[currentGameIndex], at: position) }
            return
        }
        
        let midIndex = (lowIndex + highIndex) / 2
        currentOpponent = rankedSoFar[midIndex]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showCards = true
        }
    }
    
    private func selectGame(side: String) {
        selectedSide = side
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            // Special case: first matchup (game 0 vs game 1)
            if rankedSoFar.isEmpty && currentGameIndex == 0 {
                isComparing = false
                currentOpponent = nil
                
                let winner: UserGame
                let loser: UserGame
                if side == "left" {
                    winner = shuffledGames[0]
                    loser = shuffledGames[1]
                } else {
                    winner = shuffledGames[1]
                    loser = shuffledGames[0]
                }
                
                Task {
                    await placeFirstTwo(winner: winner, loser: loser)
                }
                return
            }
            
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
    
    private func placeFirstTwo(winner: UserGame, loser: UserGame) async {
        guard let _ = supabase.currentUser?.id else { return }
            do {
                // Place winner at #1
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": 1])
                    .eq("id", value: winner.id)
                    .execute()
                
                // Place loser at #2
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": 2])
                    .eq("id", value: loser.id)
                    .execute()
                
                debugLog("✅ First matchup: \(winner.gameTitle) at #1, \(loser.gameTitle) at #2")
                
                // Update local state
                var rankedWinner = winner
                rankedWinner.rankPosition = 1
                var rankedLoser = loser
                rankedLoser.rankPosition = 2
                
                rankedSoFar = [rankedWinner, rankedLoser]
                
                // Save snapshot so we can undo back to this matchup
                gameHistory.append(GameSnapshot(
                    gameIndex: 0,
                    rankedSoFar: [],
                    lastPlacedPosition: 1
                ))
                
                // Skip to game index 2 (both 0 and 1 are placed)
                currentGameIndex = 2
                
                if currentGameIndex >= shuffledGames.count {
                    await postFeedEntry()
                    isComplete = true
                } else {
                    startComparisonForCurrentGame()
                }
                
            } catch {
                debugLog("❌ Error placing first two games: \(error)")
                errorMessage = "Something went wrong. Try again?"
            }
        }
    
    private func undoLastComparison() {
        // If we have comparison history within the current game, undo that
        if let lastState = comparisonHistory.popLast() {
            lowIndex = lastState.lowIndex
            highIndex = lastState.highIndex
            comparisonCount = lastState.comparisonCount
            nextComparison()
        } else {
            // No comparison history — go back to previous game
            Task { await undoPreviousGame() }
        }
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func undoPreviousGame() async {
            guard let snapshot = gameHistory.popLast() else { return }
            guard let userId = supabase.currentUser?.id else { return }
            
            do {
                let placedGame = shuffledGames[snapshot.gameIndex]
                
                // Check if undoing back to the first matchup
                if snapshot.gameIndex == 0 && snapshot.rankedSoFar.isEmpty {
                    let game0 = shuffledGames[0]
                    let game1 = shuffledGames[1]
                    
                    try await supabase.client
                        .rpc("undo_first_matchup", params: [
                            "p_game0_id": AnyJSON.string(game0.id),
                            "p_game1_id": AnyJSON.string(game1.id),
                            "p_user_id": AnyJSON.string(userId.uuidString)
                        ])
                        .execute()
                    
                    debugLog("✅ Undid first matchup, back to game 1 vs game 2")
                } else {
                    try await supabase.client
                        .rpc("undo_game_placement", params: [
                            "p_user_game_id": AnyJSON.string(placedGame.id),
                            "p_user_id": AnyJSON.string(userId.uuidString),
                            "p_placed_position": AnyJSON.integer(snapshot.lastPlacedPosition)
                        ])
                        .execute()
                }
                
                // Restore local state
                rankedSoFar = snapshot.rankedSoFar
                currentGameIndex = snapshot.gameIndex
                comparisonHistory = []
                
                // Restart comparisons for this game
                startComparisonForCurrentGame()
                
                debugLog("✅ Undid placement of \(placedGame.gameTitle), back to game \(snapshot.gameIndex + 1)")
                
            } catch {
                debugLog("❌ Error undoing game placement: \(error)")
            }
        }
    
    // MARK: - Start Reset
    
    private func startReset() async {
        guard let userId = supabase.currentUser?.id else { return }
        isResetting = true
        
        do {
            try await supabase.client.rpc("reset_user_rankings", params: ResetParams(p_user_id: userId.uuidString))
                .execute()
            
            debugLog("✅ All rank positions wiped")
            
            shuffledGames = games.shuffled()
            rankedSoFar = []
            currentGameIndex = 0
            showIntro = false
            isResetting = false
            
            // First game goes straight to #1
            if !shuffledGames.isEmpty {
                startComparisonForCurrentGame()
            }
            
        } catch {
            debugLog("❌ Error resetting ranks: \(error)")
            errorMessage = "Couldn't reset rankings. Try again?"
            isResetting = false
        }
    }
    
    // MARK: - Place Game at Position
    
    private func placeGame(_ game: UserGame, at position: Int) async {
            guard let userId = supabase.currentUser?.id else { return }
            
            // Save snapshot for game-level undo (skip first game — no comparison was made)
            if currentGameIndex > 0 {
                gameHistory.append(GameSnapshot(
                    gameIndex: currentGameIndex,
                    rankedSoFar: rankedSoFar,
                    lastPlacedPosition: position
                ))
            }
            
            do {
                try await supabase.client
                    .rpc("place_game_at_rank", params: [
                        "p_user_game_id": AnyJSON.string(game.id),
                        "p_user_id": AnyJSON.string(userId.uuidString),
                        "p_rank": AnyJSON.integer(position)
                    ])
                    .execute()
                
                debugLog("✅ Placed \(game.gameTitle) at #\(position)")
                
                // Update local state
                var updatedGame = game
                updatedGame.rankPosition = position
                
                rankedSoFar = rankedSoFar.map { g in
                    var mutable = g
                    if mutable.rankPosition >= position {
                        mutable.rankPosition += 1
                    }
                    return mutable
                }
                rankedSoFar.append(updatedGame)
                rankedSoFar.sort { $0.rankPosition < $1.rankPosition }
                
                // Move to next game
                currentGameIndex += 1
                
                if currentGameIndex >= shuffledGames.count {
                    // Safety net: renormalize at the end
                    _ = try? await supabase.client
                        .rpc("renormalize_ranks", params: [
                            "p_user_id": AnyJSON.string(userId.uuidString)
                        ])
                        .execute()
                    
                    await postFeedEntry()
                    isComplete = true
                } else {
                    startComparisonForCurrentGame()
                }
                
            } catch {
                debugLog("❌ Error placing game: \(error)")
                errorMessage = "Something went wrong. Try again?"
            }
        }
    
    // MARK: - Post Feed Entry
    
    private func postFeedEntry() async {
        guard let userId = supabase.currentUser?.id else { return }
        guard games.count >= 2 else { return }
        
        do {
            struct ActivityFeedInsert: Encodable {
                let user_id: String
                let activity_type: String
            }
            
            struct ActivityFeedResponse: Decodable {
                let id: String
            }
            
            let activityResponse: ActivityFeedResponse = try await supabase.client
                .from("activity_feed")
                .insert(ActivityFeedInsert(
                    user_id: userId.uuidString,
                    activity_type: "reset_rankings"
                ))
                .select("id")
                .single()
                .execute()
                .value
            
            struct FeedPostInsert: Encodable {
                let user_id: String
                let post_type: String
                let activity_feed_id: String
            }
            
            try await supabase.client
                .from("feed_posts")
                .insert(FeedPostInsert(
                    user_id: userId.uuidString,
                    post_type: "reset_rankings",
                    activity_feed_id: activityResponse.id
                ))
                .execute()
            
            debugLog("✅ Posted reset rankings feed entry")
        } catch {
            debugLog("❌ Error posting feed entry: \(error)")
        }
    }
}
