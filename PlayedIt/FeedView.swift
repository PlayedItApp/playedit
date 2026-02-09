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
                let game_id: Int
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
                let avatar_url: String?
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
                .select("id, user_id, game_id, rank_position, logged_at, games(title, cover_url), users(username, avatar_url)")
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
                    avatarURL: row.users.avatar_url,
                    gameId: row.game_id,
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
    let avatarURL: String?
    let gameId: Int
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
    @State private var showGameDetail = false
    @State private var toastMessage = ""
    @State private var showToast = false
    
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
                
                // Profile photo
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
            .padding(12)
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
                                                
                // Bookmark (only on friends' posts)
                if item.userId.lowercased() != (SupabaseManager.shared.currentUser?.id.uuidString.lowercased() ?? "") {
                    HStack(spacing: 6) {
                        if showToast {
                            Text(toastMessage)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.grayText)
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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

// MARK: - Feed Game Detail Sheet
struct FeedGameDetailSheet: View {
    let item: FeedItem
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var userGame: UserGame? = nil
    @State private var friend: Friend? = nil
    @State private var myGames: [UserGame] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { dismiss() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.silver)
                            }
                        }
                    }
            } else if let userGame = userGame, let friend = friend {
                GameDetailFromFriendView(
                    userGame: userGame,
                    friend: friend,
                    myGames: myGames
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.silver)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Couldn't load game details")
                        .font(.system(size: 16, design: .rounded))
                        .foregroundColor(.grayText)
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
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let canonical_game_id: Int?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                }
            }
            
            // 1. Fetch the user_game entry
            let row: UserGameRow = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("id", value: item.userGameId)
                .single()
                .execute()
                .value
            
            userGame = UserGame(
                id: row.id,
                gameId: row.game_id,
                userId: row.user_id,
                rankPosition: row.rank_position,
                platformPlayed: row.platform_played,
                notes: row.notes,
                loggedAt: row.logged_at,
                canonicalGameId: row.canonical_game_id,
                gameTitle: row.games.title,
                gameCoverURL: row.games.cover_url,
                gameReleaseDate: row.games.release_date
            )
            
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
            
            // Find the friendship ID
            struct FriendshipRow: Decodable {
                let id: String
            }
            
            let friendshipId: String
            if item.userId.lowercased() == userId.uuidString.lowercased() {
                // It's your own post
                friendshipId = ""
            } else {
                let friendships: [FriendshipRow] = try await supabase.client
                    .from("friendships")
                    .select("id")
                    .or("and(user_id.eq.\(userId.uuidString),friend_id.eq.\(item.userId)),and(user_id.eq.\(item.userId),friend_id.eq.\(userId.uuidString))")
                    .eq("status", value: "accepted")
                    .limit(1)
                    .execute()
                    .value
                
                friendshipId = friendships.first?.id ?? ""
            }
            
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
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: userId.uuidString)
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            myGames = myRows.map { r in
                UserGame(
                    id: r.id,
                    gameId: r.game_id,
                    userId: r.user_id,
                    rankPosition: r.rank_position,
                    platformPlayed: r.platform_played,
                    notes: r.notes,
                    loggedAt: r.logged_at,
                    canonicalGameId: r.canonical_game_id,
                    gameTitle: r.games.title,
                    gameCoverURL: r.games.cover_url,
                    gameReleaseDate: r.games.release_date
                )
            }
            
        } catch {
            print("❌ Error loading feed game detail: \(error)")
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
                    .foregroundColor(isWantToPlay ? .accentOrange : .grayText)
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
            print("❌ Error checking ranked status: \(error)")
        }
    }
}

#Preview {
    FeedView(unreadNotificationCount: .constant(3))
}
