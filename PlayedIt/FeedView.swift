import SwiftUI
import Supabase

struct FeedView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var feedItems: [FeedItem] = []
    @State private var isLoading = true
    @State private var showGameSearch = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                } else if feedItems.isEmpty {
                    emptyStateView
                } else {
                    feedListView
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showGameSearch) {
                GameSearchView()
            }
        }
        .task {
            await fetchFeed()
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundColor(.silver)
            
            Text("Your feed is quiet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.slate)
            
            Text("Add friends or log some games to get things moving.")
                .font(.body)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var feedListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(feedItems) { item in
                    FeedItemRow(item: item)
                }
            }
            .padding(16)
        }
        .refreshable {
            await fetchFeed()
        }
    }
    
    private func fetchFeed() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct FeedRow: Decodable {
                let id: String
                let user_id: String
                let rank_position: Int
                let logged_at: String?
                let games: GameInfo
                let users: UserInfo
                
                struct GameInfo: Decodable {
                    let title: String
                    let cover_url: String?
                }
                
                struct UserInfo: Decodable {
                    let username: String?
                }
            }
            
            // Get friend IDs
            struct Friendship: Decodable {
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            let friendships: [Friendship] = try await supabase.client
                .from("friendships")
                .select("user_id, friend_id, status")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .eq("status", value: "accepted")
                .execute()
                .value
            
            var feedUserIds = friendships.map { f in
                f.user_id == userId.uuidString ? f.friend_id : f.user_id
            }

            // Include current user's games in feed
            feedUserIds.append(userId.uuidString)
            
            // Fetch recent games from friends and self
            let rows: [FeedRow] = try await supabase.client
                .from("user_games")
                .select("id, user_id, rank_position, logged_at, games(title, cover_url), users(username)")
                .in("user_id", values: feedUserIds)
                .order("logged_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            feedItems = rows.map { row in
                FeedItem(
                    id: row.id,
                    username: row.users.username ?? "Friend",
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    rankPosition: row.rank_position,
                    loggedAt: row.logged_at
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error fetching feed: \(error)")
            isLoading = false
        }
    }
}

// MARK: - Feed Item Model
struct FeedItem: Identifiable {
    let id: String
    let username: String
    let gameTitle: String
    let gameCoverURL: String?
    let rankPosition: Int
    let loggedAt: String?
}

// MARK: - Feed Item Row
struct FeedItemRow: View {
    let item: FeedItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            AsyncImage(url: URL(string: item.gameCoverURL ?? "")) { image in
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
                Text("\(item.username) ranked")
                    .font(.subheadline)
                    .foregroundColor(.grayText)
                
                Text(item.gameTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Text("at #\(item.rankPosition)")
                        .font(.subheadline)
                        .foregroundColor(.primaryBlue)
                    
                    if let loggedAt = item.loggedAt {
                        Text("• \(timeAgo(from: loggedAt))")
                            .font(.caption)
                            .foregroundColor(.grayText)
                    }
                }
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
    
    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return ""
        }
        
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

#Preview {
    FeedView()
}
