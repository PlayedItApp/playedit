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
                        avatarURL: userInfo.avatar_url
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
struct Friend: Identifiable, Hashable {
    let id: String
    let friendshipId: String
    let username: String
    let userId: String
    let avatarURL: String?
    
    init(id: String, friendshipId: String, username: String, userId: String, avatarURL: String? = nil) {
        self.id = id
        self.friendshipId = friendshipId
        self.username = username
        self.userId = userId
        self.avatarURL = avatarURL
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
        
        return sharedGames.filter { $0.theirs.rankPosition <= theirThreshold && $0.mine.rankPosition > myBottomHalf }
            .sorted { $0.theirs.rankPosition < $1.theirs.rankPosition }
    }
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                    .padding(.top, 100)
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
                    
                    // Friend's Full List
                    friendListSection
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
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
                .foregroundColor(.slate)
            
            Text("\(friendGames.count) games ranked")
                .font(.subheadline)
                .foregroundColor(.grayText)
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
                    .foregroundColor(.grayText)
                
                Button {
                    showMatchInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.grayText)
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
                .foregroundColor(.slate)
                .multilineTextAlignment(.center)
            
            // Shared games count
            Text("Based on \(sharedGames.count) \(sharedGames.count == 1 ? "game" : "games") you've both ranked")
                .font(.caption)
                .foregroundColor(.grayText)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
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
            var sumDSquared = 0
            for pair in sharedGames {
                let d = pair.mine.rankPosition - pair.theirs.rankPosition
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
                .foregroundColor(.silver)
            
            Text("No shared games yet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.slate)
            
            Text("Rank some games \(friend.username) has played to see your taste match!")
                .font(.subheadline)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.lightGray)
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
                    .foregroundColor(.slate)
                Text("\(friend.username) loved these, you... didn't")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.slate.opacity(0.08))
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
    
    // MARK: - Friend's List Section
    private var friendListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(friend.username)'s Rankings")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.grayText)
                .padding(.horizontal, 16)
            
            if friendGames.isEmpty {
                Text("\(friend.username) hasn't ranked any games yet. Peer pressure them? 😄")
                    .font(.subheadline)
                    .foregroundColor(.grayText)
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
    
    // MARK: - Load Data
    private func loadData() async {
        guard let userId = supabase.currentUser?.id else {
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
                }
            }
            
            // Fetch friend's games with join
            let friendRows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: friend.userId)
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
                    gameReleaseDate: row.games.release_date
                )
            }
            
            // Fetch my games with join
            let myRows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: userId.uuidString)
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
                    gameReleaseDate: row.games.release_date
                )
            }
            
            isLoading = false
            
        } catch {
            print("❌ Error loading friend data: \(error)")
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
                    .fill(Color.lightGray)
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info
            VStack(alignment: .leading, spacing: 4) {
                Text(game.gameTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
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
                    .foregroundColor(diff >= 10 ? .accentOrange : .grayText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(diff >= 10 ? Color.accentOrange.opacity(0.15) : Color.lightGray)
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Color.white)
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
                    .fill(Color.lightGray)
            }
            .frame(width: 50, height: 67)
            .cornerRadius(6)
            .clipped()
            
            // Game info
            VStack(alignment: .leading, spacing: 2) {
                Text(game.gameTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.slate)
                    .lineLimit(1)
                
                if let myRank = myRank {
                    Text("You: #\(myRank)")
                        .font(.caption)
                        .foregroundColor(.primaryBlue)
                } else {
                    Text("Not in your list")
                        .font(.caption)
                        .foregroundColor(.grayText)
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
        default: return .grayText
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
                        .fill(Color.lightGray)
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
                .foregroundColor(.grayText)
                .frame(width: 24)
            
            AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.lightGray)
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
                .foregroundColor(.slate)
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
