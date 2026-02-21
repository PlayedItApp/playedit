import SwiftUI
import Supabase

struct FeedView: View {
    @Binding var unreadNotificationCount: Int
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var feedItems: [FeedItem] = []
    @State private var combinedFeed: [FeedEntry] = []
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
                } else if combinedFeed.isEmpty {
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
                        showGameSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
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
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("Your feed is quiet")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Add friends or log some games to get things moving.")
                .font(.body)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    private var feedListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(combinedFeed) { entry in
                    switch entry {
                    case .game(let item):
                        FeedItemRow(
                            item: item,
                            onLikeTapped: { toggleLike(for: item) },
                            onCommentTapped: { selectedItem = item }
                        )
                    case .groupedGames(let group):
                        GroupedFeedRow(
                            group: group,
                            onLikeTapped: { toggleGroupLike(for: group) },
                            onCommentTapped: {
                                selectedItem = FeedItem(
                                    id: group.id,
                                    feedPostId: group.feedPostId,
                                    userGameId: "",
                                    userId: group.userId,
                                    username: group.username,
                                    avatarURL: group.avatarURL,
                                    gameId: 0,
                                    gameTitle: "\(group.username) ranked \(group.gameCount) games",
                                    gameCoverURL: nil,
                                    rankPosition: nil,
                                    loggedAt: nil,
                                    batchSource: group.batchSource,
                                    likeCount: group.likeCount,
                                    commentCount: group.commentCount,
                                    isLikedByMe: group.isLikedByMe
                                )
                            }
                        )
                    case .activity(let item):
                        ActivityFeedRow(
                            item: item,
                            onLikeTapped: { toggleActivityLike(for: item) },
                            onCommentTapped: {
                                selectedItem = FeedItem(
                                    id: item.id,
                                    feedPostId: item.feedPostId,
                                    userGameId: "",
                                    userId: item.userId,
                                    username: item.username,
                                    avatarURL: item.avatarURL,
                                    gameId: 0,
                                    gameTitle: "Reset Rankings",
                                    gameCoverURL: nil,
                                    rankPosition: nil,
                                    loggedAt: nil,
                                    batchSource: nil,
                                    likeCount: item.likeCount,
                                    commentCount: item.commentCount,
                                    isLikedByMe: item.isLikedByMe
                                )
                            }
                        )
                    }
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
                    try await supabase.client
                        .from("feed_reactions")
                        .delete()
                        .eq("feed_post_id", value: item.feedPostId)
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                } else {
                    try await supabase.client
                        .from("feed_reactions")
                        .insert([
                            "feed_post_id": item.feedPostId,
                            "user_game_id": item.userGameId,
                            "user_id": userId.uuidString,
                            "emoji": "❤️"
                        ])
                        .execute()
                }
                
                await fetchFeed()
                
            } catch {
                debugLog("❌ Error toggling like: \(error)")
            }
        }
    }
    
    private func toggleGroupLike(for group: GroupedFeedItem) {
        guard let userId = supabase.currentUser?.id else { return }
        
        Task {
            do {
                if group.isLikedByMe {
                    try await supabase.client
                        .from("feed_reactions")
                        .delete()
                        .eq("feed_post_id", value: group.feedPostId)
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                } else {
                    try await supabase.client
                        .from("feed_reactions")
                        .insert([
                            "feed_post_id": group.feedPostId,
                            "user_id": userId.uuidString,
                            "emoji": "❤️"
                        ])
                        .execute()
                }
                
                await fetchFeed()
                
            } catch {
                debugLog("❌ Error toggling group like: \(error)")
            }
        }
    }
    
    private func toggleActivityLike(for item: ActivityFeedItem) {
            guard let userId = supabase.currentUser?.id else { return }
            
            Task {
                do {
                    if item.isLikedByMe {
                        try await supabase.client
                            .from("feed_reactions")
                            .delete()
                            .eq("feed_post_id", value: item.feedPostId)
                            .eq("user_id", value: userId.uuidString)
                            .execute()
                    } else {
                        try await supabase.client
                            .from("feed_reactions")
                            .insert([
                                "feed_post_id": item.feedPostId,
                                "user_id": userId.uuidString,
                                "emoji": "❤️"
                            ])
                            .execute()
                    }
                    
                    await fetchFeed()
                    
                } catch {
                    debugLog("❌ Error toggling activity like: \(error)")
                }
            }
        }

    
    private func fetchFeed() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct Friendship: Decodable {
                let user_id: String
                let friend_id: String
                let status: String
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
                f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
            }
            feedUserIds.append(userId.uuidString)
            
            // Fetch feed_posts
            struct FeedPostRow: Decodable {
                let id: String
                let user_id: String
                let post_type: String
                let user_game_id: String?
                let activity_feed_id: String?
                let batch_post_id: String?
                let metadata: BatchMetadata?
                let created_at: String
                let users: UserInfo
                let user_games: GamePostInfo?
                
                struct BatchMetadata: Decodable {
                    let game_count: Int?
                    let user_game_ids: [String]?
                }
                
                struct UserInfo: Decodable {
                    let username: String?
                    let avatar_url: String?
                }
                
                struct GamePostInfo: Decodable {
                    let game_id: Int
                    let rank_position: Int?
                    let logged_at: String?
                    let batch_source: String?
                    let games: GameDetails
                    
                    struct GameDetails: Decodable {
                        let title: String
                        let cover_url: String?
                        let release_date: String?
                        let rawg_id: Int?
                    }
                }
            }
            
            let posts: [FeedPostRow] = try await supabase.client
                .from("feed_posts")
                .select("id, user_id, post_type, user_game_id, activity_feed_id, batch_post_id, metadata, created_at, users(username, avatar_url), user_games(game_id, rank_position, logged_at, batch_source, games(title, cover_url))")
                .in("user_id", values: feedUserIds)
                .order("created_at", ascending: false)
                .limit(100)
                .execute()
                .value
            
            let feedPostIds = posts.map { $0.id }
            
            guard !feedPostIds.isEmpty else {
                feedItems = []
                combinedFeed = []
                isLoading = false
                return
            }
            
            // Fetch reactions for all posts
            struct ReactionRow: Decodable {
                let feed_post_id: String
                let user_id: String
            }
            
            let reactions: [ReactionRow] = try await supabase.client
                .from("feed_reactions")
                .select("feed_post_id, user_id")
                .in("feed_post_id", values: feedPostIds)
                .execute()
                .value
            
            var likeCountMap: [String: Int] = [:]
            var myLikedIds: Set<String> = []
            
            for reaction in reactions {
                likeCountMap[reaction.feed_post_id, default: 0] += 1
                if reaction.user_id.lowercased() == userId.uuidString.lowercased() {
                    myLikedIds.insert(reaction.feed_post_id)
                }
            }
            
            // Fetch comment counts
            struct CommentCountRow: Decodable {
                let feed_post_id: String
            }
            
            let commentRows: [CommentCountRow] = try await supabase.client
                .from("feed_comments")
                .select("feed_post_id")
                .in("feed_post_id", values: feedPostIds)
                .execute()
                .value
            
            var commentCountMap: [String: Int] = [:]
            for comment in commentRows {
                commentCountMap[comment.feed_post_id, default: 0] += 1
            }
            
            feedItems = []
            // Build combined feed
            var combined: [FeedEntry] = []
            
            for post in posts {
                let likes = likeCountMap[post.id] ?? 0
                let comments = commentCountMap[post.id] ?? 0
                let isLiked = myLikedIds.contains(post.id)
                
                switch post.post_type {
                case "ranked_game":
                    // Skip if this post belongs to a batch — it'll be included via the batch_ranked post
                    if post.batch_post_id != nil { continue }
                    
                    guard let ug = post.user_games, ug.rank_position != nil else { continue }
                    let item = FeedItem(
                        id: post.user_game_id ?? post.id,
                        feedPostId: post.id,
                        userGameId: post.user_game_id ?? "",
                        userId: post.user_id,
                        username: post.users.username ?? "Friend",
                        avatarURL: post.users.avatar_url,
                        gameId: ug.game_id,
                        gameTitle: ug.games.title,
                        gameCoverURL: ug.games.cover_url,
                        rankPosition: ug.rank_position,
                        loggedAt: ug.logged_at,
                        batchSource: ug.batch_source,
                        likeCount: likes,
                        commentCount: comments,
                        isLikedByMe: isLiked
                    )
                    feedItems.append(item)
                    combined.append(.game(item))
                    
                case "batch_ranked":
                    // Build grouped entry from the batch's child posts
                    let childPosts = posts.filter { p in
                        p.batch_post_id == post.id && p.post_type == "ranked_game"
                    }
                    
                    let childItems: [FeedItem] = childPosts.compactMap { child in
                        guard let ug = child.user_games, ug.rank_position != nil else { return nil }
                        let childLikes = likeCountMap[child.id] ?? 0
                        let childComments = commentCountMap[child.id] ?? 0
                        let childIsLiked = myLikedIds.contains(child.id)
                        return FeedItem(
                            id: child.user_game_id ?? child.id,
                            feedPostId: child.id,
                            userGameId: child.user_game_id ?? "",
                            userId: child.user_id,
                            username: child.users.username ?? "Friend",
                            avatarURL: child.users.avatar_url,
                            gameId: ug.game_id,
                            gameTitle: ug.games.title,
                            gameCoverURL: ug.games.cover_url,
                            rankPosition: ug.rank_position,
                            loggedAt: ug.logged_at,
                            batchSource: ug.batch_source,
                            likeCount: childLikes,
                            commentCount: childComments,
                            isLikedByMe: childIsLiked
                        )
                    }
                    
                    guard !childItems.isEmpty else { continue }
                    
                    let group = GroupedFeedItem(
                        id: post.id,
                        userId: post.user_id,
                        username: post.users.username ?? "Friend",
                        avatarURL: post.users.avatar_url,
                        items: childItems,
                        batchSource: childItems.first?.batchSource,
                        mostRecentDate: post.created_at,
                        feedPostId: post.id,
                        likeCount: likes,
                        commentCount: comments,
                        isLikedByMe: isLiked
                    )
                    combined.append(.groupedGames(group))
                    
                case "reset_rankings":
                    let item = ActivityFeedItem(
                        id: post.activity_feed_id ?? post.id,
                        feedPostId: post.id,
                        userId: post.user_id,
                        username: post.users.username ?? "Friend",
                        avatarURL: post.users.avatar_url,
                        activityType: post.post_type,
                        createdAt: post.created_at,
                        likeCount: likes,
                        commentCount: comments,
                        isLikedByMe: isLiked
                    )
                    combined.append(.activity(item))
                    
                default:
                    continue
                }
            }
            
            combinedFeed = combined
            isLoading = false
            
        } catch {
            debugLog("❌ Error fetching feed: \(error)")
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
            debugLog("❌ Error fetching unread count: \(error)")
        }
    }
}

