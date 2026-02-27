import SwiftUI
import Supabase

struct CommentsSheet: View {
    let feedItem: FeedItem
    let onDismiss: () -> Void
    
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var comments: [FeedComment] = []
    @State private var newComment = ""
    @State private var isLoading = true
    @State private var isSending = false
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputFocused: Bool
    @State private var editingComment: FeedComment? = nil
    @State private var replyingTo: FeedComment? = nil
    @State private var editText = ""
    @State private var moderationError: String?
    @State private var hiddenCommentIds: Set<String> = []
    @State private var reportingComment: FeedComment? = nil
    @State private var isPostMuted = false
    @State private var mutedCommentIds: Set<String> = []

    private var isPostOwner: Bool {
        feedItem.userId.lowercased() == (supabase.currentUser?.id.uuidString ?? "").lowercased()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Post header
                HStack(spacing: 12) {
                    if feedItem.gameCoverURL != nil {
                        CachedAsyncImage(url: feedItem.gameCoverURL) {
                            Rectangle()
                                .fill(Color.secondaryBackground)
                        }
                        .frame(width: 40, height: 54)
                        .cornerRadius(4)
                        .clipped()
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if feedItem.gameTitle == "Reset Rankings" {
                            HStack(spacing: 4) {
                                Text(feedItem.username)
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primaryBlue)
                                Text("rebuilt their rankings")
                            }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                        } else if feedItem.rankPosition == nil && feedItem.userGameId.isEmpty {
                            // Batch post
                            Text(feedItem.gameTitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                                .lineLimit(2)
                        } else {
                            Text("\(feedItem.username) ranked")
                                .font(.caption)
                                .foregroundStyle(Color.adaptiveGray)
                            Text(feedItem.gameTitle)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                                .lineLimit(1)
                            if let rank = feedItem.rankPosition {
                                Text("at #\(rank)")
                                    .font(.caption)
                                    .foregroundColor(.primaryBlue)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.secondaryBackground.opacity(0.5))
                
                Divider()
                
                // Comments list
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.adaptiveSilver)
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundStyle(Color.adaptiveGray)
                        Text("Be the first to comment!")
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments) { comment in
                                VStack(alignment: .leading, spacing: 0) {
                                    CommentRowView(
                                        comment: comment,
                                        isPostOwner: isPostOwner,
                                        onEdit: {
                                            editingComment = comment
                                            editText = comment.content
                                        },
                                        onDelete: {
                                            deleteComment(comment)
                                        },
                                        isReported: hiddenCommentIds.contains(comment.id),
                                        onReport: {
                                            reportingComment = comment
                                        },
                                        onReply: {
                                            replyingTo = comment
                                            isInputFocused = true
                                        },
                                        onLike: {
                                            toggleCommentLike(comment)
                                        },
                                        onMuteThread: {
                                            toggleMuteThread(comment)
                                        },
                                        isThreadMuted: mutedCommentIds.contains(comment.id)
                                    )
                                    
                                    // Threaded replies
                                    if !comment.replies.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            ForEach(comment.replies) { reply in
                                                CommentRowView(
                                                    comment: reply,
                                                    isPostOwner: isPostOwner,
                                                    onEdit: {
                                                        editingComment = reply
                                                        editText = reply.content
                                                    },
                                                    onDelete: {
                                                        deleteComment(reply)
                                                    },
                                                    isReported: hiddenCommentIds.contains(reply.id),
                                                    onReport: {
                                                        reportingComment = reply
                                                    },
                                                    onReply: nil,
                                                    onLike: {
                                                        toggleCommentLike(reply)
                                                    },
                                                    isReply: true
                                                )
                                            }
                                        }
                                        .padding(.leading, 42)
                                        .padding(.top, 8)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom)
                    }
                }
                
                Divider()
                
