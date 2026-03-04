import SwiftUI
import Supabase
import UserNotifications

struct NotificationsView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
    @State private var selectedFeedItem: FeedItem?
    @State private var selectedFriend: Friend?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                } else if notifications.isEmpty {
                    emptyStateView
                } else {
                    notificationsList
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                if !notifications.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button {
                                markAllAsRead()
                            } label: {
                                Label("Mark All Read", systemImage: "envelope.open")
                            }
                            
                            Button(role: .destructive) {
                                clearAllNotifications()
                            } label: {
                                Label("Clear All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.body)
                        }
                    }
                }
            }
            .task {
                await fetchNotifications()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "bell")
                .font(.system(size: 48))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("No notifications yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("When friends like or comment on your rankings, you'll see it here.")
                .font(.body)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var notificationsList: some View {
        List {
            ForEach(notifications) { notification in
                NotificationRow(notification: notification)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        markAsRead(notification)
                        handleNotificationTap(notification)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteNotification(notification)
                        } label: {
                            Label("Clear", systemImage: "trash")
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.visible)
                    .listRowSeparatorTint(Color.adaptiveDivider)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await fetchNotifications()
        }
        .sheet(item: $selectedFeedItem) { feedItem in
            CommentsSheet(feedItem: feedItem, onDismiss: {
                selectedFeedItem = nil
            })
        }
        .navigationDestination(item: $selectedFriend) { friend in
            FriendProfileView(friend: friend)
        }
    }
    
    private func fetchNotifications() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct NotificationData: Decodable {
                let id: String
                let type: String
                let from_user_id: String
                let user_game_id: String?
                let is_read: Bool
                let created_at: String
                let feed_post_id: String?
                let from_user: UserInfo
                let user_games: GameInfo?
                let feed_posts: FeedPostInfo?
                
                struct FeedPostInfo: Decodable {
                    let post_type: String?
                }
                
                struct UserInfo: Decodable {
                    let username: String?
                }
                
                struct GameInfo: Decodable {
                    let games: GameDetails
                    let description: String?
                    
                    struct GameDetails: Decodable {
                        let title: String
                        let cover_url: String?
                        let release_date: String?
                        let rawg_id: Int?
                    }
                }
            }
            
            let rows: [NotificationData] = try await supabase.client
                .from("notifications")
                .select("id, type, from_user_id, user_game_id, feed_post_id, is_read, created_at, from_user:users!from_user_id(username), user_games(games(title, cover_url)), feed_posts(post_type)")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            // Collect feed_post_ids for batch posts so we can fetch game titles
            let batchRankedPostIds = rows
                .filter { $0.feed_posts?.post_type == "batch_ranked" && $0.feed_post_id != nil }
                .compactMap { $0.feed_post_id?.lowercased() }
            
            let batchWtpPostIds = rows
                .filter { $0.feed_posts?.post_type == "batch_want_to_play" && $0.feed_post_id != nil }
                .compactMap { $0.feed_post_id?.lowercased() }
            
            let batchPostIds = batchRankedPostIds
            
            // Fetch child game titles for batch posts
            var batchGameTitles: [String: (title: String, coverURL: String?, count: Int)] = [:]
            if !batchPostIds.isEmpty {
                struct BatchChild: Decodable {
                    let batch_post_id: String
                    let user_games: ChildGame?
                    struct ChildGame: Decodable {
                        let games: ChildGameDetails
                        struct ChildGameDetails: Decodable {
                            let title: String
                            let cover_url: String?
                        }
                    }
                }
                
                let children: [BatchChild] = try await supabase.client
                    .from("feed_posts")
                    .select("batch_post_id, user_games(games(title, cover_url))")
                    .in("batch_post_id", values: batchPostIds.map { $0.lowercased() })
                    .eq("post_type", value: "ranked_game")
                    .order("created_at", ascending: true)
                    .execute()
                    .value
                
                // Group by batch_post_id, take first game title + count
                var grouped: [String: [(String, String?)]] = [:]
                for child in children {
                    guard let batchId = Optional(child.batch_post_id),
                          let game = child.user_games else { continue }
                    grouped[batchId, default: []].append((game.games.title, game.games.cover_url))
                }
                for (batchId, games) in grouped {
                    if let first = games.first {
                        batchGameTitles[batchId] = (title: first.0, coverURL: first.1, count: games.count)
                    }
                }
            }
            
            // Fetch child game titles for batch want-to-play posts
            if !batchWtpPostIds.isEmpty {
                struct WtpBatchChild: Decodable {
                    let batch_post_id: String
                    let metadata: WtpMeta?
                    struct WtpMeta: Decodable {
                        let game_title: String?
                        let game_cover_url: String?
                    }
                }
                
                let wtpChildren: [WtpBatchChild] = try await supabase.client
                    .from("feed_posts")
                    .select("batch_post_id, metadata")
                    .in("batch_post_id", values: batchWtpPostIds)
                    .eq("post_type", value: "want_to_play")
                    .order("created_at", ascending: true)
                    .execute()
                    .value
                
                var wtpGrouped: [String: [(String, String?)]] = [:]
                for child in wtpChildren {
                    let title = child.metadata?.game_title ?? "Unknown"
                    let cover = child.metadata?.game_cover_url
                    wtpGrouped[child.batch_post_id, default: []].append((title, cover))
                }
                for (batchId, games) in wtpGrouped {
                    if let first = games.first {
                        batchGameTitles[batchId] = (title: first.0, coverURL: first.1, count: games.count)
                    }
                }
            }
            
            notifications = rows.map { row in
                let isBatch = row.feed_posts?.post_type == "batch_ranked" || row.feed_posts?.post_type == "batch_want_to_play"
                let batchInfo = row.feed_post_id.flatMap { batchGameTitles[$0] }
                
                let gameTitle: String?
                let coverURL: String?
                if isBatch, let info = batchInfo {
                    gameTitle = info.count > 1 ? "\(info.title) and \(info.count - 1) other\(info.count - 1 == 1 ? "" : "s")" : info.title
                    coverURL = info.coverURL
                } else {
                    gameTitle = row.user_games?.games.title
                    coverURL = row.user_games?.games.cover_url
                }
                
                return AppNotification(
                    id: row.id,
                    type: NotificationType(rawValue: row.type) ?? .like,
                    fromUserId: row.from_user_id,
                    fromUsername: row.from_user.username ?? "Someone",
                    userGameId: row.user_game_id,
                    feedPostId: row.feed_post_id,
                    gameTitle: gameTitle,
                    gameCoverURL: coverURL,
                    postType: row.feed_posts?.post_type,
                    isRead: row.is_read,
                    createdAt: row.created_at
                )
            }
            
            isLoading = false
            
        } catch {
            debugLog("❌ Error fetching notifications: \(error)")
            isLoading = false
        }
    }
    
    private func markAsRead(_ notification: AppNotification) {
        guard !notification.isRead else { return }
        
        Task {
            do {
                try await supabase.client
                    .from("notifications")
                    .update(["is_read": true])
                    .eq("id", value: notification.id)
                    .execute()
                
                // Update local state
                if let index = notifications.firstIndex(where: { $0.id == notification.id }) {
                    let newUnreadCount = notifications.filter { !$0.isRead && $0.id != notification.id }.count
                        try? await UNUserNotificationCenter.current().setBadgeCount(newUnreadCount)
                    notifications[index] = AppNotification(
                        id: notification.id,
                        type: notification.type,
                        fromUserId: notification.fromUserId,
                        fromUsername: notification.fromUsername,
                        userGameId: notification.userGameId,
                        feedPostId: notification.feedPostId,
                        gameTitle: notification.gameTitle,
                        gameCoverURL: notification.gameCoverURL,
                        postType: notification.postType,
                        isRead: true,
                        createdAt: notification.createdAt
                    )
                }
                
            } catch {
                debugLog("❌ Error marking notification as read: \(error)")
            }
        }
    }
    
    private func markAllAsRead() {
        guard let userId = supabase.currentUser?.id else { return }
        
        Task {
            do {
                try await supabase.client
                    .from("notifications")
                    .update(["is_read": true])
                    .eq("user_id", value: userId.uuidString)
                    .eq("is_read", value: false)
                    .execute()
                
                // Update local state
                notifications = notifications.map { notification in
                    AppNotification(
                        id: notification.id,
                        type: notification.type,
                        fromUserId: notification.fromUserId,
                        fromUsername: notification.fromUsername,
                        userGameId: notification.userGameId,
                        feedPostId: notification.feedPostId,
                        gameTitle: notification.gameTitle,
                        gameCoverURL: notification.gameCoverURL,
                        postType: notification.postType,
                        isRead: true,
                        createdAt: notification.createdAt
                    )
                }
                
                try await UNUserNotificationCenter.current().setBadgeCount(0)
                                
            } catch {
                debugLog("❌ Error marking all as read: \(error)")
            }
        }
    }
    
    private func deleteNotification(_ notification: AppNotification) {
        Task {
            do {
                try await supabase.client
                    .from("notifications")
                    .delete()
                    .eq("id", value: notification.id)
                    .execute()
                
                notifications.removeAll { $0.id == notification.id }
                
                let newUnreadCount = notifications.filter { !$0.isRead }.count
                try? await UNUserNotificationCenter.current().setBadgeCount(newUnreadCount)
                
            } catch {
                debugLog("❌ Error deleting notification: \(error)")
            }
        }
    }

    private func clearAllNotifications() {
        guard let userId = supabase.currentUser?.id else { return }
        
        Task {
            do {
                try await supabase.client
                    .from("notifications")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                
                notifications.removeAll()
                try? await UNUserNotificationCenter.current().setBadgeCount(0)
                
            } catch {
                debugLog("❌ Error clearing all notifications: \(error)")
            }
        }
    }
    
    private func handleNotificationTap(_ notification: AppNotification) {
        switch notification.type {
        case .like, .comment:
            // Open comments sheet for this post
            guard let feedPostId = notification.feedPostId, !feedPostId.isEmpty else { return }
            let userGameId = notification.userGameId ?? ""
            
            // Fetch actual rank position
            Task {
                var rankPosition: Int? = nil
                do {
                    struct UserGameRow: Decodable {
                        let rank_position: Int?
                    }
                    let rows: [UserGameRow] = try await supabase.client
                        .from("user_games")
                        .select("rank_position")
                        .eq("id", value: userGameId)
                        .limit(1)
                        .execute()
                        .value
                    rankPosition = rows.first?.rank_position
                } catch {
                    debugLog("❌ Error fetching rank for notification: \(error)")
                }
                
                selectedFeedItem = FeedItem(
                    id: userGameId,
                    feedPostId: notification.feedPostId ?? "",
                    userGameId: userGameId,
                    userId: supabase.currentUser?.id.uuidString ?? "",
                    username: "You",
                    avatarURL: nil,
                    gameId: 0,
                    gameTitle: notification.gameTitle ?? "Unknown Game",
                    gameCoverURL: notification.gameCoverURL,
                    rankPosition: rankPosition,
                    loggedAt: nil,
                    batchSource: nil,
                    likeCount: 0,
                    commentCount: 0,
                    isLikedByMe: false
                )
            }
            
        case .friendRequest, .friendAccepted:
            // Navigate to the friend's profile
            selectedFriend = Friend(
                id: notification.fromUserId,
                friendshipId: "",
                username: notification.fromUsername,
                userId: notification.fromUserId
            )
        }
    }
}

