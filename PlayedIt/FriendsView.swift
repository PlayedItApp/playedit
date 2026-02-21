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
    @State private var sentRequests: [Friend] = []
    
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
                            .foregroundStyle(Color.adaptiveGray)
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
                
                // Sent requests
                if !sentRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sent Requests")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                            .padding(.horizontal, 16)
                        
                        ForEach(sentRequests) { friend in
                            NavigationLink(destination: FriendProfileView(friend: friend)) {
                                SentRequestRow(friend: friend) {
                                    Task { await cancelFriendRequest(friend) }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, 16)
                    }
                }
                
                // Friends list
                if friends.isEmpty && pendingRequests.isEmpty && sentRequests.isEmpty {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.adaptiveSilver)
                        
                        Text("No friends yet")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        Text("Add some friends and see how your taste compares!")
                            .font(.body)
                            .foregroundStyle(Color.adaptiveGray)
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
                            .foregroundStyle(Color.adaptiveGray)
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
        .onAppear {
            Task { await fetchFriends() }
        }
    }
    
    private var addFriendSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter username")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                    
                    TextField("username", text: $searchUsername)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .onChange(of: searchUsername) { _, newValue in
                            if !newValue.isEmpty {
                                searchError = nil
                                searchSuccess = nil
                            }
                        }
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
            .onAppear {
                searchUsername = ""
                searchError = nil
                searchSuccess = nil
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
        
        // Check if we have a valid session
        let session = try? await supabase.client.auth.session
        print("🔍 Session exists: \(session != nil), token prefix: \(String(session?.accessToken.prefix(20) ?? "nil"))")
        
        print("🔍 Current user ID: \(userId.uuidString)")
        print("🔍 Query filter: user_id.eq.\(userId.uuidString.lowercased()),friend_id.eq.\(userId.uuidString.lowercased())")

        
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
                .or("user_id.eq.\(userId.uuidString.lowercased()),friend_id.eq.\(userId.uuidString.lowercased())")
                .execute()
                .value
            
            print("🔍 Found \(friendships.count) friendships")
            for f in friendships {
                print("   - id: \(f.id), user_id: \(f.user_id), friend_id: \(f.friend_id), status: \(f.status)")
            }
            
            var acceptedFriends: [Friend] = []
            var pending: [Friend] = []
            var sent: [Friend] = []
            
            for friendship in friendships {
                let friendUserId = friendship.user_id.lowercased() == userId.uuidString.lowercased() ? friendship.friend_id : friendship.user_id
                let isIncoming = friendship.friend_id.lowercased() == userId.uuidString.lowercased()
                
                print("🔍 Processing friendship: friendUserId=\(friendUserId), isIncoming=\(isIncoming)")
                
                // Fetch friend's user info
                struct UserInfo: Decodable {
                    let id: String
                    let username: String?
                    let email: String?
                    let avatar_url: String?
                }
                
                do {
                    let userInfo: UserInfo = try await supabase.client
                        .from("users")
                        .select("id, username, email, avatar_url")
                        .eq("id", value: friendUserId)
                        .single()
                        .execute()
                        .value
                    
                    print("🔍 Found user: \(userInfo.username ?? "no username")")
                    
                    let friend = Friend(
                        id: friendship.id,
                        friendshipId: friendship.id,
                        username: userInfo.username ?? userInfo.email ?? "Unknown",
                        userId: friendUserId,
                        avatarURL: userInfo.avatar_url,
                        status: friendship.status
                    )
                    
                    if friendship.status == "accepted" {
                        acceptedFriends.append(friend)
                    } else if friendship.status == "pending" && isIncoming {
                        pending.append(friend)
                        print("🔍 Added to pending requests")
                    } else if friendship.status == "pending" && !isIncoming {
                        sent.append(friend)
                        print("🔍 Added to sent requests")
                    }
                } catch {
                    print("❌ Error fetching user info for \(friendUserId): \(error)")
                }
            }
            
            friends = acceptedFriends
            pendingRequests = pending
            sentRequests = sent
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
                .ilike("username", pattern: searchUsername)
                .execute()
                .value
            
            guard let foundUser = users.first else {
                searchError = "Couldn't find that user. Double-check the username?"
                return
            }
            
            if foundUser.id.lowercased() == userId.uuidString.lowercased() {
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
            await fetchFriends()
            
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
    
    private func cancelFriendRequest(_ friend: Friend) async {
            do {
                try await supabase.client
                    .from("friendships")
                    .delete()
                    .eq("id", value: friend.friendshipId)
                    .execute()
                
                await fetchFriends()
                
            } catch {
                print("❌ Error cancelling friend request: \(error)")
            }
        }
}

// MARK: - Friend Model
struct Friend: Identifiable, Hashable {
    let id: String
    let friendshipId: String
    let username: String
    let userId: String
    let avatarURL: String?
    let status: String
    
    init(id: String, friendshipId: String, username: String, userId: String, avatarURL: String? = nil, status: String = "accepted") {
        self.id = id
        self.friendshipId = friendshipId
        self.username = username
        self.userId = userId
        self.avatarURL = avatarURL
        self.status = status
    }
}

// MARK: - Friend Row
struct FriendRow: View {
    let friend: Friend
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .overlay(
                                Text(String(friend.username.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.primaryBlue.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(friend.username.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                        )
                }
            }
            
            Text(friend.username)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.adaptiveSilver)
        }
        .padding(12)
        .background(Color.cardBackground) 
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
            Group {
                if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .overlay(
                                Text(String(friend.username.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Group {
                        if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Circle()
                                    .fill(Color.primaryBlue.opacity(0.2))
                                    .overlay(
                                        Text(String(friend.username.prefix(1)).uppercased())
                                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primaryBlue)
                                    )
                            }
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.primaryBlue.opacity(0.2))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Text(String(friend.username.prefix(1)).uppercased())
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primaryBlue)
                                )
                        }
                    }
                }
            }
            
            Text(friend.username)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Spacer()
            
            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.adaptiveGray)
                    .frame(width: 32, height: 32)
                    .background(Color.secondaryBackground)
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
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Sent Request Row
struct SentRequestRow: View {
    let friend: Friend
    let onCancel: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.primaryBlue.opacity(0.2))
                            .overlay(
                                Text(String(friend.username.prefix(1)).uppercased())
                                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.primaryBlue.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(friend.username.prefix(1)).uppercased())
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(.primaryBlue)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.username)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("Pending")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            Spacer()
            
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondaryBackground)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Friend Profile View
struct FriendProfileView: View {
    let friend: Friend
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var friendGames: [UserGame] = []
    @State private var myGames: [UserGame] = []
    @State private var isLoading = true
    @State private var showCompareView = false
    @State private var showMatchInfo = false
    @State private var showBatchRank = false
    @State private var showRemoveFriendConfirm = false
    @State private var isRemovingFriend = false
    @State private var showReportSheet = false
    @State private var selectedListTab = 0
    @State private var friendWantToPlay: [WantToPlayGame] = []
    @State private var selectedWTPGame: WantToPlayGame? = nil
    @Environment(\.dismiss) private var dismiss
    