                // Comment input
                VStack(spacing: 0) {
                    SpoilerHint()
                        .padding(.horizontal)
                        .padding(.top, 4)
                    if let moderationError = moderationError {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.error)
                            Text(moderationError)
                                .font(.caption)
                                .foregroundColor(.error)
                            Spacer()
                            Button {
                                self.moderationError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    if let replyTarget = replyingTo {
                        HStack {
                            Text("Replying to \(replyTarget.username)")
                                .font(.caption)
                                .foregroundColor(.primaryBlue)
                            Spacer()
                            Button {
                                replyingTo = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    if editingComment != nil {
                        HStack {
                            Text("Editing comment")
                                .font(.caption)
                                .foregroundColor(.primaryBlue)
                            Spacer()
                            Button {
                                editingComment = nil
                                editText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    HStack(spacing: 12) {
                        if editingComment != nil {
                            TextField("Edit comment...", text: $editText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .lineLimit(1...4)
                                .focused($isInputFocused)
                            
                            Button {
                                saveEdit()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .silver : .primaryBlue)
                            }
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                        } else {
                            TextField("Add a comment...", text: $newComment, axis: .vertical)
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                                .lineLimit(1...4)
                                .focused($isInputFocused)
                            
                            Button {
                                sendComment()
                            } label: {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .silver : .primaryBlue)
                            }
                            .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                        }
                    }
                    .padding()
                }
                .background(Color.cardBackground) 
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            toggleMutePost()
                        } label: {
                            Label(
                                isPostMuted ? "Unmute notifications" : "Mute notifications",
                                systemImage: isPostMuted ? "bell.fill" : "bell.slash"
                            )
                        }
                    } label: {
                        Image(systemName: isPostMuted ? "bell.slash.fill" : "bell.fill")
                            .font(.system(size: 14))
                            .foregroundColor(isPostMuted ? .adaptiveGray : .primaryBlue)
                    }
                }
            }
            .task {
                await fetchComments()
                await checkMuteStatus()
                await fetchMutedThreads()
            }
            .sheet(item: $reportingComment) { comment in
                ReportView(
                    contentType: .comment,
                    contentId: UUID(uuidString: comment.id),
                    contentText: comment.content,
                    reportedUserId: UUID(uuidString: comment.userId) ?? UUID()
                )
                .presentationDetents([.large])
            }
        }
    }
    
