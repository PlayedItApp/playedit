import SwiftUI

struct ComparisonView: View {
    let newGame: Game
    let existingGames: [UserGame]
    let onComplete: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var comparisonQueue: [UserGame] = []
    @State private var currentComparison: UserGame?
    @State private var lowIndex = 0
    @State private var highIndex = 0
    @State private var comparisonCount = 0
    @State private var finalPosition: Int?
    @State private var showCards = false
    @State private var selectedSide: String? = nil
    @State private var comparisonHistory: [ComparisonState] = []
    @State private var showCancelAlert = false
    
    // History state for undo
    struct ComparisonState {
        let lowIndex: Int
        let highIndex: Int
        let comparisonCount: Int
    }
    
    private let maxComparisons = 10
    
    private let prompts = [
        "Which did you enjoy more?",
        "Tough call — which one wins?",
        "Head to head: your pick?",
        "If you could only replay one..."
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Progress indicator.
                VStack(spacing: 8) {
                }
                .padding(.top, 12)
                
                // Prompt
                if finalPosition == nil {
                    Text(prompts[comparisonCount % prompts.count])
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.slate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                
                if let opponent = currentComparison {
                    // Head-to-head comparison
                    HStack(spacing: 8) {
                        // New game (left)
                        GameComparisonCard(
                            title: newGame.title,
                            coverURL: newGame.coverURL,
                            year: String(newGame.releaseDate?.prefix(4) ?? ""),
                            isHighlighted: selectedSide == "left"
                        ) {
                            selectGame(side: "left")
                        }
                        .opacity(showCards ? 1 : 0)
                        .offset(x: showCards ? 0 : -50)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showCards)
                        
                        // Pixel VS
                        PixelVS()
                            .opacity(showCards ? 1 : 0)
                            .scaleEffect(showCards ? 1 : 0.5)
                            .animation(.spring(response: 0.4).delay(0.2), value: showCards)
                        
                        // Existing game (right)
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
                    
                    // Tip
                    Text("Tap the game you liked better")
                        .font(.caption)
                        .foregroundColor(.grayText)
                        .padding(.bottom, 24)
                    
                } else if let position = finalPosition {
                    Spacer()
                    RetroCompletionView(game: newGame, position: position, totalGames: existingGames.count + 1) {
                        onComplete(position)
                        dismiss()
                    }
                    Spacer()
                }
            }
            .navigationTitle("Rank It")
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
            .alert("Cancel Ranking?", isPresented: $showCancelAlert) {
                Button("Keep Ranking", role: .cancel) { }
                Button("Cancel", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("Your progress will be lost and the game won't be ranked.")
            }
            .onAppear {
                setupComparison()
            }
        }
    }
    
    private var estimatedTotal: Int {
        let count = existingGames.count
        if count <= 1 { return 1 }
        return min(Int(ceil(log2(Double(count)))) + 2, maxComparisons)
    }
    
    private func setupComparison() {
        guard !existingGames.isEmpty else {
            finalPosition = 1
            currentComparison = nil
            return
        }
        
        lowIndex = 0
        highIndex = existingGames.count - 1
        comparisonCount = 0
        
        nextComparison()
    }
    
    private func nextComparison() {
        showCards = false
        selectedSide = nil
        
        if lowIndex > highIndex || comparisonCount >= maxComparisons {
            finalPosition = lowIndex + 1
            currentComparison = nil
            return
        }
        
        let midIndex = (lowIndex + highIndex) / 2
        currentComparison = existingGames[midIndex]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showCards = true
        }
    }
    
    private func selectGame(side: String) {
        selectedSide = side
        
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if side == "left" {
                userChoseNewGame()
            } else {
                userChoseExistingGame()
            }
        }
    }
    
    private func userChoseNewGame() {
        // Save current state for undo
        comparisonHistory.append(ComparisonState(
            lowIndex: lowIndex,
            highIndex: highIndex,
            comparisonCount: comparisonCount
        ))
        
        let midIndex = (lowIndex + highIndex) / 2
        highIndex = midIndex - 1
        comparisonCount += 1
        nextComparison()
    }
    
    private func userChoseExistingGame() {
        // Save current state for undo
        comparisonHistory.append(ComparisonState(
            lowIndex: lowIndex,
            highIndex: highIndex,
            comparisonCount: comparisonCount
        ))
        
        let midIndex = (lowIndex + highIndex) / 2
        lowIndex = midIndex + 1
        comparisonCount += 1
        nextComparison()
    }
    
    private func undoLastComparison() {
        guard let lastState = comparisonHistory.popLast() else { return }
        
        // Restore previous state
        lowIndex = lastState.lowIndex
        highIndex = lastState.highIndex
        comparisonCount = lastState.comparisonCount
        finalPosition = nil
        
        // Show the comparison again
        nextComparison()
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Pixel VS
struct PixelVS: View {
    var body: some View {
        Text("VS")
            .font(.system(size: 24, weight: .black, design: .monospaced))
            .foregroundColor(.accentOrange)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentOrange.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentOrange, style: StrokeStyle(lineWidth: 3, dash: [6, 3]))
                    )
            )
    }
}