    // Computed taste match
    private var sharedGames: [(mine: UserGame, theirs: UserGame)] {
        var shared: [(mine: UserGame, theirs: UserGame)] = []
        for myGame in myGames {
            let myCanonical = myGame.canonicalGameId ?? myGame.gameId
            if let theirGame = friendGames.first(where: {
                ($0.canonicalGameId ?? $0.gameId) == myCanonical
            }) {
                shared.append((mine: myGame, theirs: theirGame))
            }
        }
        return shared
    }
    private var matchPercentage: Int {
        guard !sharedGames.isEmpty else { return 0 }
        
        // With only 1 shared game, use simple rank difference
        if sharedGames.count == 1 {
            let pair = sharedGames[0]
            let maxPossibleDiff = max(myGames.count, friendGames.count)
            let actualDiff = abs(pair.mine.rankPosition - pair.theirs.rankPosition)
            
            if maxPossibleDiff == 0 { return 100 }
            let percentage = 100 - Int((Double(actualDiff) / Double(maxPossibleDiff)) * 100)
            return max(0, min(100, percentage))
        }
        
        let n = Double(sharedGames.count)
        var sumDSquared: Double = 0
        
        // Assign relative ranks: rank by position in each user's list
        var myRelativeRanks: [Int] = Array(repeating: 0, count: sharedGames.count)
        var theirRelativeRanks: [Int] = Array(repeating: 0, count: sharedGames.count)
        
        // Sort indices by my rank position
        let myOrder = sharedGames.indices.sorted { sharedGames[$0].mine.rankPosition < sharedGames[$1].mine.rankPosition }
        for (rank, idx) in myOrder.enumerated() {
            myRelativeRanks[idx] = rank + 1
        }
        
        // Sort indices by their rank position
        let theirOrder = sharedGames.indices.sorted { sharedGames[$0].theirs.rankPosition < sharedGames[$1].theirs.rankPosition }
        for (rank, idx) in theirOrder.enumerated() {
            theirRelativeRanks[idx] = rank + 1
        }
        
        for i in sharedGames.indices {
            let d = Double(myRelativeRanks[i] - theirRelativeRanks[i])
            sumDSquared += d * d
        }
        
        // ρ = 1 - (6 * Σd²) / (n * (n² - 1))
        let denominator = n * (n * n - 1)
        guard denominator != 0 else { return 50 }
        
        let rho = 1 - (6 * sumDSquared) / denominator
        
        // Convert from [-1, 1] to [0, 100]
        let percentage = Int(((rho + 1) / 2) * 100)
        return max(0, min(100, percentage))
    }
    