    private func fetchComments() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        do {
            struct CommentData: Decodable {
                let id: String
                let user_id: String
                let content: String
                let created_at: String
                let parent_comment_id: String?
                let users: UserInfo?
                
                struct UserInfo: Decodable {
                    let username: String?
                    let avatar_url: String?
                }
            }
            
            let data: [CommentData] = try await supabase.client
                .from("feed_comments")
                .select("id, user_id, content, created_at, parent_comment_id, users(username, avatar_url)")
                .eq("feed_post_id", value: feedItem.feedPostId)
                .order("created_at", ascending: true)
                .execute()
                .value
            
            // Fetch comment reactions
            let commentIds = data.map { $0.id }
            
            struct CommentReactionRow: Decodable {
                let comment_id: String
                let user_id: String
            }
            
            var reactionRows: [CommentReactionRow] = []
            if !commentIds.isEmpty {
                reactionRows = try await supabase.client
                    .from("comment_reactions")
                    .select("comment_id, user_id")
                    .in("comment_id", values: commentIds)
                    .execute()
                    .value
            }
            
            var commentLikeCountMap: [String: Int] = [:]
            var myLikedCommentIds: Set<String> = []
            
            for reaction in reactionRows {
                commentLikeCountMap[reaction.comment_id, default: 0] += 1
                if reaction.user_id.lowercased() == userId.uuidString.lowercased() {
                    myLikedCommentIds.insert(reaction.comment_id)
                }
            }
            
            // Build flat list
            let allComments = data.map { row in
                FeedComment(
                    id: row.id,
                    userId: row.user_id,
                    username: row.users?.username ?? "User",
                    avatarURL: row.users?.avatar_url,
                    content: row.content,
                    createdAt: row.created_at,
                    isOwn: row.user_id.lowercased() == userId.uuidString.lowercased(),
                    parentCommentId: row.parent_comment_id,
                    likeCount: commentLikeCountMap[row.id] ?? 0,
                    isLikedByMe: myLikedCommentIds.contains(row.id),
                    replies: []
                )
            }
            
            // Build threaded structure
            let repliesByParent = Dictionary(grouping: allComments.filter { $0.parentCommentId != nil }) { $0.parentCommentId! }
            
            comments = allComments
                .filter { $0.parentCommentId == nil }
                .map { comment in
                    var c = comment
                    c.replies = repliesByParent[comment.id] ?? []
                    return c
                }
            
            isLoading = false
        } catch {
            debugLog("❌ Error fetching comments: \(error)")
            isLoading = false
        }
    }
    
    private func sendComment() {
        guard let userId = supabase.currentUser?.id else { return }
        let content = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        moderationError = nil
        
        Task {
            // Check comment moderation
            let result = await ModerationService.shared.moderateComment(content)
            if !result.allowed {
                moderationError = result.reason
                isSending = false
                return
            }
            do {
                struct CommentInsert: Encodable {
                    let feed_post_id: String
                    let user_game_id: String?
                    let user_id: String
                    let content: String
                    let parent_comment_id: String?
                }
                
                try await supabase.client
                    .from("feed_comments")
                    .insert(CommentInsert(
                        feed_post_id: feedItem.feedPostId,
                        user_game_id: feedItem.userGameId.isEmpty ? nil : feedItem.userGameId,
                        user_id: userId.uuidString,
                        content: content,
                        parent_comment_id: replyingTo?.id
                    ))
                    .execute()
                
                newComment = ""
                replyingTo = nil
                isInputFocused = false
                await fetchComments()
                
            } catch {
                debugLog("❌ Error sending comment: \(error)")
            }
            
            isSending = false
        }
    }
    
    private func deleteComment(_ comment: FeedComment) {
            Task {
                do {
                    try await supabase.client
                        .from("feed_comments")
                        .delete()
                        .eq("id", value: comment.id)
                        .execute()
                    
                    await fetchComments()
                    
                } catch {
                    debugLog("❌ Error deleting comment: \(error)")
                }
            }
        }
    
    private func toggleMuteThread(_ comment: FeedComment) {
            guard let userId = supabase.currentUser?.id else { return }
            
            Task {
                do {
                    if mutedCommentIds.contains(comment.id) {
                        try await supabase.client
                            .from("muted_threads")
                            .delete()
                            .eq("user_id", value: userId.uuidString)
                            .eq("comment_id", value: comment.id)
                            .execute()
                        mutedCommentIds.remove(comment.id)
                    } else {
                        try await supabase.client
                            .from("muted_threads")
                            .insert([
                                "user_id": userId.uuidString,
                                "feed_post_id": feedItem.feedPostId,
                                "comment_id": comment.id
                            ])
                            .execute()
                        mutedCommentIds.insert(comment.id)
                    }
                } catch {
                    debugLog("❌ Error toggling thread mute: \(error)")
                }
            }
        }
        
        private func fetchMutedThreads() async {
            guard let userId = supabase.currentUser?.id else { return }
            
            do {
                struct MuteRow: Decodable {
                    let comment_id: String?
                }
                let rows: [MuteRow] = try await supabase.client
                    .from("muted_threads")
                    .select("comment_id")
                    .eq("user_id", value: userId.uuidString)
                    .eq("feed_post_id", value: feedItem.feedPostId)
                    .not("comment_id", operator: .is, value: "null")
                    .execute()
                    .value
                mutedCommentIds = Set(rows.compactMap { $0.comment_id })
            } catch {
                debugLog("❌ Error fetching muted threads: \(error)")
            }
        }
    
    private func toggleMutePost() {
            guard let userId = supabase.currentUser?.id else { return }
            
            Task {
                do {
                    if isPostMuted {
                        try await supabase.client
                            .from("muted_threads")
                            .delete()
                            .eq("user_id", value: userId.uuidString)
                            .eq("feed_post_id", value: feedItem.feedPostId)
                            .is("comment_id", value: nil)
                            .execute()
                    } else {
                        try await supabase.client
                            .from("muted_threads")
                            .insert([
                                "user_id": userId.uuidString,
                                "feed_post_id": feedItem.feedPostId
                            ])
                            .execute()
                    }
                    isPostMuted.toggle()
                } catch {
                    debugLog("❌ Error toggling mute: \(error)")
                }
            }
        }
        
        private func checkMuteStatus() async {
            guard let userId = supabase.currentUser?.id else { return }
            
            do {
                struct MuteRow: Decodable { let id: String }
                let rows: [MuteRow] = try await supabase.client
                    .from("muted_threads")
                    .select("id")
                    .eq("user_id", value: userId.uuidString)
                    .eq("feed_post_id", value: feedItem.feedPostId)
                    .is("comment_id", value: nil)
                    .limit(1)
                    .execute()
                    .value
                isPostMuted = !rows.isEmpty
            } catch {
                debugLog("❌ Error checking mute status: \(error)")
            }
        }
    
    private func toggleCommentLike(_ comment: FeedComment) {
            guard let userId = supabase.currentUser?.id else { return }
            
            Task {
                do {
                    if comment.isLikedByMe {
                        try await supabase.client
                            .from("comment_reactions")
                            .delete()
                            .eq("comment_id", value: comment.id)
                            .eq("user_id", value: userId.uuidString)
                            .execute()
                    } else {
                        try await supabase.client
                            .from("comment_reactions")
                            .insert([
                                "comment_id": comment.id,
                                "user_id": userId.uuidString
                            ])
                            .execute()
                    }
                    await fetchComments()
                } catch {
                    debugLog("❌ Error toggling comment like: \(error)")
                }
            }
        }
    
    private func saveEdit() {
        guard let comment = editingComment else { return }
        let content = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        moderationError = nil
        
        Task {
            // Check comment moderation
            let result = await ModerationService.shared.moderateComment(content)
            if !result.allowed {
                moderationError = result.reason
                isSending = false
                return
            }
                do {
                    try await supabase.client
                        .from("feed_comments")
                        .update(["content": content])
                        .eq("id", value: comment.id)
                        .execute()
                    
                    isInputFocused = false
                    await fetchComments()
                    editingComment = nil
                    editText = ""
                    
                } catch {
                    debugLog("❌ Error editing comment: \(error)")
                }
                
                isSending = false
            }
        }
}

