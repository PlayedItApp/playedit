import SwiftUI
import Supabase

struct ContentView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    
    var body: some View {
        Group {
            if supabase.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var pendingRequestCount = 0
    @ObservedObject var supabase = SupabaseManager.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RankingsView()
                .tabItem {
                    Image(systemName: "list.number")
                    Text("Rankings")
                }
                .tag(0)
            
            FeedView()
                .tabItem {
                    Image(systemName: "bell")
                    Text("Feed")
                }
                .tag(1)
            
            FriendsView()
                .tabItem {
                    Image(systemName: "person.2")
                    Text("Friends")
                }
                .tag(2)
                .badge(pendingRequestCount > 0 ? pendingRequestCount : 0)
            
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(3)
        }
        .tint(.primaryBlue)
        .task {
            await fetchPendingCount()
        }
        .onChange(of: selectedTab) { _, _ in
            Task { await fetchPendingCount() }
        }
    }
    
    private func fetchPendingCount() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct FriendshipRow: Decodable {
                let id: String
                let friend_id: String
                let status: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("id, friend_id, status")
                .eq("status", value: "pending")
                .execute()
                .value
            
            // Count where current user is the recipient (case-insensitive)
            pendingRequestCount = friendships.filter {
                $0.friend_id.lowercased() == userId.uuidString.lowercased()
            }.count
            
        } catch {
            print("❌ Error fetching pending count: \(error)")
        }
    }
}

// MARK: - Rankings View (formerly HomeView)
struct RankingsView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var showGameSearch = false
    @State private var rankedGames: [UserGame] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                } else if rankedGames.isEmpty {
                    emptyStateView
                } else {
                    rankedListView
                }
            }
            .navigationTitle("My Rankings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGameSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showGameSearch, onDismiss: {
                Task { await fetchRankedGames() }
            }) {
                GameSearchView()
            }
        }
        .task {
            await fetchRankedGames()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            
            HStack(spacing: 0) {
                Text("played")
                    .font(.largeTitle)
                    .foregroundColor(.slate)
                Text("it")
                    .font(.largeTitle)
                    .foregroundColor(.accentOrange)
            }
            
            Text("Your list is waiting. What's the first game?")
                .font(.body)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                showGameSearch = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Log Game")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var rankedListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(rankedGames.enumerated()), id: \.element.id) { index, game in
                    RankedGameRow(rank: index + 1, game: game)
                }
            }
            .padding(16)
        }
        .refreshable {
            await fetchRankedGames()
        }
    }
    
    private func fetchRankedGames() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                }
            }
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: userId.uuidString)
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            rankedGames = rows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error fetching games: \(error)")
            isLoading = false
        }
    }
}

// MARK: - Ranked Game Row
struct RankedGameRow: View {
    let rank: Int
    let game: UserGame
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 32)
            
            AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
                    .lineLimit(2)
                
                if let year = game.gameReleaseDate?.prefix(4) {
                    Text(String(year))
                        .font(.caption)
                        .foregroundColor(.grayText)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.silver)
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        default: return .slate
        }
    }
}

#Preview {
    ContentView()
}