    private var agreements: [(mine: UserGame, theirs: UserGame)] {
        // Games you both ranked highly (top 5 or top 25% of each list, whichever is larger)
        let myThreshold = max(5, Int(Double(myGames.count) * 0.25))
        let theirThreshold = max(5, Int(Double(friendGames.count) * 0.25))
        
        return sharedGames.filter { $0.mine.rankPosition <= myThreshold && $0.theirs.rankPosition <= theirThreshold }
            .sorted { $0.mine.rankPosition < $1.mine.rankPosition }
    }
    
    private var disagreements: [(mine: UserGame, theirs: UserGame)] {
        // Games with significant rank difference (5+ or 25% of smaller list, whichever is larger)
        let smallerListSize = min(myGames.count, friendGames.count)
        let threshold = max(5, Int(Double(smallerListSize) * 0.25))
        
        return sharedGames.filter { abs($0.mine.rankPosition - $0.theirs.rankPosition) >= threshold }
            .sorted { abs($0.mine.rankPosition - $0.theirs.rankPosition) > abs($1.mine.rankPosition - $1.theirs.rankPosition) }
    }
    
    private var theyLoveYouDont: [(mine: UserGame, theirs: UserGame)] {
        // They ranked in their top 25%, you ranked in your bottom 50%
        let theirThreshold = max(5, Int(Double(friendGames.count) * 0.25))
        let myBottomHalf = myGames.count / 2
        
        let disagreementIds = Set(disagreements.map { $0.mine.id })
        return sharedGames.filter { $0.theirs.rankPosition <= theirThreshold && $0.mine.rankPosition > myBottomHalf && !disagreementIds.contains($0.mine.id) }
            .sorted { $0.theirs.rankPosition < $1.theirs.rankPosition }
    }
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    .padding(.top, 100)
            } else if friend.status == "pending" {
                VStack(spacing: 24) {
                    profileHeader
                    
                    VStack(spacing: 12) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.adaptiveSilver)
                        
                        Text("Request pending")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        Text("You'll be able to see \(friend.username)'s rankings and compare taste once they accept your request.")
                            .font(.subheadline)
                            .foregroundStyle(Color.adaptiveGray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.top, 20)
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 24) {
                    // Profile Header
                    profileHeader
                    
                    // Taste Match Card
                    if !sharedGames.isEmpty {
                        tasteMatchCard
                    } else if !friendGames.isEmpty {
                        noSharedGamesCard
                    }
                    
                    // Compare Lists Button
                    if !friendGames.isEmpty && !myGames.isEmpty {
                        HStack(spacing: 12) {
                            Button {
                                showCompareView = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text("Compare Lists")
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            
                            Button {
                                showBatchRank = true
                            } label: {
                                HStack {
                                    Image(systemName: "gamecontroller.fill")
                                    Text("Rank Their Games")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Agreements Section
                    if !agreements.isEmpty {
                        agreementsSection
                    }
                    
                    // Disagreements Section
                    if !disagreements.isEmpty {
                        disagreementsSection
                    }
                    
                    // They Love, You Don't
                    if !theyLoveYouDont.isEmpty {
                        theyLoveSection
                    }
                    
                    // List Picker
                    Picker("List", selection: $selectedListTab) {
                        Text("Ranked").tag(0)
                        Text("Want to Play").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    
                    if selectedListTab == 0 {
                        friendListSection
                    } else {
                        friendWantToPlaySection
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if friend.status == "accepted" {
                Menu {
                    Button(role: .destructive) {
                        showRemoveFriendConfirm = true
                    } label: {
                        Label("Remove Friend", systemImage: "person.badge.minus")
                    }
                    
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.primaryBlue)
                }
                .confirmationDialog(
                    "Remove \(friend.username)?",
                    isPresented: $showRemoveFriendConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove Friend", role: .destructive) {
                        Task { await removeFriend() }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("They won't be notified. You'll need to send a new request to be friends again.")
                }
                }
            }
        }
        .sheet(isPresented: $showCompareView) {
            CompareListsView(
                myGames: myGames,
                friendGames: friendGames,
                friendName: friend.username
            )
        }
        .sheet(isPresented: $showBatchRank) {
            BatchRankSelectionView(
                friendGames: friendGames,
                myGames: myGames,
                friendName: friend.username
            )
        }
        .sheet(isPresented: $showReportSheet) {
            ReportView(
                contentType: .username,
                contentId: nil,
                contentText: friend.username,
                reportedUserId: UUID(uuidString: friend.userId) ?? UUID()
            )
            .presentationDetents([.large])
        }
        .task {
            await loadData()
        }
    }
    
    // MARK: - Profile Header
        private var profileHeader: some View {
            VStack(spacing: 12) {
                Group {
                    if let avatarURL = friend.avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Circle()
                                .fill(Color.primaryBlue.opacity(0.2))
                                .overlay(
                                    Text(String(friend.username.prefix(1)).uppercased())
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
                                Text(String(friend.username.prefix(1)).uppercased())
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.primaryBlue)
                            )
                    }
                }
            
            Text(friend.username)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            if friend.status != "pending" {
                Text("\(friendGames.count) games ranked")
                    .font(.subheadline)
                    .foregroundStyle(Color.adaptiveGray)
            }
        }
        .padding(.top, 20)
    }
    
    // MARK: - Taste Match Card
    private var tasteMatchCard: some View {
        VStack(spacing: 16) {
            // Title with info button
            HStack {
                Spacer()
                Text("Taste Match")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                Button {
                    showMatchInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.adaptiveGray)
                }
                Spacer()
            }
            
            // Big percentage
            Text("\(matchPercentage)%")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundColor(matchColor)
            
            // Label
            Text(matchLabel)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .multilineTextAlignment(.center)
            
            // Shared games count
            Text("Based on \(sharedGames.count) \(sharedGames.count == 1 ? "game" : "games") you've both ranked")
                .font(.caption)
                .foregroundStyle(Color.adaptiveGray)
            
            if sharedGames.count < 5 {
                Text("Rank more games in common for a more accurate match!")
                    .font(.caption)
                    .foregroundColor(.accentOrange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground) 
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .alert("How Taste Match Works", isPresented: $showMatchInfo) {
            Button("Got it!", role: .cancel) { }
        } message: {
            Text(matchExplanation)
        }
    }
    
    private var matchColor: Color {
        switch matchPercentage {
        case 80...100: return .teal
        case 50...79: return .primaryBlue
        default: return .accentOrange
        }
    }
    
    private var matchLabel: String {
        switch matchPercentage {
        case 80...100: return "You and \(friend.username) are taste twins! 🎮"
        case 50...79: return "You've got some common ground"
        default: return "You two should argue about games more 😄"
        }
    }
    
    private var matchExplanation: String {
        if sharedGames.count == 1 {
            let pair = sharedGames[0]
            let maxPossibleDiff = max(myGames.count, friendGames.count)
            let actualDiff = abs(pair.mine.rankPosition - pair.theirs.rankPosition)
            
            return """
            With n=1 shared game, Spearman's ρ is undefined (division by zero), so we use a linear distance metric:
            
            Match% = 100 × (1 - |d| / max(L₁, L₂))
            
            Where:
            • d = rank difference = |\(pair.mine.rankPosition) - \(pair.theirs.rankPosition)| = \(actualDiff)
            • L₁ = your list size = \(myGames.count)
            • L₂ = their list size = \(friendGames.count)
            • max(L₁, L₂) = \(maxPossibleDiff)
            
            Result: 100 × (1 - \(actualDiff)/\(maxPossibleDiff)) = \(matchPercentage)%
            """
        } else {
            let n = sharedGames.count
                        
            // Use relative ranks (same as matchPercentage calculation)
            let myOrder = sharedGames.indices.sorted { sharedGames[$0].mine.rankPosition < sharedGames[$1].mine.rankPosition }
            var myRelativeRanks = Array(repeating: 0, count: n)
            for (rank, idx) in myOrder.enumerated() { myRelativeRanks[idx] = rank + 1 }
            
            let theirOrder = sharedGames.indices.sorted { sharedGames[$0].theirs.rankPosition < sharedGames[$1].theirs.rankPosition }
            var theirRelativeRanks = Array(repeating: 0, count: n)
            for (rank, idx) in theirOrder.enumerated() { theirRelativeRanks[idx] = rank + 1 }
            
            var sumDSquared = 0
            for i in sharedGames.indices {
                let d = myRelativeRanks[i] - theirRelativeRanks[i]
                sumDSquared += d * d
            }
            return """
            Spearman's rank correlation coefficient:
            
            ρ = 1 - (6 × Σdᵢ²) / (n × (n² - 1))
            
            Where:
            • n = shared games = \(n)
            • dᵢ = rank difference for game i
            • Σdᵢ² = \(sumDSquared)
            
            ρ = 1 - (6 × \(sumDSquared)) / (\(n) × \(n * n - 1))
            
            Normalized to 0-100%:
            Match% = (ρ + 1) / 2 × 100 = \(matchPercentage)%
            """
        }
    }
    
    private var noSharedGamesCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("No shared games yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Rank some games \(friend.username) has played to see your taste match!")
                .font(.subheadline)
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.secondaryBackground)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Agreements Section
    private var agreementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "circle.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.teal)
                Text("You both loved")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.teal)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.teal.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            ForEach(agreements.prefix(5), id: \.mine.id) { pair in
                NavigationLink(destination: GameDetailFromFriendView(
                    userGame: pair.theirs,
                    friend: friend,
                    myGames: myGames
                )) {
                    ComparisonGameRow(
                        game: pair.mine,
                        myRank: pair.mine.rankPosition,
                        theirRank: pair.theirs.rankPosition,
                        friendName: friend.username
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Disagreements Section
    private var disagreementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentOrange)
                Text("Biggest debates")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.accentOrange)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentOrange.opacity(0.1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            ForEach(disagreements.prefix(5), id: \.mine.id) { pair in
                NavigationLink(destination: GameDetailFromFriendView(
                    userGame: pair.theirs,
                    friend: friend,
                    myGames: myGames
                )) {
                    ComparisonGameRow(
                        game: pair.mine,
                        myRank: pair.mine.rankPosition,
                        theirRank: pair.theirs.rankPosition,
                        friendName: friend.username
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - They Love Section
    private var theyLoveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hand.thumbsup.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.adaptiveSlate)
                Text("\(friend.username) loved these, you... didn't")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.adaptiveSlate.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            ForEach(theyLoveYouDont.prefix(5), id: \.mine.id) { pair in
                NavigationLink(destination: GameDetailFromFriendView(
                    userGame: pair.theirs,
                    friend: friend,
                    myGames: myGames
                )) {
                    ComparisonGameRow(
                        game: pair.mine,
                        myRank: pair.mine.rankPosition,
                        theirRank: pair.theirs.rankPosition,
                        friendName: friend.username
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Friend's Want to Play Section
    private var friendWantToPlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(friend.username)'s Want to Play")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .padding(.horizontal, 16)
            
            if friendWantToPlay.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.adaptiveSilver)
                    Text("\(friend.username) hasn't bookmarked any games yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.adaptiveGray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                let ranked = friendWantToPlay.filter { $0.sortPosition != nil }.sorted { ($0.sortPosition ?? 0) < ($1.sortPosition ?? 0) }
                let unranked = friendWantToPlay.filter { $0.sortPosition == nil }
                
                if !ranked.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                        Text("Prioritized")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        Text("(\(ranked.count))")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    .padding(.horizontal, 16)
                    
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, game in
                        Button {
                            selectedWTPGame = game
                        } label: {
                            FriendWantToPlayRow(game: game, position: index + 1)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
                
                if !unranked.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.adaptiveGray)
                        Text("Backlog")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        Text("(\(unranked.count))")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, ranked.isEmpty ? 0 : 8)
                    
                    ForEach(unranked) { game in
                        Button {
                            selectedWTPGame = game
                        } label: {
                            FriendWantToPlayRow(game: game, position: nil)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .sheet(item: $selectedWTPGame) { game in
            FriendWantToPlayDetailSheet(game: game, friendName: friend.username)
        }
    }
    
    // MARK: - Friend's List Section
    private var friendListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(friend.username)'s Rankings")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .padding(.horizontal, 16)
            
            if friendGames.isEmpty {
                Text("\(friend.username) hasn't ranked any games yet. Peer pressure them? 😄")
                    .font(.subheadline)
                    .foregroundStyle(Color.adaptiveGray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                ForEach(friendGames.sorted { $0.rankPosition < $1.rankPosition }) { game in
                    NavigationLink(destination: GameDetailFromFriendView(
                        userGame: game,
                        friend: friend,
                        myGames: myGames
                    )) {
                        FriendGameRow(game: game, myRank: myGames.first(where: { $0.gameId == game.gameId })?.rankPosition)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    // MARK: - Remove Friend
    private func removeFriend() async {
        isRemovingFriend = true
        do {
            try await supabase.client
                .from("friendships")
                .delete()
                .eq("id", value: friend.friendshipId)
                .execute()
            
            dismiss()
        } catch {
            print("❌ Error removing friend: \(error)")
            isRemovingFriend = false
        }
    }
    
    // MARK: - Load Data
    private func loadData() async {
        guard let userId = supabase.currentUser?.id else {
            isLoading = false
            return
        }
        
        // Don't load game data for pending friends
        if friend.status == "pending" {
            isLoading = false
            return
        }
        
        do {
            // Helper struct to decode the joined query
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                    let rawg_id: Int?
                }
            }
            
            // Fetch friend's games with join
            let friendRows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("user_id", value: friend.userId)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            friendGames = friendRows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    canonicalGameId: nil,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date,
                    gameRawgId: row.games.rawg_id
                )
            }
            
            // Fetch my games with join
            let myRows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            myGames = myRows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    canonicalGameId: nil,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date,
                    gameRawgId: row.games.rawg_id
                )
            }
            
            isLoading = false
                        
            friendWantToPlay = await WantToPlayManager.shared.fetchFriendList(friendId: friend.userId)
            
        } catch {
            print("❌ Error loading friend data: \(error)")
        }
    }
}

// MARK: - Friend Want to Play Row
struct FriendWantToPlayRow: View {
    let game: WantToPlayGame
    let position: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            if let pos = position {
                Text("#\(pos)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(pos <= 3 ? Color.primaryBlue : Color.adaptiveGray)
                    .frame(width: 30, alignment: .leading)
            }
            
            AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondaryBackground)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .foregroundStyle(Color.adaptiveSilver)
                            .font(.system(size: 12))
                    )
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            Text(game.gameTitle)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .lineLimit(2)
            
            Spacer()
            
            BookmarkButton(
                gameId: game.gameId,
                gameTitle: game.gameTitle,
                gameCoverUrl: game.gameCoverUrl,
                source: "friend_wtp",
                sourceFriendId: game.userId
            )
        }
        .padding(12)
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Friend Want to Play Detail Sheet
struct FriendWantToPlayDetailSheet: View {
    let game: WantToPlayGame
    let friendName: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var gameDescription: String? = nil
    @State private var metacriticScore: Int? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: URL(string: game.gameCoverUrl ?? "")) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondaryBackground)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Color.adaptiveSilver)
                            )
                    }
                    .frame(width: 150, height: 200)
                    .cornerRadius(12)
                    .clipped()
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    
                    Text(game.gameTitle)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    if let position = game.sortPosition {
                        Text("\(friendName)'s Priority #\(position)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.primaryBlue)
                    } else {
                        Text("In \(friendName)'s backlog")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    if let score = metacriticScore, score > 0 {
                        HStack(spacing: 4) {
                            Text("Metacritic")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            Text("\(score)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(metacriticColor(score))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(metacriticColor(score).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    
                    Divider().padding(.horizontal, 40)
                    
                    if let desc = gameDescription, !desc.isEmpty {
                        GameDescriptionView(text: desc)
                            .padding(.horizontal, 24)
                    }
                    
                    // Bookmark CTA
                    BookmarkButton(
                        gameId: game.gameId,
                        gameTitle: game.gameTitle,
                        gameCoverUrl: game.gameCoverUrl,
                        source: "friend_wtp",
                        sourceFriendId: game.userId
                    )
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.adaptiveSilver)
                    }
                }
            }
            .task {
                await fetchGameDetails()
            }
        }
    }
    
    private func fetchGameDetails() async {
        do {
            struct GameInfo: Decodable {
                let rawg_id: Int
                let metacritic_score: Int?
                let description: String?
            }
            let infos: [GameInfo] = try await SupabaseManager.shared.client
                .from("games")
                .select("rawg_id, metacritic_score, description")
                .eq("rawg_id", value: game.gameId)
                .limit(1)
                .execute()
                .value
            
            guard let info = infos.first else { return }
            metacriticScore = info.metacritic_score

            if let cached = info.description, !cached.isEmpty {
                gameDescription = cached
                return
            }
            
            let details = try await RAWGService.shared.getGameDetails(id: info.rawg_id)
            gameDescription = details.gameDescriptionHtml ?? details.gameDescription

            if let desc = gameDescription, !desc.isEmpty {
                _ = try? await SupabaseManager.shared.client
                    .from("games")
                    .update(["description": desc])
                    .eq("rawg_id", value: info.rawg_id)
                    .execute()
            }
        } catch {
            print("⚠️ Could not fetch game details: \(error)")
        }
    }
    
    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return .success
        case 50...74: return .accentOrange
        default: return .error
        }
    }
}