// MARK: - Comment Model
struct FeedComment: Identifiable {
    let id: String
    let userId: String
    let username: String
    let avatarURL: String?
    let content: String
    let createdAt: String
    let isOwn: Bool
    let parentCommentId: String?
    var likeCount: Int
    var isLikedByMe: Bool
    var replies: [FeedComment]
}

// MARK: - Comment Row View
struct CommentRowView: View {
    let comment: FeedComment
    let isPostOwner: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    var isReported: Bool = false
    var onReport: (() -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onLike: (() -> Void)? = nil
    var onMuteThread: (() -> Void)? = nil
    var isThreadMuted: Bool = false
    var isReply: Bool = false
    
    @State private var showDeleteConfirm = false
    
    private var canDelete: Bool {
        comment.isOwn || isPostOwner
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let avatarURL = comment.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .overlay(
                                Text(String(comment.username.prefix(1)).uppercased())
                                    .font(.system(size: isReply ? 10 : 14, weight: .semibold))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: isReply ? 24 : 32, height: isReply ? 24 : 32)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.primaryBlue.opacity(0.2))
                        .frame(width: isReply ? 24 : 32, height: isReply ? 24 : 32)
                        .overlay(
                            Text(String(comment.username.prefix(1)).uppercased())
                                .font(.system(size: isReply ? 10 : 14, weight: .semibold))
                                .foregroundColor(.primaryBlue)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.username)
                        .font(.system(size: isReply ? 13 : 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text(timeAgo(from: comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                    
                    Spacer()
                    
                    Menu {
                        if comment.isOwn {
                            Button {
                                onEdit()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        
                        if comment.isOwn || isPostOwner {
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        
                        if !comment.isOwn {
                            Button(role: .destructive) {
                                onReport?()
                            } label: {
                                Label("Report", systemImage: "flag")
                            }
                        }
                        
                        if comment.isOwn && !isReply {
                            Button {
                                onMuteThread?()
                            } label: {
                                Label(
                                    isThreadMuted ? "Unmute replies" : "Mute replies",
                                    systemImage: isThreadMuted ? "bell.fill" : "bell.slash"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: isReply ? 12 : 14))
                            .foregroundStyle(Color.adaptiveGray)
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .confirmationDialog("Delete comment?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
                
                if isReported {
                    Text("You reported this comment")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .italic()
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                        .background(Color.secondaryBackground)
                        .cornerRadius(8)
                } else {
                    SpoilerTextView(comment.content, font: .system(size: isReply ? 13 : 14), color: .primary)
                }
                
                // Like & Reply buttons
                HStack(spacing: 16) {
                    Button {
                        onLike?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: comment.isLikedByMe ? "heart.fill" : "heart")
                                .font(.system(size: 12))
                                .foregroundStyle(comment.isLikedByMe ? Color.orange : Color.adaptiveGray)
                            if comment.likeCount > 0 {
                                Text("\(comment.likeCount)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(comment.isLikedByMe ? Color.orange : Color.adaptiveGray)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if !isReply {
                        Button {
                            onReply?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 12))
                                Text("Reply")
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(Color.adaptiveGray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
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
            return "\(mins)m"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d"
        }
    }
}

#Preview {
    CommentsSheet(
        feedItem: FeedItem(
            id: "1",
            feedPostId: "1",
            userGameId: "1",
            userId: "user1",
            username: "TestUser",
            avatarURL: nil,
            gameId: 0,
            gameTitle: "The Legend of Zelda: Breath of the Wild",
            gameCoverURL: nil,
            rankPosition: 1,
            loggedAt: nil,
            batchSource: nil,
            likeCount: 5,
            commentCount: 3,
            isLikedByMe: true
        ),
        onDismiss: {}
    )
}