// MARK: - Activity Feed Item Model
struct ActivityFeedItem: Identifiable {
    let id: String
    let feedPostId: String
    let userId: String
    let username: String
    let avatarURL: String?
    let activityType: String
    let createdAt: String
    let likeCount: Int
    let commentCount: Int
    let isLikedByMe: Bool
}

// MARK: - Combined Feed Entry
enum FeedEntry: Identifiable {
    case game(FeedItem)
    case activity(ActivityFeedItem)
    case groupedGames(GroupedFeedItem)
    
    var id: String {
        switch self {
        case .game(let item): return "game-\(item.id)"
        case .activity(let item): return "activity-\(item.id)"
        case .groupedGames(let group): return "group-\(group.id)"
        }
    }
    
    var sortDate: String {
        switch self {
        case .game(let item): return item.loggedAt ?? ""
        case .activity(let item): return item.createdAt
        case .groupedGames(let group): return group.mostRecentDate
        }
    }
    
    var userId: String {
        switch self {
        case .game(let item): return item.userId
        case .activity(let item): return item.userId
        case .groupedGames(let group): return group.userId
        }
    }
}

// MARK: - Grouped Feed Item
struct GroupedFeedItem: Identifiable {
    let id: String
    let userId: String
    let username: String
    let avatarURL: String?
    let items: [FeedItem]
    let batchSource: String?
    let mostRecentDate: String
    let feedPostId: String
    let likeCount: Int
    let commentCount: Int
    let isLikedByMe: Bool
    