// MARK: - Models

enum NotificationType: String {
    case like
    case comment
    case friendRequest = "friend_request"
    case friendAccepted = "friend_accepted"
}

struct AppNotification: Identifiable {
    let id: String
    let type: NotificationType
    let fromUserId: String
    let fromUsername: String
    let userGameId: String?
    let feedPostId: String?
    let gameTitle: String?
    let gameCoverURL: String?
    let postType: String?
    let isRead: Bool
    let createdAt: String
}

// MARK: - Notification Row

struct NotificationRow: View {
    let notification: AppNotification
    
    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(notification.isRead ? Color.clear : Color.orange)
                .frame(width: 8, height: 8)
            
            // Icon or cover art
            if let coverURL = notification.gameCoverURL {
                CachedAsyncImage(url: coverURL) {
                    Rectangle()
                        .fill(Color.secondaryBackground)
                }
                .frame(width: 40, height: 54)
                .cornerRadius(4)
                .clipped()
            } else {
                Circle()
                    .fill(Color.primaryBlue.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: iconForType)
                            .foregroundColor(.primaryBlue)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(messageText)
                    .font(.subheadline)
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(3)
                
                Text(timeAgo(from: notification.createdAt))
                    .font(.caption)
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(notification.isRead ? Color.clear : Color.primaryBlue.opacity(0.05))
    }
    
