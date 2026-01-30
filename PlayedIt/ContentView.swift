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
    @State private var unreadNotificationCount = 0
    @ObservedObject var supabase = SupabaseManager.shared
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(unreadNotificationCount: $unreadNotificationCount)
                .tabItem {
                    Label {
                        Text("Home")
                    } icon: {
                        Image(systemName: "house")
                            .environment(\.symbolVariants, selectedTab == 0 ? .fill : .none)
                    }
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
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: notificationDotOffset, y: -32)
            }
        }
        .task {
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
    
    private var notificationDotOffset: CGFloat {
        // Position dot over the Home tab (leftmost tab)
        let screenWidth = UIScreen.main.bounds.width
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
                        // Platform
                        if !game.platformPlayed.isEmpty {
                            DetailRow(
                                icon: "gamecontroller",
                                label: "Played on",
                                value: game.platformPlayed.joined(separator: ", ")
                            )
                        }
                        
                        // Release year
                        if let year = game.gameReleaseDate?.prefix(4) {
                            DetailRow(
                                icon: "calendar",
                                label: "Released",
                                value: String(year)
                            )
                        }
                        
                        // Notes
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