    var gameCount: Int { items.count }
    
    // Pull out any #1 ranked game to show separately
    var newNumberOne: FeedItem? {
        items.first { $0.rankPosition == 1 }
    }
    
    var collapsedItems: [FeedItem] {
        items.filter { $0.rankPosition != 1 }
    }
    
    var displayLabel: String {
        switch batchSource {
        case "steam_import":
            return "\(username) imported their Steam library — \(gameCount) games ranked"
        case "onboarding":
            return "\(username) just joined and ranked \(gameCount) games!"
        default:
            return "\(username) ranked \(gameCount) games"
        }
    }
}

// MARK: - Feed Item Model
struct FeedItem: Identifiable {
    let id: String
    let feedPostId: String
    let userGameId: String
    let userId: String
    let username: String
    let avatarURL: String?
    let gameId: Int
    let gameTitle: String
    let gameCoverURL: String?
    let rankPosition: Int?
    let loggedAt: String?
    let batchSource: String?
    let likeCount: Int
    let commentCount: Int
    let isLikedByMe: Bool
}

// MARK: - Feed Item Row
struct FeedItemRow: View {
    let item: FeedItem
    let onLikeTapped: () -> Void
    let onCommentTapped: () -> Void
    @State private var showGameDetail = false
    @State private var toastMessage = ""
    @State private var showToast = false
    @State private var showReportSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main content
            Button {
                showGameDetail = true
            } label: {
                HStack(spacing: 12) {
                // Cover art
                AsyncImage(url: URL(string: item.gameCoverURL ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondaryBackground)
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(Color.adaptiveSilver)
                        )
                }
                .frame(width: 50, height: 67)
                .cornerRadius(6)
                .clipped()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.username) ranked")
                        .font(.subheadline)
                        .foregroundStyle(Color.adaptiveGray)
                    