// MARK: - Comparison Game Row
struct ComparisonGameRow: View {
    let game: UserGame
    let myRank: Int
    let theirRank: Int
    let friendName: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Cover art
            AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondaryBackground)
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.adaptiveDivider, lineWidth: 0.5)
            )
            
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                
                HStack(spacing: 16) {
                    Label("You: #\(myRank)", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.primaryBlue)
                    
                    Label("\(friendName): #\(theirRank)", systemImage: "person")
                        .font(.caption)
                        .foregroundColor(.accentOrange)
                }
            }
            
            Spacer()
            
            // Rank difference badge
            let diff = abs(myRank - theirRank)
            if diff > 0 {
                Text(diff == 0 ? "=" : "±\(diff)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(diff >= 10 ? Color.accentOrange : Color.adaptiveGray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(diff >= 10 ? Color.accentOrange.opacity(0.15) : Color.secondaryBackground)
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.cardBackground) 
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Friend Game Row
struct FriendGameRow: View {
    let game: UserGame
    let myRank: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank number
            Text("#\(game.rankPosition)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(rankColor)
                .frame(width: 36, alignment: .leading)
            
            // Cover art
            AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondaryBackground)
            }
            .frame(width: 50, height: 67)
                .cornerRadius(6)
                .clipped()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.adaptiveDivider, lineWidth: 0.5)
                )
                
                // Game info
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.gameTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(1)
                
                if let myRank = myRank {
                    Text("You: #\(myRank)")
                        .font(.caption)
                        .foregroundColor(.primaryBlue)
                } else {
                    Text("Not in your list")
                        .font(.caption)
                        .foregroundStyle(Color.adaptiveGray)
                }
            }
            
            Spacer()
            
            // Bookmark (only if not in my list)
            if myRank == nil {
                BookmarkButton(
                    gameId: game.gameId,
                    gameTitle: game.gameTitle,
                    gameCoverUrl: game.gameCoverURL,
                    source: "profile",
                    sourceFriendId: game.userId
                )
            }
        }
        .padding(.vertical, 8)
    }
    
    private var rankColor: Color {
        switch game.rankPosition {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        case 4...10: return .teal
        default: return .adaptiveGray
        }
    }
}

