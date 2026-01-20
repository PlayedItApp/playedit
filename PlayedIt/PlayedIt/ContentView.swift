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
            FeedView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
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
            
            pendingRequestCount = friendships.filter {
                $0.friend_id.lowercased() == userId.uuidString.lowercased()
            }.count
            
        } catch {
            print("❌ Error fetching pending count: \(error)")
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
