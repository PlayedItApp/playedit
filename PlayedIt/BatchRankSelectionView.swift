import SwiftUI
import Supabase

struct BatchRankSelectionView: View {
    let friendGames: [UserGame]
    let myGames: [UserGame]
    let friendName: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedGameIds: Set<Int> = []
    @State private var showBatchFlow = false
    
    // Only games the user hasn't ranked yet
    private var unrankedGames: [UserGame] {
        let myGameIds = Set(myGames.map { $0.gameId })
        let myTitles = Set(myGames.map { $0.gameTitle.lowercased().trimmingCharacters(in: .whitespaces) })
        
        return friendGames
            .filter { game in
                let titleNormalized = game.gameTitle.lowercased().trimmingCharacters(in: .whitespaces)
                return !myGameIds.contains(game.gameId) && !myTitles.contains(titleNormalized)
            }
            .sorted { $0.rankPosition < $1.rankPosition }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if unrankedGames.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.teal)
                        
                        Text("You've ranked them all!")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        
                        Text("You've already ranked every game on \(friendName)'s list.")
                            .font(.subheadline)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Spacer()
                    }
                } else {
                    // Header info
                    VStack(spacing: 4) {
                        Text("Pick games from \(friendName)'s list to rank")
                            .font(.system(size: 15, design: .rounded))
                            .foregroundColor(.grayText)
                        
                        Text("\(unrankedGames.count) games you haven't ranked")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.silver)
                    }
                    .padding(.vertical, 12)
                    
                    // Game list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(unrankedGames, id: \.id) { game in
                                BatchGameRow(
                                    game: game,
                                    friendRank: game.rankPosition,
                                    isSelected: selectedGameIds.contains(game.gameId)
                                ) {
                                    if selectedGameIds.contains(game.gameId) {
                                        selectedGameIds.remove(game.gameId)
                                    } else {
                                        selectedGameIds.insert(game.gameId)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 100) // Space for bottom button
                    }
                    
                    // Bottom bar with start button
                    if !selectedGameIds.isEmpty {
                        VStack(spacing: 0) {
                            Divider()
                            
                            HStack {
                                Text("\(selectedGameIds.count) game\(selectedGameIds.count == 1 ? "" : "s") selected")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundColor(.slate)
                                
                                Spacer()
                                
                                Button {
                                    showBatchFlow = true
                                } label: {
                                    Text("Start Ranking")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .background(Color.white)
                    }
                }
            }
            .navigationTitle("Rank \(friendName)'s Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primaryBlue)
                }
                
                if !unrankedGames.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            if selectedGameIds.count == unrankedGames.count {
                                selectedGameIds.removeAll()
                            } else {
                                selectedGameIds = Set(unrankedGames.map { $0.gameId })
                            }
                        } label: {
                            Text(selectedGameIds.count == unrankedGames.count ? "Deselect All" : "Select All")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.primaryBlue)
                    }
                }
            }
            .fullScreenCover(isPresented: $showBatchFlow) {
                // When batch flow finishes, dismiss this view too
                dismiss()
            } content: {
                BatchRankFlowView(
                    games: unrankedGames.filter { selectedGameIds.contains($0.gameId) }
                )
            }
        }
    }
}

// MARK: - Batch Game Row
struct BatchGameRow: View {
    let game: UserGame
    let friendRank: Int
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.primaryBlue : Color.silver, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primaryBlue)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                            )
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
                }
                .frame(width: 44, height: 59)
                .cornerRadius(6)
                .clipped()
                
                // Game info
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.gameTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                        .lineLimit(1)
                    
                    Text("#\(friendRank) on their list")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.grayText)
                }
                
                Spacer()
            }
            .padding(12)
            .background(isSelected ? Color.primaryBlue.opacity(0.05) : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.primaryBlue.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    BatchRankSelectionView(
        friendGames: [],
        myGames: [],
        friendName: "Alex"
    )
}
