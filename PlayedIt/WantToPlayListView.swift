import SwiftUI

struct WantToPlayListView: View {
    @StateObject private var manager = WantToPlayManager.shared
    @State private var games: [WantToPlayGame] = []
    @State private var isLoading = true
    @State private var showGameSearch = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    .padding(.top, 40)
            } else if games.isEmpty {
                emptyState
            } else {
                gameList
            }
        }
        .task {
            await loadGames()
        }
    }
    
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
    
    private var gameList: some View {
        VStack(spacing: 8) {
            ForEach(games) { game in
                WantToPlayRow(game: game, onRemove: {
                    Task {
                        let _ = await manager.removeGame(gameId: game.gameId)
                        await loadGames()
                    }
                }, onPlayed: {
                    // Dismiss and open game log - handled by parent
                })
            }
        }
    }
    
    func loadGames() async {
        games = await manager.fetchMyList()
        isLoading = false
    }
}

// MARK: - Want to Play Row
struct WantToPlayRow: View {
    let game: WantToPlayGame
    let onRemove: () -> Void
    let onPlayed: () -> Void
    
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
                
                if let friendName = game.sourceFriendName {
                    Text("via \(friendName)")
                        .font(.caption)
                        .foregroundColor(.grayText)
                } else if let createdAt = game.createdAt {
                    Text(timeAgo(from: createdAt))
                        .font(.caption)
                        .foregroundColor(.grayText)
                }
            }
            
            Spacer()
            
            // Remove button (swipe alternative)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.grayText)
                    .frame(width: 28, height: 28)
                    .background(Color.lightGray)
                    .cornerRadius(6)
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