// MARK: - Game Comparison Card
struct GameComparisonCard: View {
    let title: String
    let coverURL: String?
    let year: String
    var isHighlighted: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Retro frame around image
                ZStack {
                    // Pixel border effect
                    Rectangle()
                        .fill(isHighlighted ? Color.primaryBlue : Color.slate.opacity(0.3))
                        .frame(width: 148, height: 195)
                    
                    Rectangle()
                        .fill(isHighlighted ? Color.primaryBlue.opacity(0.3) : Color.lightGray)
                        .frame(width: 144, height: 191)
                    
                    AsyncImage(url: URL(string: coverURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.lightGray)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 32))
                                    .foregroundColor(.silver)
                            )
                    }
                    .frame(width: 140, height: 187)
                    .clipped()
                }
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(height: 36)
                    
                    if !year.isEmpty {
                        Text(year)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.grayText)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isHighlighted ? Color.primaryBlue.opacity(0.1) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isHighlighted ? Color.primaryBlue : Color.lightGray, lineWidth: isHighlighted ? 3 : 1)
            )
            .scaleEffect(isHighlighted ? 1.02 : 1.0)
            .animation(.spring(response: 0.2), value: isHighlighted)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Retro Completion View
struct RetroCompletionView: View {
    let game: Game
    let position: Int
    let totalGames: Int
    let onDone: () -> Void
    
    @State private var showContent = false
    @State private var confettiParticles: [ConfettiParticle] = []
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confettiParticles) { particle in
                    Rectangle()
                        .fill(particle.color.opacity(0.5))
                        .frame(width: particle.size, height: particle.size)
                        .position(particle.position)
                        .opacity(showContent ? 0 : 1)
                        .animation(.easeOut(duration: 2).delay(particle.delay), value: showContent)
                }
                
                VStack(spacing: 20) {
                    PixelRankBadge(position: position)
                        .scaleEffect(showContent ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1), value: showContent)
                    
                    Text(celebrationMessage)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.slate)
                        .multilineTextAlignment(.center)
                        .opacity(showContent ? 1 : 0)
                        .offset(y: showContent ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.3), value: showContent)
                    
                    Text("\(game.title)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.4), value: showContent)
                    
                    Text("is now #\(position)")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.grayText)
                        .opacity(showContent ? 1 : 0)
                        .animation(.easeOut(duration: 0.4).delay(0.45), value: showContent)
                    
                    Button("Done") {
                        onDone()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 60)
                    .padding(.top, 20)
                    .opacity(showContent ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.6), value: showContent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                generateConfetti(in: geometry.size)
                
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showContent = true
                }
            }
        }
    }
    
    private func generateConfetti(in size: CGSize) {
        let colors: [Color] = [.accentOrange, .primaryBlue, .teal, .yellow, .pink]
        
        for i in 0..<50 {
            let particle = ConfettiParticle(
                id: i,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 8...16),
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                delay: Double.random(in: 0...0.8)
            )
            confettiParticles.append(particle)
        }
    }
    
    private var celebrationMessage: String {
        if position == 1 {
            return "New champion!"
        } else if position <= 3 {
            return "Elite tier!"
        } else if position <= totalGames / 2 {
            return "That's high praise!"
        } else if position == totalGames {
            return "Hey, you still finished it!"
        } else {
            return "They can't all be bangers."
        }
    }
}

// MARK: - Confetti Particle
struct ConfettiParticle: Identifiable {
    let id: Int
    let color: Color
    let size: CGFloat
    let position: CGPoint
    let delay: Double
}

// MARK: - Pixel Rank Badge
struct PixelRankBadge: View {
    let position: Int
    
    var body: some View {
        ZStack {
            // Pixel-style container
            RoundedRectangle(cornerRadius: 8)
                .fill(badgeColor.opacity(0.15))
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(badgeColor, style: StrokeStyle(lineWidth: 4))
                )
            
            Text(badgeEmoji)
                .font(.system(size: 40))
        }
    }
    
    private var badgeEmoji: String {
        switch position {
        case 1: return "👑"
        case 2...3: return "🏆"
        case 4...10: return "🔥"
        default: return "✅"
        }
    }
    
    private var badgeColor: Color {
        switch position {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        case 4...10: return .teal
        default: return .success
        }
    }
}

// MARK: - Scale Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ComparisonView(
        newGame: Game(
            from: RAWGGame(
                id: 1,
                name: "Horizon Zero Dawn",
                backgroundImage: nil,
                released: "2017-02-28",
                metacritic: 89,
                genres: [],
                platforms: []
            )
        ),
        existingGames: [],
        onComplete: { position in
            print("Final position: \(position)")
        }
    )
}
