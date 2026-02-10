import SwiftUI

struct BatchRankFlowView: View {
    let games: [UserGame]
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex = 0
    @State private var showCurrentGame = false
    @State private var showCancelAlert = false
    
    private var currentGame: UserGame? {
        guard currentIndex < games.count else { return nil }
        return games[currentIndex]
    }
    
    private var progress: String {
        "\(currentIndex + 1) of \(games.count)"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                if let game = currentGame {
                    // Current game preview
                    VStack(spacing: 20) {
                        // Progress
                        HStack(spacing: 8) {
                            Text("Game \(progress)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                            
                            // Progress dots
                            HStack(spacing: 4) {
                                ForEach(0..<games.count, id: \.self) { i in
                                    Circle()
                                        .fill(i < currentIndex ? Color.teal : (i == currentIndex ? Color.primaryBlue : Color.silver.opacity(0.5)))
                                        .frame(width: i == currentIndex ? 8 : 6, height: i == currentIndex ? 8 : 6)
                                }
                            }
                        }
                        
                        // Cover art
                        AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle()
                                .fill(Color.lightGray)
                                .overlay(
                                    Image(systemName: "gamecontroller")
                                        .font(.system(size: 40))
                                        .foregroundColor(.silver)
                                )
                        }
                        .frame(width: 150, height: 200)
                        .cornerRadius(12)
                        .clipped()
                        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                        
                        // Title
                        Text(game.gameTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.slate)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        if let year = game.gameReleaseDate?.prefix(4) {
                            Text(String(year))
                                .font(.subheadline)
                                .foregroundColor(.grayText)
                        }
                        
                        // Up next preview
                        if currentIndex + 1 < games.count {
                            HStack(spacing: 4) {
                                Text("Up next:")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.grayText)
                                Text(games[currentIndex + 1].gameTitle)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.slate)
                                    .lineLimit(1)
                            }
                            .padding(.top, 8)
                        }
                        
                        // Rank button
                        Button {
                            showCurrentGame = true
                        } label: {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text("Rank This Game")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                        
                        // Skip button
                        Button {
                            advanceToNext()
                        } label: {
                            Text("Skip")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.grayText)
                        }
                    }
                } else {
                    // All done
                    batchCompleteView
                }
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if currentIndex < games.count {
                            showCancelAlert = true
                        } else {
                            dismiss()
                        }
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
            .alert("Stop Ranking?", isPresented: $showCancelAlert) {
                Button("Keep Going", role: .cancel) { }
                Button("Stop", role: .destructive) {
                    dismiss()
                }
            } message: {
                Text("You've ranked \(currentIndex) of \(games.count) games. Games already ranked are saved.")
            }
            .sheet(isPresented: $showCurrentGame) {
                if let game = currentGame {
                    GameLogView(game: game.toGame())
                }
            }
            .onChange(of: showCurrentGame) { _, isShowing in
                if !isShowing {
                    // GameLogView was dismissed - move to next game
                    advanceToNext()
                }
            }
        }
    }
    
    private func advanceToNext() {
        withAnimation {
            currentIndex += 1
        }
    }
    
    // MARK: - Batch Complete View
    private var batchCompleteView: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.teal.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.teal, style: StrokeStyle(lineWidth: 4))
                    )
                
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.teal)
            }
            
            Text("All done!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.slate)
            
            Text("You ranked \(games.count) game\(games.count == 1 ? "" : "s")")
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.grayText)
            
            Button("Finish") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 60)
            .padding(.top, 12)
        }
    }
}

#Preview {
    BatchRankFlowView(games: [])
}
