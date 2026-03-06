import SwiftUI
import Supabase

struct DeepLinkProfileView: View {
    let username: String
    @EnvironmentObject var supabase: SupabaseManager
    @State private var isLoading = true
    @State private var userNotFound = false
    @State private var lookupUser: LookupUser?
    @State private var friendshipStatus: FriendshipResult = .none
    @State private var isSendingRequest = false
    @State private var requestSent = false
    @State private var gameCount = 0
    @State private var mutualFriends: [Friend] = []
    @Environment(\.dismiss) private var dismiss
    
    enum FriendshipResult {
        case none
        case pending
        case accepted(Friend)
    }
    
    struct LookupUser: Identifiable {
        let id: String
        let username: String
        let avatarURL: String?
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
            } else if userNotFound {
                notFoundView
            } else if case .accepted(let friend) = friendshipStatus {
                FriendProfileView(friend: friend)
            } else if let user = lookupUser {
                notFriendsView(user: user)
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await lookupAndCheckFriendship()
        }
    }
    
    // MARK: - Not Found
    private var notFoundView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            
            Image(systemName: "person.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("User not found")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Couldn't find anyone with the username \"\(username)\". Double-check the link?")
                .font(.subheadline)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
    
    // MARK: - Not Friends View
    private func notFriendsView(user: LookupUser) -> some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 40)
            
            // Avatar
            Group {
                if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .overlay(
                                Text(String(user.username.prefix(1)).uppercased())
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.primaryBlue.opacity(0.2))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                        )
                }
            }
            
            // Username and game count
            VStack(spacing: 6) {
                Text(user.username)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("\(gameCount) games ranked")
                    .font(.subheadline)
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            // Mutual friends
            if !mutualFriends.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: -8) {
                        ForEach(mutualFriends.prefix(3)) { friend in
                            Group {
                                if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.primaryBlue.opacity(0.2))
                                            .overlay(
                                                Text(String(friend.username.prefix(1)).uppercased())
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .foregroundColor(.primaryBlue)
                                            )
                                    }
                                } else {
                                    Circle()
                                        .fill(Color.primaryBlue.opacity(0.2))
                                        .overlay(
                                            Text(String(friend.username.prefix(1)).uppercased())
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundColor(.primaryBlue)
                                        )
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                        }
                    }
                    
                    let names = mutualFriends.map { $0.username }
                    Text(mutualFriendsText(names: names))
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            // Action area
            if user.id.lowercased() == supabase.currentUser?.id.uuidString.lowercased() {
                Text("This is you!")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            } else if requestSent {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                    Text("Friend request sent!")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.success)
                }
            } else if case .pending = friendshipStatus {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(Color.adaptiveGray)
                    Text("Friend request pending")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Add \(user.username) as a friend to see their rankings and compare taste!")
                        .font(.subheadline)
                        .foregroundStyle(Color.adaptiveGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button {
                        Task { await sendFriendRequest(to: user) }
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text(isSendingRequest ? "Sending..." : "Add Friend")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isSendingRequest)
                    .padding(.horizontal, 40)
                }
            }
            
            Spacer()
        }
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Lookup & Check Friendship
    private func lookupAndCheckFriendship() async {
        guard let myId = supabase.currentUser?.id else {
            isLoading = false
            userNotFound = true
            return
        }
        
        do {
            // Look up user by username
            struct UserRow: Decodable {
                let id: String
                let username: String?
                let avatar_url: String?
            }
            
            let users: [UserRow] = try await supabase.client
                .from("users")
                .select("id, username, avatar_url")
                .ilike("username", pattern: username)
                .execute()
                .value
            
            guard let foundUser = users.first else {
                userNotFound = true
                isLoading = false
                return
            }
            
            lookupUser = LookupUser(
                id: foundUser.id,
                username: foundUser.username ?? username,
                avatarURL: foundUser.avatar_url
            )
            
            // Get game count
            gameCount = try await supabase.client
                .from("user_games")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: foundUser.id)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .count ?? 0
            
            // Check friendship status
            struct FriendshipRow: Decodable {
                let id: String
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("*")
                .or("and(user_id.eq.\(myId.uuidString.lowercased()),friend_id.eq.\(foundUser.id.lowercased())),and(user_id.eq.\(foundUser.id.lowercased()),friend_id.eq.\(myId.uuidString.lowercased()))")
                .execute()
                .value
            
            if let friendship = friendships.first {
                if friendship.status == "accepted" {
                    let friend = Friend(
                        id: friendship.id,
                        friendshipId: friendship.id,
                        username: foundUser.username ?? username,
                        userId: foundUser.id,
                        avatarURL: foundUser.avatar_url,
                        status: "accepted"
                    )
                    friendshipStatus = .accepted(friend)
                } else if friendship.status == "pending" {
                    friendshipStatus = .pending
                }
            }
            
            isLoading = false
                        
            // Fetch mutual friends if not already friends
            if case .accepted = friendshipStatus {
                // Already friends, no need to show mutual
            } else {
                await fetchMutualFriends(targetUserId: foundUser.id)
            }
            
        } catch {
            debugLog("❌ Error looking up user: \(error)")
            userNotFound = true
            isLoading = false
        }
    }
    
    // MARK: - Send Friend Request
    private func sendFriendRequest(to user: LookupUser) async {
        guard let myId = supabase.currentUser?.id else { return }
        
        isSendingRequest = true
        
        do {
            struct FriendRequest: Encodable {
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            try await supabase.client
                .from("friendships")
                .insert(FriendRequest(
                    user_id: myId.uuidString,
                    friend_id: user.id,
                    status: "pending"
                ))
                .execute()
            
            requestSent = true
        } catch {
            debugLog("❌ Error sending friend request: \(error)")
        }
        
        isSendingRequest = false
    }
    
    // MARK: - Mutual Friends Text
    private func mutualFriendsText(names: [String]) -> String {
        switch names.count {
        case 1:
            return "Friends with \(names[0])"
        case 2:
            return "Friends with \(names[0]) and \(names[1])"
        case 3:
            return "Friends with \(names[0]), \(names[1]), and \(names[2])"
        default:
            let extra = names.count - 2
            return "Friends with \(names[0]), \(names[1]), and \(extra) other\(extra == 1 ? "" : "s")"
        }
    }
    
    // MARK: - Fetch Mutual Friends
    private func fetchMutualFriends(targetUserId: String) async {
        guard let myId = supabase.currentUser?.id else { return }
        
        do {
            struct MutualFriendRow: Decodable {
                let user_id: String
                let username: String?
                let avatar_url: String?
            }
            
            let rows: [MutualFriendRow] = try await supabase.client
                .rpc("get_mutual_friends", params: [
                    "requesting_user_id": myId.uuidString.lowercased(),
                    "target_user_id": targetUserId.lowercased()
                ])
                .execute()
                .value
            
            mutualFriends = rows.map { row in
                Friend(
                    id: row.user_id,
                    friendshipId: "",
                    username: row.username ?? "Unknown",
                    userId: row.user_id,
                    avatarURL: row.avatar_url,
                    status: "accepted"
                )
            }
            
            debugLog("🔍 Found \(mutualFriends.count) mutual friends")
            
        } catch {
            debugLog("❌ Error fetching mutual friends: \(error)")
        }
    }
}