// MARK: - Compare Lists View
struct CompareListsView: View {
    let myGames: [UserGame]
    let friendGames: [UserGame]
    let friendName: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // My list
                    VStack(spacing: 0) {
                        Text("You")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primaryBlue)
                            .padding(.vertical, 12)
                        
                        ForEach(myGames.sorted { $0.rankPosition < $1.rankPosition }) { game in
                            SideBySideGameCell(
                                game: game,
                                isShared: friendGames.contains { $0.gameId == game.gameId }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(Color.secondaryBackground)
                        .frame(width: 1)
                    
                    // Friend's list
                    VStack(spacing: 0) {
                        Text(friendName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.accentOrange)
                            .padding(.vertical, 12)
                        
                        ForEach(friendGames.sorted { $0.rankPosition < $1.rankPosition }) { game in
                            SideBySideGameCell(
                                game: game,
                                isShared: myGames.contains { $0.gameId == game.gameId }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Compare Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
    }
}

// MARK: - Side By Side Game Cell
struct SideBySideGameCell: View {
    let game: UserGame
    let isShared: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Text("#\(game.rankPosition)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .frame(width: 24)
            
            AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.secondaryBackground)
            }
            .frame(width: 30, height: 40)
            .cornerRadius(4)
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isShared ? Color.teal : Color.clear, lineWidth: 2)
            )
            
            Text(game.gameTitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .lineLimit(2)
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isShared ? Color.teal.opacity(0.1) : Color.clear)
    }
}

#Preview {
    FriendsView()
}