    private var iconForType: String {
        switch notification.type {
        case .like:
            return "heart.fill"
        case .comment:
            return "bubble.right.fill"
        case .friendRequest:
            return "person.badge.plus"
        case .friendAccepted:
            return "person.2.fill"
        }
    }
    
    private var messageText: AttributedString {
        var result = AttributedString()
        
        var username = AttributedString(notification.fromUsername)
        username.font = .system(size: 15, weight: .semibold, design: .rounded)
        result.append(username)
        
        var action = AttributedString("")
        switch notification.type {
        case .like:
            let isWtp = notification.postType == "batch_want_to_play" || notification.postType == "want_to_play"
            if let game = notification.gameTitle {
                action = AttributedString(isWtp ? " liked your Want to Play post for \(game)" : " liked your ranking of \(game)")
            } else {
                action = AttributedString(isWtp ? " liked your Want to Play post" : " liked your ranking")
            }
        case .comment:
            let isWtp = notification.postType == "batch_want_to_play" || notification.postType == "want_to_play"
            if let game = notification.gameTitle {
                action = AttributedString(isWtp ? " commented on your Want to Play post for \(game)" : " commented on your ranking of \(game)")
            } else {
                action = AttributedString(isWtp ? " commented on your Want to Play post" : " commented on your ranking")
            }
        case .friendRequest:
            action = AttributedString(" sent you a friend request")
        case .friendAccepted:
            action = AttributedString(" accepted your friend request")
        }
        action.font = .system(size: 15, design: .rounded)
        result.append(action)
        
        return result
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
    NotificationsView()
}