                    Text(item.gameTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .lineLimit(2)
                    
                    HStack(spacing: 4) {
                        Text("at #\(item.rankPosition ?? 0)")
                            .font(.subheadline)
                            .foregroundColor(.primaryBlue)
                        
                        if let loggedAt = item.loggedAt {
                            Text("• \(timeAgo(from: loggedAt))")
                                .font(.caption)
                                .foregroundStyle(Color.adaptiveGray)
                        }
                    }
                }
                
                    Spacer()
                                    
                    // Profile photo - tap to view profile (only for friends' posts)
                    NavigationLink(destination: item.userId.lowercased() == (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") ? AnyView(ProfileView()) : AnyView(FriendProfileView(friend: Friend(id: item.userId, friendshipId: "", username: item.username, userId: item.userId, avatarURL: item.avatarURL)))) {
                        Group {
                            if let avatarURL = item.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.primaryBlue.opacity(0.2))
                                .overlay(
                                    Text(String(item.username.prefix(1)).uppercased())
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.primaryBlue)
                                )
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text(String(item.username.prefix(1)).uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                }
                }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            
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
                            .foregroundStyle(item.isLikedByMe ? Color.orange : Color.adaptiveGray)
                        
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
                                .font(.subheadline)
                                .foregroundStyle(item.isLikedByMe ? Color.orange : Color.adaptiveGray)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Comment button
                Button(action: onCommentTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.adaptiveGray)
                        
