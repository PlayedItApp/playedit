import SwiftUI
import Supabase

struct GameSearchView: View {
    @State private var searchText = ""
    @State private var games: [Game] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var selectedGame: Game?
    @State private var rankedGameIds: Set<Int> = []
    @State private var searchError: String? = nil
    @Environment(\.dismiss) var dismiss
    
    private var rawgAttribution: some View {
        Link(destination: URL(string: "https://rawg.io")!) {
            Text("Game data powered by RAWG")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
        }
        .padding(.bottom, 12)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.adaptiveGray)
                    
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
                                .foregroundStyle(Color.adaptiveGray)
                        }
                    }
                }
                .padding(12)
                .background(Color.secondaryBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.adaptiveDivider, lineWidth: 0.5)
                )
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
                            .foregroundStyle(Color.adaptiveSilver)
                        if let error = searchError {
                            Text(error)
                                .font(.body)
                                .foregroundStyle(Color.adaptiveGray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        } else {
                            Text("No games found. Try a different search?")
                                .font(.body)
                                .foregroundStyle(Color.adaptiveGray)
                        }
                    }
                    Spacer()
                    rawgAttribution
                } else if games.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.adaptiveSilver)
                        Text("Search for a game to get started")
                            .font(.body)
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    Spacer()
                    rawgAttribution
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

                        rawgAttribution
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
                let previousCount = rankedGameIds.count
                Task {
                    await fetchRankedGameIds()
                    if rankedGameIds.count > previousCount {
                        dismiss()
                    }
                }
            }) { game in
                GameLogView(game: game, source: "search")
                    .presentationBackground(Color.appBackground)
            }
            .task {
                await WantToPlayManager.shared.refreshMyIds()
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
        
        searchError = nil
        do {
            games = try await RAWGService.shared.searchGames(query: searchText)
            if games.isEmpty {
                searchError = nil
            }
        } catch {
            debugLog("Search error: \(error)")
            games = []
            searchError = "Can't reach the game database right now. Check your connection and try again."
        }
        
        isLoading = false
    }
    
    private func fetchRankedGameIds() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            debugLog("❌ No user ID found")
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
            debugLog("✅ Fetched ranked RAWG IDs: \(rankedGameIds)")
        } catch {
            debugLog("❌ Failed to fetch ranked game IDs: \(error)")
        }
    }
}

// MARK: - Game Search Row
struct GameSearchRow: View {
    let game: Game
    let isRanked: Bool
    let onSelect: () -> Void
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Cover Image
                CachedAsyncImage(url: game.coverURL) {
                    GameArtworkPlaceholder(genre: nil, size: .medium)
                }
                .frame(width: 60, height: 80)
                .cornerRadius(8)
                .clipped()
                
                // Game Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let year = game.releaseDate?.prefix(4) {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    if !game.platforms.isEmpty {
                        Text(game.platforms.prefix(3).joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
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
                    } else {
                        BookmarkButton(
                            gameId: game.id,
                            gameTitle: game.title,
                            gameCoverUrl: game.coverURL,
                            source: "search",
                            onToast: { message in
                                toastMessage = message
                                withAnimation { showToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showToast = false }
                                }
                            }
                        )
                        .overlay(alignment: .trailing) {
                            if showToast {
                                Text(toastMessage)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                                    .fixedSize()
                                    .offset(x: -30)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.adaptiveSilver)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(12)
            .background(Color.cardBackground) 
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.adaptiveDivider, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
