import SwiftUI
import Supabase

struct GameSearchView: View {
    @State private var searchText = ""
    @State private var games: [Game] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var selectedGame: Game?
    @State private var rankedGameIds: Set<Int> = []
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.grayText)
                    
                    TextField("What did you play?", text: $searchText)
                        .autocorrectionDisabled()
                        .onSubmit {
                            Task { await search() }
                        }
                    
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            games = []
                            hasSearched = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.grayText)
                        }
                    }
                }
                .padding(12)
                .background(Color.lightGray)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Results
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    Spacer()
                } else if games.isEmpty && hasSearched {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 48))
                            .foregroundColor(.silver)
                        Text("No games found. Try a different search?")
                            .font(.body)
                            .foregroundColor(.grayText)
                    }
                    Spacer()
                } else if games.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.silver)
                        Text("Search for a game to get started")
                            .font(.body)
                            .foregroundColor(.grayText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(games) { game in
                                GameSearchRow(game: game, isRanked: rankedGameIds.contains(game.id)) {
                                    selectedGame = game
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Search Games")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
            .sheet(item: $selectedGame, onDismiss: {
                Task {
                    await fetchRankedGameIds()
                }
            }) { game in
                GameLogView(game: game)
            }
            .task {
                await fetchRankedGameIds()
            }
        }
    }
    
    private func search() async {
        guard !searchText.isEmpty else { return }
        
        isLoading = true
        hasSearched = true
        
        // Refresh ranked game IDs before showing results
        await fetchRankedGameIds()
        
        do {
            games = try await RAWGService.shared.searchGames(query: searchText)
        } catch {
            print("Search error: \(error)")
            games = []
        }
        
        isLoading = false
    }
    
    private func fetchRankedGameIds() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            print("❌ No user ID found")
            return
        }
        
        do {
            // Join with games table to get the rawg_id
            let response: [UserGameWithRawgId] = try await SupabaseManager.shared.client
                .from("user_games")
                .select("game_id, games(rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            rankedGameIds = Set(response.compactMap { $0.games?.rawg_id })
            print("✅ Fetched ranked RAWG IDs: \(rankedGameIds)")
        } catch {
            print("❌ Failed to fetch ranked game IDs: \(error)")
        }
    }
}

// MARK: - Game Search Row
struct GameSearchRow: View {
    let game: Game
    let isRanked: Bool
    let onSelect: () -> Void
    @ObservedObject private var wantToPlayManager = WantToPlayManager.shared
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Cover Image
                AsyncImage(url: URL(string: game.coverURL ?? "")) { image in
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
                .frame(width: 60, height: 80)
                .cornerRadius(8)
                .clipped()
                
                // Game Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let year = game.releaseDate?.prefix(4) {
                        Text(String(year))
                            .font(.caption)
                            .foregroundColor(.grayText)
                    }
                    
                    if !game.platforms.isEmpty {
                        Text(game.platforms.prefix(3).joined(separator: " • "))
                            .font(.caption)
                            .foregroundColor(.grayText)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Status badges
                VStack(spacing: 6) {
                    if isRanked {
                        Text("Ranked")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.teal)
                            .clipShape(Capsule())
                    } else if wantToPlayManager.myWantToPlayIds.contains(game.id) {
                        Text("Want to Play")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.accentOrange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentOrange.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        // Want to Play button
                        Button {
                            Task { await addToWantToPlay() }
                        } label: {
                            Image(systemName: "bookmark")
                                .font(.system(size: 16))
                                .foregroundColor(.grayText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundColor(.silver)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(12)
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            .overlay(
                Group {
                    if showToast {
                        Text(toastMessage)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.slate)
                            .cornerRadius(8)
                            .transition(.opacity)
                    }
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func addToWantToPlay() async {
        let success = await wantToPlayManager.addGame(
            gameId: game.id,
            gameTitle: game.title,
            gameCoverUrl: game.coverURL,
            source: "search"
        )
        if success {
            toastMessage = "Saved to Want to Play!"
            withAnimation { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showToast = false }
            }
        }
    }
}

#Preview {
    GameSearchView()
}

struct UserGameWithRawgId: Decodable {
    let game_id: Int
    let games: GameRawgId?
    
    struct GameRawgId: Decodable {
        let rawg_id: Int
    }
}