                        if item.commentCount > 0 {
                            Text("\(item.commentCount)")
                                .font(.subheadline)
                                .foregroundStyle(Color.adaptiveGray)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                                                
                // Bookmark (only on friends' posts)
                if item.userId.lowercased() != (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") {
                    HStack(spacing: 6) {
                        if showToast {
                            Text(toastMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                                .transition(.opacity)
                        }
                        BookmarkButton(
                            gameId: item.gameId,
                            gameTitle: item.gameTitle,
                            gameCoverUrl: item.gameCoverURL,
                            source: "feed",
                            sourceFriendId: item.userId,
                            onToast: { message in
                                toastMessage = message
                                withAnimation { showToast = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    withAnimation { showToast = false }
                                }
                            }
                        )
                    }
                }
                // Report (only on friends' posts)
                if item.userId.lowercased() != (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") {
                    Menu {
                        Button(role: .destructive) {
                            showReportSheet = true
                        } label: {
                            Label("Report", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.adaptiveGray)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showReportSheet) {
            ReportView(
                contentType: .note,
                contentId: UUID(uuidString: item.userGameId),
                contentText: nil,
                reportedUserId: UUID(uuidString: item.userId) ?? UUID()
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showGameDetail) {
            FeedGameDetailSheet(item: item)
        }
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

// MARK: - Activity Feed Row
struct ActivityFeedRow: View {
    let item: ActivityFeedItem
    let onLikeTapped: () -> Void
    let onCommentTapped: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Avatar - tap to view profile
                NavigationLink(destination: item.userId.lowercased() == (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") ? AnyView(ProfileView()) : AnyView(FriendProfileView(friend: Friend(id: item.userId, friendshipId: "", username: item.username, userId: item.userId, avatarURL: item.avatarURL)))) {
                    if let avatarURL = item.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            avatarPlaceholder
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(item.username)
                        Text("rebuilt their rankings")
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                    }
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text(timeAgo(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                Spacer()
            }
            .padding(12)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Like and Comment buttons
            HStack(spacing: 24) {
                Button(action: onLikeTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: item.isLikedByMe ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundStyle(item.isLikedByMe ? Color.orange : Color.adaptiveGray)
                        
                        if item.likeCount > 0 {
                            Text("\(item.likeCount)")
                                .font(.subheadline)
                                .foregroundStyle(item.isLikedByMe ? Color.orange : Color.adaptiveGray)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: onCommentTapped) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.adaptiveGray)
                        
                        if item.commentCount > 0 {
                            Text("\(item.commentCount)")
                                .font(.subheadline)
                                .foregroundStyle(Color.adaptiveGray)
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
        
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.primaryBlue.opacity(0.2))
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(item.username.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primaryBlue)
            )
    }
    
    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else { return "" }
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 { return "Just now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }
}

//// MARK: - Feed Game Detail Sheet
struct FeedGameDetailSheet: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var userGame: UserGame? = nil
    @State private var friend: Friend? = nil
    @State private var myGames: [UserGame] = []
    @State private var isLoading = true
    
    var body: some View {
        Group {
            if isLoading {
                NavigationStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button { dismiss() } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.adaptiveSilver)
                                }
                            }
                        }
                }
            } else if let userGame = userGame {
                if item.userId.lowercased() == (supabase.currentUser?.id.uuidString.lowercased() ?? "") {
                    GameDetailSheet(game: userGame, rank: userGame.rankPosition)
                } else if let friend = friend {
                    NavigationStack {
                        GameDetailFromFriendView(
                            userGame: userGame,
                            friend: friend,
                            myGames: myGames
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button { dismiss() } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Color.adaptiveSilver)
                                }
                            }
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Couldn't load game details")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                        Button("Dismiss") { dismiss() }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Couldn't load game details")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                    Button("Dismiss") { dismiss() }
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int?
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let canonical_game_id: Int?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                    let rawg_id: Int?
                }
            }
            
            // 1. Fetch the user_game entry
            let row: UserGameRow = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("id", value: item.userGameId)
                .single()
                .execute()
                .value
            
            userGame = UserGame(
                id: row.id,
                gameId: row.game_id,
                userId: row.user_id,
                rankPosition: row.rank_position ?? 0,
                platformPlayed: row.platform_played,
                notes: row.notes,
                loggedAt: row.logged_at,
                canonicalGameId: row.canonical_game_id,
                gameTitle: row.games.title,
                gameCoverURL: row.games.cover_url,
                gameReleaseDate: row.games.release_date,
                gameRawgId: row.games.rawg_id
            )
            
            // Skip friend/myGames fetch if it's own post
            if item.userId.lowercased() == userId.uuidString.lowercased() {
                isLoading = false
                return
            }
            
            // 2. Fetch the poster's profile and friendship
            struct UserProfile: Decodable {
                let id: String
                let username: String?
                let avatar_url: String?
            }
            
            let profile: UserProfile = try await supabase.client
                .from("users")
                .select("id, username, avatar_url")
                .eq("id", value: item.userId)
                .single()
                .execute()
                .value
            
            struct FriendshipRow: Decodable {
                let id: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("id")
                .or("and(user_id.eq.\(userId.uuidString),friend_id.eq.\(item.userId)),and(user_id.eq.\(item.userId),friend_id.eq.\(userId.uuidString))")
                .eq("status", value: "accepted")
                .limit(1)
                .execute()
                .value
            
            let friendshipId = friendships.first?.id ?? ""
            
            friend = Friend(
                id: friendshipId,
                friendshipId: friendshipId,
                username: profile.username ?? item.username,
                userId: profile.id,
                avatarURL: profile.avatar_url
            )
             
            // 3. Fetch my games
            let myRows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            myGames = myRows.map { r in
                UserGame(
                    id: r.id,
                    gameId: r.game_id,
                    userId: r.user_id,
                    rankPosition: r.rank_position ?? 0,
                    platformPlayed: r.platform_played,
                    notes: r.notes,
                    loggedAt: r.logged_at,
                    canonicalGameId: r.canonical_game_id,
                    gameTitle: r.games.title,
                    gameCoverURL: r.games.cover_url,
                    gameReleaseDate: r.games.release_date,
                    gameRawgId: r.games.rawg_id
                )
            }
            
        } catch {
            debugLog("❌ Error loading feed game detail: \(error)")
        }
        
        isLoading = false
    }
}

// MARK: - Bookmark Button
struct BookmarkButton: View {
    let gameId: Int
    let gameTitle: String
    let gameCoverUrl: String?
    let source: String
    var sourceFriendId: String? = nil
    var onToast: ((String) -> Void)? = nil
    
    @ObservedObject private var manager = WantToPlayManager.shared
    @State private var isRanked = false
    
    var body: some View {
        let isWantToPlay = manager.myWantToPlayIds.contains(gameId)
        
        if !isRanked {
            Button {
                Task { await handleTap(isWantToPlay: isWantToPlay) }
            } label: {
                Image(systemName: isWantToPlay ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18))
                    .foregroundStyle(isWantToPlay ? Color.accentOrange : Color.adaptiveGray)
            }
            .buttonStyle(.plain)
            .task {
                await checkIfRanked()
            }
        }
    }
    
    private func handleTap(isWantToPlay: Bool) async {
        if isWantToPlay {
            let success = await manager.removeGame(gameId: gameId)
            if success { onToast?("Removed") }
        } else {
            let success = await manager.addGame(
                gameId: gameId,
                gameTitle: gameTitle,
                gameCoverUrl: gameCoverUrl,
                source: source,
                sourceFriendId: sourceFriendId
            )
            if success { onToast?("Saved!") }
        }
    }
    
    private func checkIfRanked() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        do {
            let response: [UserGameWithRawgId] = try await SupabaseManager.shared.client
                .from("user_games")
                .select("game_id, games(rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            let rankedIds = Set(response.compactMap { $0.games?.rawg_id })
            isRanked = rankedIds.contains(gameId)
        } catch {
            debugLog("❌ Error checking ranked status: \(error)")
        }
    }
}

// MARK: - Grouped Feed Row
struct GroupedFeedRow: View {
    let group: GroupedFeedItem
    let onLikeTapped: () -> Void
    let onCommentTapped: () -> Void
    @State private var isExpanded = false
    @State private var selectedItem: FeedItem?
    @State private var selectedCommentItem: FeedItem?
    @State private var localLikeOverrides: [String: Bool] = [:]
    @State private var localLikeCountOverrides: [String: Int] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Avatar
                NavigationLink(destination: group.userId.lowercased() == (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") ? AnyView(ProfileView()) : AnyView(FriendProfileView(friend: Friend(id: group.userId, friendshipId: "", username: group.username, userId: group.userId, avatarURL: group.avatarURL)))) {
                    if let avatarURL = group.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            avatarPlaceholder
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        avatarPlaceholder
                    }
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayLabel)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text(timeAgo(from: group.mostRecentDate))
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                }
                
