import SwiftUI
import Supabase

struct ContentView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var isCheckingAuth = true
    
    var body: some View {
        Group {
            if isCheckingAuth {
                SplashView()
            } else if supabase.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: isCheckingAuth)
        .task {
            await supabase.checkSession()
            isCheckingAuth = false
        }
    }
}

// MARK: - Splash View
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @AppStorage("startTab") private var startTab = 0
    @State private var selectedTab = 0
    @State private var pendingRequestCount = 0
    @State private var unreadNotificationCount = 0
    @ObservedObject var supabase = SupabaseManager.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(unreadNotificationCount: $unreadNotificationCount)
                .tabItem {
                    Image(systemName: "newspaper")
                    Text("Feed")
                }
                .tag(0)
            
            FriendsView()
                .tabItem {
                    Image(systemName: "person.2")
                    Text("Friends")
                }
                .tag(1)
                .badge(pendingRequestCount > 0 ? pendingRequestCount : 0)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(2)
        }
        .tint(.primaryBlue)
        .overlay(alignment: .bottomLeading) {
            // Notification dot on Home tab
            if unreadNotificationCount > 0 && selectedTab != 0 {
                GeometryReader { geo in
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: notificationDotOffset(screenWidth: geo.size.width), y: geo.size.height - 32)
                }
            }
        }
        .task {
            selectedTab = startTab
            await fetchPendingCount()
            await fetchUnreadNotificationCount()
        }
        .onChange(of: selectedTab) { _, _ in
            Task {
                await fetchPendingCount()
                await fetchUnreadNotificationCount()
            }
        }
    }
    
    private func notificationDotOffset(screenWidth: CGFloat) -> CGFloat {
        let tabWidth = screenWidth / 3
        return (tabWidth / 2) + 12
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
            
            pendingRequestCount = friendships.filter {
                $0.friend_id.lowercased() == userId.uuidString.lowercased()
            }.count
            
        } catch {
            print("❌ Error fetching pending count: \(error)")
        }
    }
    
    private func fetchUnreadNotificationCount() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            let count: Int = try await supabase.client
                .from("notifications")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: userId.uuidString.lowercased())
                .eq("is_read", value: false)
                .execute()
                .count ?? 0
            
            unreadNotificationCount = count
            
        } catch {
            print("❌ Error fetching notification count: \(error)")
        }
    }
}

// MARK: - Ranked Game Row
struct RankedGameRow: View {
    let rank: Int
    let game: UserGame
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
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
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            GameDetailSheet(game: game, rank: rank)
        }
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        default: return .slate
        }
    }
}

// MARK: - Game Detail Sheet
struct GameDetailSheet: View {
    let game: UserGame
    let rank: Int
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var showComparison = false
    @State private var existingUserGames: [UserGame] = []
    @State private var isLoadingReRank = false
    @State private var oldRank: Int? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
                    
                    // Title and rank
                    VStack(spacing: 8) {
                        Text(game.gameTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.slate)
                            .multilineTextAlignment(.center)
                        
                        Text("Ranked #\(rank)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(rank == 1 ? .accentOrange : .primaryBlue)
                    }
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        if !game.platformPlayed.isEmpty {
                            DetailRow(
                                icon: "gamecontroller",
                                label: "Played on",
                                value: game.platformPlayed.joined(separator: ", ")
                            )
                        }
                        
                        if let year = game.gameReleaseDate?.prefix(4) {
                            DetailRow(
                                icon: "calendar",
                                label: "Released",
                                value: String(year)
                            )
                        }
                        
                        if let notes = game.notes, !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Notes", systemImage: "note.text")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.grayText)
                                
                                Text(notes)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundColor(.slate)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Re-rank button
                    Button {
                        Task {
                            await startReRank()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingReRank {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                            } else {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13))
                                Text("Re-rank")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                        }
                        .foregroundColor(.primaryBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.primaryBlue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(isLoadingReRank)
                    .padding(.top, 8)
                    
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.silver)
                    }
                }
            }
            .sheet(isPresented: $showComparison) {
                ComparisonView(
                    newGame: game.toGame(),
                    existingGames: existingUserGames,
                    onComplete: { newPosition in
                        Task {
                            await saveReRankedGame(newPosition: newPosition)
                            dismiss()
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    // MARK: - Start Re-Rank
    private func startReRank() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoadingReRank = true
        oldRank = rank
        
        do {
            // Fetch all user's games EXCEPT this one, for comparisons
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
                .neq("game_id", value: game.gameId)
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            existingUserGames = rows.map { row in
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
            
            isLoadingReRank = false
            showComparison = true
            
        } catch {
            print("❌ Error loading games for re-rank: \(error)")
            isLoadingReRank = false
        }
    }
    
    // MARK: - Save Re-Ranked Game
    private func saveReRankedGame(newPosition: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            // 1. Delete the old entry
            try await supabase.client
                .from("user_games")
                .delete()
                .eq("id", value: game.id)
                .execute()
            
            // 2. Shift games that were below the old rank up by 1
            struct GameToShift: Decodable {
                let id: String
                let rank_position: Int
            }
            
            let gamesToShiftUp: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .gt("rank_position", value: rank)
                .execute()
                .value
            
            for g in gamesToShiftUp {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position - 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            // 3. Shift games at or below the new position down by 1
            let gamesToShiftDown: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .gte("rank_position", value: newPosition)
                .order("rank_position", ascending: false)
                .execute()
                .value
            
            for g in gamesToShiftDown {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position + 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            // 4. Insert at new position (preserve original platform/notes/date)
            struct UserGameInsert: Encodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let platform_played: [String]
                let notes: String
            }
            
            let insert = UserGameInsert(
                user_id: userId.uuidString,
                game_id: game.gameId,
                rank_position: newPosition,
                platform_played: game.platformPlayed,
                notes: game.notes ?? ""
            )
            
            try await supabase.client.from("user_games")
                .insert(insert)
                .execute()
            
            print("✅ Re-ranked from #\(rank) → #\(newPosition)")
            
        } catch {
            print("❌ Error saving re-ranked game: \(error)")
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.primaryBlue)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.grayText)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.slate)
        }
    }
}

#Preview {
    ContentView()
}
