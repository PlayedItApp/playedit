import SwiftUI
import Supabase

struct FriendsView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var friends: [Friend] = []
    @State private var pendingRequests: [Friend] = []
    @State private var isLoading = true
    @State private var showAddFriend = false
    @State private var searchUsername = ""
    @State private var searchError: String?
    @State private var searchSuccess: String?
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                } else {
                    friendsListView
                }
            }
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                addFriendSheet
            }
        }
        .task {
            await fetchFriends()
        }
    }
    
    private var friendsListView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Pending requests
                if !pendingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Friend Requests")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.grayText)
                            .padding(.horizontal, 16)
                        
                        ForEach(pendingRequests) { friend in
                            PendingRequestRow(friend: friend) {
                                Task { await acceptFriend(friend) }
                            } onDecline: {
                                Task { await declineFriend(friend) }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // Friends list
                if friends.isEmpty && pendingRequests.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.silver)
                        
                        Text("No friends yet")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        
                        Text("Add some friends and see how your taste compares!")
                            .font(.body)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        
                        Button {
                            showAddFriend = true
                        } label: {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Add Friend")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 40)
                    }
                } else if !friends.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Friends")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.grayText)
                            .padding(.horizontal, 16)
                        
                        ForEach(friends) { friend in
                            NavigationLink(destination: FriendProfileView(friend: friend)) {
                                FriendRow(friend: friend)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable {
            await fetchFriends()
        }
    }
    
    private var addFriendSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter username")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.grayText)
                    
                    TextField("username", text: $searchUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                if let error = searchError {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.error)
                        .padding(.horizontal, 20)
                }
                
                if let success = searchSuccess {
                    Text(success)
                        .font(.callout)
                        .foregroundColor(.success)
                        .padding(.horizontal, 20)
                }
                
                Button {
                    Task { await sendFriendRequest() }
                } label: {
                    Text("Send Friend Request")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 20)
                .disabled(searchUsername.isEmpty)
                
                Spacer()
            }
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddFriend = false
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
    }
    
    private func fetchFriends() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        print("🔍 Current user ID: \(userId.uuidString)")
        
        do {
            struct FriendshipRow: Decodable {
                let id: String
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("*")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .execute()
                .value
            
            print("🔍 Found \(friendships.count) friendships")
            for f in friendships {
                print("   - id: \(f.id), user_id: \(f.user_id), friend_id: \(f.friend_id), status: \(f.status)")
            }
            
            var acceptedFriends: [Friend] = []
            var pending: [Friend] = []
            
            for friendship in friendships {
                let friendUserId = friendship.user_id.lowercased() == userId.uuidString.lowercased() ? friendship.friend_id : friendship.user_id
                let isIncoming = friendship.friend_id.lowercased() == userId.uuidString.lowercased()
                
                print("🔍 Processing friendship: friendUserId=\(friendUserId), isIncoming=\(isIncoming)")
                
                // Fetch friend's user info
                struct UserInfo: Decodable {
                    let id: String
                    let username: String?
                    let email: String?
                }
                
                do {
                    let userInfo: UserInfo = try await supabase.client
                        .from("users")
                        .select("id, username, email")
                        .eq("id", value: friendUserId)
                        .single()
                        .execute()
                        .value
                    
                    print("🔍 Found user: \(userInfo.username ?? "no username")")
                    
                    let friend = Friend(
                        id: friendship.id,
                        friendshipId: friendship.id,
                        username: userInfo.username ?? userInfo.email ?? "Unknown",
                        userId: friendUserId
                    )
                    
                    if friendship.status == "accepted" {
                        acceptedFriends.append(friend)
                    } else if friendship.status == "pending" && isIncoming {
                        pending.append(friend)
                        print("🔍 Added to pending requests")
                    }
                } catch {
                    print("❌ Error fetching user info for \(friendUserId): \(error)")
                }
            }
            
            friends = acceptedFriends
            pendingRequests = pending
            isLoading = false
            
            print("🔍 Final: \(friends.count) friends, \(pendingRequests.count) pending")
            
        } catch {
            print("❌ Error fetching friends: \(error)")
            isLoading = false
        }
    }
    
    private func sendFriendRequest() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        searchError = nil
        searchSuccess = nil
        
        do {
            // Find user by username
            struct UserSearch: Decodable {
                let id: String
                let username: String?
            }
            
            let users: [UserSearch] = try await supabase.client
                .from("users")
                .select("id, username")
                .eq("username", value: searchUsername)
                .execute()
                .value
            
            guard let foundUser = users.first else {
                searchError = "Couldn't find that user. Double-check the username?"
                return
            }
            
            if foundUser.id == userId.uuidString {
                searchError = "You can't add yourself as a friend!"
                return
            }
            
            // Send friend request
            struct FriendRequest: Encodable {
                let user_id: String
                let friend_id: String
                let status: String
            }
            
            try await supabase.client
                .from("friendships")
                .insert(FriendRequest(
                    user_id: userId.uuidString,
                    friend_id: foundUser.id,
                    status: "pending"
                ))
                .execute()
            
            searchSuccess = "Friend request sent to \(searchUsername)!"
            searchUsername = ""
            
        } catch {
            print("❌ Error sending friend request: \(error)")
            searchError = "Couldn't send request. Maybe you're already friends?"
        }
    }
    
    private func acceptFriend(_ friend: Friend) async {
        do {
            try await supabase.client
                .from("friendships")
                .update(["status": "accepted"])
                .eq("id", value: friend.friendshipId)
                .execute()
            
            await fetchFriends()
            
        } catch {
            print("❌ Error accepting friend: \(error)")
        }
    }
    
    private func declineFriend(_ friend: Friend) async {
        do {
            try await supabase.client
                .from("friendships")
                .delete()
                .eq("id", value: friend.friendshipId)
                .execute()
            
            await fetchFriends()
            
        } catch {
            print("❌ Error declining friend: \(error)")
        }
    }
}

// MARK: - Friend Model
struct Friend: Identifiable {
    let id: String
    let friendshipId: String
    let username: String
    let userId: String
    
    init(id: String, friendshipId: String, username: String, userId: String) {
        self.id = id
        self.friendshipId = friendshipId
        self.username = username
        self.userId = userId
    }
}

// MARK: - Friend Row
struct FriendRow: View {
    let friend: Friend
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.primaryBlue.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(friend.username.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.primaryBlue)
                )
            
            Text(friend.username)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.slate)
            
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
}

// MARK: - Pending Request Row
struct PendingRequestRow: View {
    let friend: Friend
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentOrange.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(friend.username.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.accentOrange)
                )
            
            Text(friend.username)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.slate)
            
            Spacer()
            
            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.grayText)
                    .frame(width: 32, height: 32)
                    .background(Color.lightGray)
                    .cornerRadius(8)
            }
            
            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.primaryBlue)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Friend Profile View (placeholder)
struct FriendProfileView: View {
    let friend: Friend
    
    var body: some View {
        Text("Profile for \(friend.username)")
            .navigationTitle(friend.username)
    }
}

#Preview {
    FriendsView()
}