                Spacer()
                
                // Batch icon
                Image(systemName: batchIcon)
                    .font(.system(size: 16))
                    .foregroundColor(.primaryBlue)
            }
            .padding(12)
            
            // Cover art grid
            coverArtGrid
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 12)
            
            // Like/Comment bar (when collapsed)
            if !isExpanded {
                HStack(spacing: 24) {
                    Button(action: onLikeTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: group.isLikedByMe ? "heart.fill" : "heart")
                                .font(.system(size: 18))
                                .foregroundStyle(group.isLikedByMe ? Color.orange : Color.adaptiveGray)
                            if group.likeCount > 0 {
                                Text("\(group.likeCount)")
                                    .font(.subheadline)
                                    .foregroundStyle(group.isLikedByMe ? Color.orange : Color.adaptiveGray)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onCommentTapped) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.right")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.adaptiveGray)
                            if group.commentCount > 0 {
                                Text("\(group.commentCount)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                
                Divider()
                    .padding(.horizontal, 12)
            }
            
            // Expand/view button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(isExpanded ? "Collapse" : "See all \(group.collapsedItems.count) games")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primaryBlue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Inline expanded list (small batches only)
            if isExpanded {
                expandedList
            }
        }
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .sheet(item: $selectedItem) { item in
            FeedGameDetailSheet(item: item)
        }
        .sheet(item: $selectedCommentItem) { item in
            CommentsSheet(feedItem: item, onDismiss: {
                selectedCommentItem = nil
            })
        }
    }
    
    // MARK: - Cover Art Grid
    private var coverArtGrid: some View {
        let displayItems = Array(group.collapsedItems.prefix(6))
        let remaining = group.collapsedItems.count - 6
        
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(displayItems.count, 3)), spacing: 8) {
            ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                ZStack {
                    AsyncImage(url: URL(string: item.gameCoverURL ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondaryBackground)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.adaptiveSilver)
                            )
                    }
                    .frame(height: 60)
                    .clipped()
                    .cornerRadius(6)
                    
                    // "+X more" badge on last item
                    if index == 5 && remaining > 0 {
                        Rectangle()
                            .fill(Color.black.opacity(0.5))
                            .cornerRadius(6)
                        
                        Text("+\(remaining)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
    
    private var expandedList: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            LazyVStack(spacing: 0) {
                    ForEach(group.collapsedItems) { item in
                        VStack(spacing: 0) {
                            // Game info row - tappable for detail
                            HStack(spacing: 10) {
                                AsyncImage(url: URL(string: item.gameCoverURL ?? "")) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.secondaryBackground)
                                        .overlay(
                                            Image(systemName: "gamecontroller")
                                                .font(.system(size: 8))
                                                .foregroundStyle(Color.adaptiveSilver)
                                        )
                                }
                                .frame(width: 36, height: 48)
                                .clipped()
                                .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.gameTitle)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                        .lineLimit(1)
                                    
                                    Text("#\(item.rankPosition ?? 0)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primaryBlue)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.adaptiveSilver)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedItem = item
                            }
                            
                            // Like/comment buttons - separate tap targets
                            HStack(spacing: 0) {
                                Button {
                                    toggleChildLike(for: item)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isChildLiked(item) ? "heart.fill" : "heart")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isChildLiked(item) ? Color.orange : Color.adaptiveGray)
                                        if childLikeCount(item) > 0 {
                                            Text("\(childLikeCount(item))")
                                                .font(.caption)
                                                .foregroundStyle(isChildLiked(item) ? Color.orange : Color.adaptiveGray)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Button {
                                    selectedCommentItem = item
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bubble.right")
                                            .font(.system(size: 14))
                                            .foregroundStyle(Color.adaptiveGray)
                                        if item.commentCount > 0 {
                                            Text("\(item.commentCount)")
                                                .font(.caption)
                                                .foregroundStyle(Color.adaptiveGray)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }
                            .padding(.leading, 46)
                            .padding(.bottom, 4)
                            
                            Divider()
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    
    private func isChildLiked(_ item: FeedItem) -> Bool {
        localLikeOverrides[item.feedPostId] ?? item.isLikedByMe
    }
    
    private func childLikeCount(_ item: FeedItem) -> Int {
        localLikeCountOverrides[item.feedPostId] ?? item.likeCount
    }
    
    private func toggleChildLike(for item: FeedItem) {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        let currentlyLiked = isChildLiked(item)
        let currentCount = childLikeCount(item)
        
        localLikeOverrides[item.feedPostId] = !currentlyLiked
        localLikeCountOverrides[item.feedPostId] = currentlyLiked ? currentCount - 1 : currentCount + 1
        
        Task {
            do {
                if currentlyLiked {
                    try await SupabaseManager.shared.client
                        .from("feed_reactions")
                        .delete()
                        .eq("feed_post_id", value: item.feedPostId)
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                } else {
                    try await SupabaseManager.shared.client
                        .from("feed_reactions")
                        .insert([
                            "feed_post_id": item.feedPostId,
                            "user_game_id": item.userGameId,
                            "user_id": userId.uuidString,
                            "emoji": "❤️"
                        ])
                        .execute()
                }
            } catch {
                localLikeOverrides[item.feedPostId] = currentlyLiked
                localLikeCountOverrides[item.feedPostId] = currentCount
                debugLog("❌ Error toggling child like: \(error)")
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.primaryBlue.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay(
                Text(String(group.username.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primaryBlue)
            )
    }
    
    private var batchIcon: String {
        switch group.batchSource {
        case "steam_import": return "arrow.down.circle"
        case "onboarding": return "star.circle"
        default: return "square.stack"
        }
    }
    
    private func timeAgo(from dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateString) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }
}

#Preview {
    FeedView(unreadNotificationCount: .constant(3))
}
