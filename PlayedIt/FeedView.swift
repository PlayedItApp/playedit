import SwiftUI
import Supabase

struct FeedView: View {
    @Binding var unreadNotificationCount: Int
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var feedItems: [FeedItem] = []
    @State private var isLoading = true
    @State private var showGameSearch = false
    @State private var selectedItem: FeedItem?
    @State private var showNotifications = false
    
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
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showNotifications = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primaryBlue)
                            
                            if unreadNotificationCount > 0 {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 2, y: -2)
                            }
                        }
                    }
                }
                
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
            .sheet(item: $selectedItem) { item in
                CommentsSheet(feedItem: item, onDismiss: {
                    selectedItem = nil
                    Task { await fetchFeed() }
                })
            }
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .onChange(of: showNotifications) { _, isShowing in
                if !isShowing {
                    Task { await fetchUnreadCount() }
                }
            }
        }
        .task {
            await fetchFeed()
            await fetchUnreadCount()
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
                    FeedItemRow(
                        item: item,
                        onLikeTapped: { toggleLike(for: item) },
                        onCommentTapped: { selectedItem = item }
                    )
                }
            }
            .padding(16)
        }
        .refreshable {
            await fetchFeed()
            await fetchUnreadCount()
        }
    }
    
    private func toggleLike(for item: FeedItem) {
        guard let userId = supabase.currentUser?.id else { return }
        
        Task {
            do {
                if item.isLikedByMe {
                    // Remove like
                    try await supabase.client
                        .from("feed_reactions")
                        .delete()
                        .eq("user_game_id", value: item.userGameId)
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                } else {
                    // Add like
                    try await supabase.client
                        .from("feed_reactions")
                        .insert([
                            "user_game_id": item.userGameId,
                            "user_id": userId.uuidString,
                            "emoji": "❤️"
                        ])
                        .execute()
                }
                
                // Refresh feed to update counts
                await fetchFeed()
                
            } catch {
                print("❌ Error toggling like: \(error)")
            }
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
            
            struct Friendship: Decodable {
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            struct ReactionRow: Decodable {
                let user_game_id: String
                let user_id: String
            }
            
            struct CommentCountRow: Decodable {
                let user_game_id: String
            }
            
            // Get friend IDs
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
            
            let userGameIds = rows.map { $0.id }
            
            // Skip reaction/comment queries if no feed items
            guard !userGameIds.isEmpty else {
                feedItems = []
                isLoading = false
                return
            }
            
            // Fetch all reactions for these posts
            let reactions: [ReactionRow] = try await supabase.client
                .from("feed_reactions")
                .select("user_game_id, user_id")
                .in("user_game_id", values: userGameIds)
                .execute()
                .value
            
            // Count likes per post and track user's own likes
            var likeCountMap: [String: Int] = [:]
            var myLikedIds: Set<String> = []
            
            for reaction in reactions {
                likeCountMap[reaction.user_game_id, default: 0] += 1
                print("🔍 Reaction user_id: \(reaction.user_id)")
                print("🔍 Current userId: \(userId.uuidString)")
                print("🔍 Match: \(reaction.user_id == userId.uuidString)")
                if reaction.user_id.lowercased() == userId.uuidString.lowercased() {
                    myLikedIds.insert(reaction.user_game_id)
                }
            }
            
            // Fetch comment counts
            let commentRows: [CommentCountRow] = try await supabase.client
                .from("feed_comments")
                .select("user_game_id")
                .in("user_game_id", values: userGameIds)
                .execute()
                .value
            
            var commentCountMap: [String: Int] = [:]
            for comment in commentRows {
                commentCountMap[comment.user_game_id, default: 0] += 1
            }
            
            feedItems = rows.map { row in
                FeedItem(
                    id: row.id,
                    userGameId: row.id,
                    userId: row.user_id,
                    username: row.users.username ?? "Friend",
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    rankPosition: row.rank_position,
                    loggedAt: row.logged_at,
                    likeCount: likeCountMap[row.id] ?? 0,
                    commentCount: commentCountMap[row.id] ?? 0,
                    isLikedByMe: myLikedIds.contains(row.id)
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error fetching feed: \(error)")
            isLoading = false
        }
    }
    
    private func fetchUnreadCount() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            let count: Int = try await supabase.client
                .from("notifications")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: userId.uuidString)
                .eq("is_read", value: false)
                .execute()
                .count ?? 0
            
            unreadNotificationCount = count
            
        } catch {
            print("❌ Error fetching unread count: \(error)")
        }
    }
}

// MARK: - Feed Item Model
struct FeedItem: Identifiable {
    let id: String
    let userGameId: String
    let userId: String
    let username: String
    let gameTitle: String
    let gameCoverURL: String?
    let rankPosition: Int
    let loggedAt: String?
    let likeCount: Int
    let commentCount: Int
    let isLikedByMe: Bool
}

// MARK: - Feed Item Row
struct FeedItemRow: View {
    let item: FeedItem
    let onLikeTapped: () -> Void
    let onCommentTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content
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
            
            // Divider
            Divider()
                .padding(.horizontal, 12)
            
            // Like and Comment buttons
            HStack(spacing: 24) {
                // Like button
                Button(action: onLikeTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isLikedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(item.isLikedByMe ? .orange : .grayText)
                        
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
                                .font(.subheadline)
                                .foregroundColor(item.isLikedByMe ? .orange : .grayText)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Comment button
                Button(action: onCommentTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 18))
                            .foregroundColor(.grayText)
                        
                        if item.commentCount > 0 {
                            Text("\(item.commentCount)")
                                .font(.subheadline)
                                .foregroundColor(.grayText)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
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
    FeedView(unreadNotificationCount: .constant(3))
}
