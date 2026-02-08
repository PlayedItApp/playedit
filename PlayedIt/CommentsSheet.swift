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
    @State private var editText = ""

    private var isPostOwner: Bool {
        feedItem.userId.lowercased() == (supabase.currentUser?.id.uuidString ?? "").lowercased()
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Post header
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: feedItem.gameCoverURL ?? "")) { image in
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
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(feedItem.username) ranked")
                            .font(.caption)
                            .foregroundColor(.grayText)
                        Text(feedItem.gameTitle)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                            .lineLimit(1)
                        Text("at #\(feedItem.rankPosition)")
                            .font(.caption)
                            .foregroundColor(.primaryBlue)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color.lightGray.opacity(0.5))
                
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
                            .foregroundColor(.silver)
                        Text("No comments yet")
                            .font(.subheadline)
                            .foregroundColor(.grayText)
                        Text("Be the first to comment!")
                            .font(.caption)
                            .foregroundColor(.grayText)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(comments) { comment in
                                CommentRowView(
                                    comment: comment,
                                    isPostOwner: isPostOwner,
                                    onEdit: {
                                        editingComment = comment
                                        editText = comment.content
                                    },
                                    onDelete: {
                                        deleteComment(comment)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
                
                Divider()
                
                // Comment input
                VStack(spacing: 0) {
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
                                    .foregroundColor(.grayText)
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
                .background(Color.white)
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
            }
            .task {
                await fetchComments()
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
                let users: UserInfo?
                
                struct UserInfo: Decodable {
                    let username: String?
                    let avatar_url: String?
                }
            }
            
            let data: [CommentData] = try await supabase.client
                .from("feed_comments")
                .select("id, user_id, content, created_at, users(username, avatar_url)")
                .eq("user_game_id", value: feedItem.userGameId)
                .order("created_at", ascending: true)
                .execute()
                .value
            
            comments = data.map { row in
                FeedComment(
                    id: row.id,
                    userId: row.user_id,
                    username: row.users?.username ?? "User",
                    avatarURL: row.users?.avatar_url,
                    content: row.content,
                    createdAt: row.created_at,
                    isOwn: row.user_id.lowercased() == userId.uuidString.lowercased()
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error fetching comments: \(error)")
            isLoading = false
        }
    }
    
    private func sendComment() {
        guard let userId = supabase.currentUser?.id else { return }
        let content = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        
        Task {
            do {
                try await supabase.client
                    .from("feed_comments")
                    .insert([
                        "user_game_id": feedItem.userGameId,
                        "user_id": userId.uuidString,
                        "content": content
                    ])
                    .execute()
                
                newComment = ""
                isInputFocused = false
                await fetchComments()
                
            } catch {
                print("❌ Error sending comment: \(error)")
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
                print("❌ Error deleting comment: \(error)")
            }
        }
    }
    
    private func saveEdit() {
        guard let comment = editingComment else { return }
        let content = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        
        isSending = true
        
        Task {
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
                print("❌ Error editing comment: \(error)")
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
}

// MARK: - Comment Row View
struct CommentRowView: View {
    let comment: FeedComment
    let isPostOwner: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    // Can delete if: it's your own comment OR you own the post
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
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.primaryBlue.opacity(0.2))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(String(comment.username.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primaryBlue)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.username)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                    
                    Text(timeAgo(from: comment.createdAt))
                        .font(.caption)
                        .foregroundColor(.grayText)
                    
                    Spacer()
                    
                    if comment.isOwn || isPostOwner {
                        Menu {
                            if comment.isOwn {
                                Button {
                                    onEdit()
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                            }
                            
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.caption)
                                .foregroundColor(.grayText)
                                .padding(4)
                        }
                    }
                }
                
                Text(comment.content)
                    .font(.subheadline)
                    .foregroundColor(.slate)
            }
        }
        .confirmationDialog("Delete comment?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
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
            userGameId: "1",
            userId: "user1",
            username: "TestUser",
            gameTitle: "The Legend of Zelda: Breath of the Wild",
            gameCoverURL: nil,
            rankPosition: 1,
            loggedAt: nil,
            likeCount: 5,
            commentCount: 3,
            isLikedByMe: true
        ),
        onDismiss: {}
    )
}
