import SwiftUI
import Supabase

struct NotificationsView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = true
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
                        Button("Mark All Read") {
                            markAllAsRead()
                        }
                        .font(.subheadline)
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
                .foregroundColor(.silver)
            
            Text("No notifications yet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.slate)
            
            Text("When friends like or comment on your rankings, you'll see it here.")
                .font(.body)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(notifications) { notification in
                    NotificationRow(notification: notification)
                        .onTapGesture {
                            markAsRead(notification)
                        }
                    
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
        .refreshable {
            await fetchNotifications()
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
                let from_user: UserInfo
                let user_games: GameInfo?
                
                struct UserInfo: Decodable {
                    let username: String?
                }
                
                struct GameInfo: Decodable {
                    let games: GameDetails
                    
                    struct GameDetails: Decodable {
                        let title: String
                        let cover_url: String?
                    }
                }
            }
            
            let rows: [NotificationData] = try await supabase.client
                .from("notifications")
                .select("id, type, from_user_id, user_game_id, is_read, created_at, from_user:users!from_user_id(username), user_games(games(title, cover_url))")
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            notifications = rows.map { row in
                AppNotification(
                    id: row.id,
                    type: NotificationType(rawValue: row.type) ?? .like,
                    fromUsername: row.from_user.username ?? "Someone",
                    gameTitle: row.user_games?.games.title,
                    gameCoverURL: row.user_games?.games.cover_url,
                    isRead: row.is_read,
                    createdAt: row.created_at
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error fetching notifications: \(error)")
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
                    notifications[index] = AppNotification(
                        id: notification.id,
                        type: notification.type,
                        fromUsername: notification.fromUsername,
                        gameTitle: notification.gameTitle,
                        gameCoverURL: notification.gameCoverURL,
                        isRead: true,
                        createdAt: notification.createdAt
                    )
                }
                
            } catch {
                print("❌ Error marking notification as read: \(error)")
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
                        fromUsername: notification.fromUsername,
                        gameTitle: notification.gameTitle,
                        gameCoverURL: notification.gameCoverURL,
                        isRead: true,
                        createdAt: notification.createdAt
                    )
                }
                
            } catch {
                print("❌ Error marking all as read: \(error)")
            }
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
    let fromUsername: String
    let gameTitle: String?
    let gameCoverURL: String?
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
                AsyncImage(url: URL(string: coverURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.lightGray)
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
                    .foregroundColor(.slate)
                    .lineLimit(2)
                
                Text(timeAgo(from: notification.createdAt))
                    .font(.caption)
                    .foregroundColor(.grayText)
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
            if let game = notification.gameTitle {
                action = AttributedString(" liked your ranking of \(game)")
            } else {
                action = AttributedString(" liked your ranking")
            }
        case .comment:
            if let game = notification.gameTitle {
                action = AttributedString(" commented on your ranking of \(game)")
            } else {
                action = AttributedString(" commented on your ranking")
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
