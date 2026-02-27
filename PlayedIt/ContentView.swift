import SwiftUI
import Supabase
import Combine

struct ContentView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var isCheckingAuth = true
    @State private var needsOnboarding = false
    @State private var isOnboardingComplete = false
    @State private var showProductTour = false
    @State private var tourAnchors: [String: CGRect] = [:]
    @State private var forceProfile = false
    
    var body: some View {
        Group {
            if isCheckingAuth {
                SplashView()
            } else if supabase.isAuthenticated {
                if needsOnboarding && !isOnboardingComplete {
                    OnboardingQuizView(isOnboardingComplete: $isOnboardingComplete, onSkip: {
                        if let userId = supabase.currentUser?.id {
                            UserDefaults.standard.set(true, forKey: "onboarding_complete_\(userId)")
                        }
                        needsOnboarding = false
                        forceProfile = true
                    })
                } else {
                    MainTabView(forceProfileTab: showProductTour || forceProfile)
                    .overlay(
                        Group {
                            if showProductTour {
                                ProductTourOverlay(anchors: tourAnchors, onDismiss: {
                                    showProductTour = false
                                })
                            }
                        }
                    )
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: isCheckingAuth)
        .task {
            await supabase.checkSession()
            isCheckingAuth = false
            
            if supabase.isAuthenticated {
                await checkOnboardingStatus()
            }
        }
        .onChange(of: supabase.isAuthenticated) { _, isAuth in
            if isAuth {
                Task { await checkOnboardingStatus() }
            }
        }
        .onChange(of: isOnboardingComplete) { _, complete in
            if complete {
                if let userId = supabase.currentUser?.id {
                    UserDefaults.standard.set(true, forKey: "onboarding_complete_\(userId)")
                }
                needsOnboarding = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showProductTour = true
                }
            }
        }
    }
    
private func checkOnboardingStatus() async {
    guard let userId = supabase.currentUser?.id else {
        debugLog("⚠️ checkOnboardingStatus: no current user")
        return
    }
    
    if UserDefaults.standard.bool(forKey: "onboarding_complete_\(userId)") {
        needsOnboarding = false
        return
    }
    debugLog("🔍 checkOnboardingStatus: checking for user \(userId)")
        
        do {
            let count: Int = try await supabase.client
                .from("user_games")
                .select("*", head: true, count: .exact)
                .eq("user_id", value: userId.uuidString)
                .execute()
                .count ?? 0
            
            needsOnboarding = count == 0
            //needsOnboarding = true // TEMP: force onboarding
        } catch {
            debugLog("❌ Error checking onboarding status: \(error)")
            needsOnboarding = true
        }
    }
}

// MARK: - Splash View
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            
            HStack(spacing: 0) {
                Text("played")
                    .font(Font.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    Text("it")
                        .font(Font.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.accentOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cardBackground) 
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    var forceProfileTab: Bool = false
    @AppStorage("startTab") private var startTab = 0
    @State private var selectedTab: Int = 0
    @State private var pendingRequestCount = 0
    @State private var unreadNotificationCount = 0
    @State private var showWhatsNew = false
    @ObservedObject var supabase = SupabaseManager.shared
    @AppStorage("profileNudgeDismissCount") private var profileNudgeDismissCount = 0
    @State private var userAvatarURL: String?
    @State private var userUsername: String = ""
    @State private var profileNudgeVisible = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(unreadNotificationCount: $unreadNotificationCount)
                .tabItem {
                    Image(systemName: "newspaper")
                    Text("Feed")
                }
                .tag(0)
                .badge(unreadNotificationCount > 0 ? unreadNotificationCount : 0)
            
            FriendsView()
                .tabItem {
                    Image(systemName: "person.2")
                    Text("Friends")
                }
                .tag(1)
                .badge(pendingRequestCount > 0 ? pendingRequestCount : 0)

            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
                .tag(2)
        }
        .tint(.primaryBlue)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .onAppear {
            if WhatsNewManager.shouldShow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showWhatsNew = true
                }
            }
        }
        .onAppear {
            debugLog("🎯 MainTabView onAppear: forceProfileTab=\(forceProfileTab), startTab=\(startTab)")
            selectedTab = forceProfileTab ? 2 : startTab
        }
        .onChange(of: forceProfileTab) { _, force in
            if force {
                selectedTab = 2
            }
        }
        .task {
            await fetchPendingCount()
            await fetchUnreadNotificationCount()
            await WantToPlayManager.shared.refreshMyIds()
            if let userId = supabase.currentUser?.id {
                    await GameLogView.backfillUsedPlatformsIfNeeded(for: userId, client: supabase.client)
                }
                await fetchProfileForNudge()
            }
        .overlay(alignment: .top) {
            if profileNudgeVisible {
                HStack(spacing: 6) {
                    Button {
                        withAnimation {
                            selectedTab = 2
                            profileNudgeVisible = false
                        }
                        NotificationCenter.default.post(name: .profileNudgeTapped, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentOrange)
                            
                            Text(profileNudgeText)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) {
                            profileNudgeDismissCount += 1
                            profileNudgeVisible = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.primaryBlue))
                .padding(.top, 54)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await fetchUnreadNotificationCount()
            }
        }
    }
    
    private var shouldShowProfileNudge: Bool {
        guard profileNudgeDismissCount < 3 else { return false }
        let needsAvatar = userAvatarURL == nil || userAvatarURL?.isEmpty == true
        let needsUsername = userUsername.isEmpty || userUsername.contains("@") || userUsername.hasPrefix("user_")
        return needsAvatar || needsUsername
    }
     
    private var profileNudgeText: String {
        let needsAvatar = userAvatarURL == nil || userAvatarURL?.isEmpty == true
        let needsUsername = userUsername.isEmpty || userUsername.contains("@") || userUsername.hasPrefix("user_")
        if needsAvatar && needsUsername {
            return "Add a pic & username!"
        } else if needsAvatar {
            return "Add a profile pic!"
        } else {
            return "Set a username so friends can find you!"
        }
    }

    private func fetchProfileForNudge() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct ProfileCheck: Decodable {
                let username: String?
                let avatar_url: String?
            }
            
            let profile: ProfileCheck = try await supabase.client
                .from("users")
                .select("username, avatar_url")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            userUsername = profile.username ?? ""
            userAvatarURL = profile.avatar_url
            
            withAnimation(.easeOut(duration: 0.3).delay(1.0)) {
                profileNudgeVisible = shouldShowProfileNudge
            }
        } catch {
            debugLog("❌ Error fetching profile for nudge: \(error)")
        }
    }
    
    private func fetchPendingCount() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct FriendshipRow: Decodable {
                let id: String
                let friend_id: String
                let status: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("id, friend_id, status")
                .eq("status", value: "pending")
                .execute()
                .value
            
            pendingRequestCount = friendships.filter {
                $0.friend_id.lowercased() == userId.uuidString.lowercased()
            }.count
            
        } catch {
            debugLog("❌ Error fetching pending count: \(error)")
        }
    }
    
    private func fetchUnreadNotificationCount() async {
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
                debugLog("🔔 MainTab unread count: \(count) for user: \(userId.uuidString)")
                
            } catch {
            debugLog("❌ Error fetching notification count: \(error)")
        }
    }
}

// MARK: - Ranked Game Row
struct RankedGameRow: View {
    let rank: Int
    let game: UserGame
    var onUpdate: (() async -> Void)? = nil
    @State private var showDetail = false
    
    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(spacing: 12) {
                Text("\(rank)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(rankColor)
                    .frame(width: 32)
                
                CachedAsyncImage(url: game.gameCoverURL) {
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
                    Text(game.gameTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .lineLimit(2)
                    
                    if let year = game.gameReleaseDate?.prefix(4) {
                        Text(String(year))
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    if !game.platformPlayed.isEmpty {
                        Text(game.platformPlayed.sorted().joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.adaptiveGray)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
            .background(Color.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.adaptiveDivider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail, onDismiss: {
            Task { await onUpdate?() }
        }) {
            GameDetailSheet(game: game, rank: rank, onRankUpdated: {
                await onUpdate?()
            })
        }
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        default: return .adaptiveGray
        }
    }
}

// MARK: - Game Detail Sheet
struct GameDetailSheet: View {
    let game: UserGame
    let rank: Int
    var onRankUpdated: (() async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var showComparison = false
    @State private var existingUserGames: [UserGame] = []
    @State private var isLoadingReRank = false
    @State private var oldRank: Int? = nil
    @State private var showRemoveConfirm = false
    @State private var isRemoving = false
    @State private var isEditingNotes = false
    @State private var editedNotes: String = ""
    @State private var isSavingNotes = false
    @State private var isEditingPlatforms = false
    @State private var editedPlatforms: Set<String> = []
    @State private var customPlatform: String = ""
    @State private var isSavingPlatforms = false
    @State private var showAllPlatformsSheet = false
    @State private var displayedNotes: String? = nil
    @State private var displayedPlatforms: [String] = []
    @State private var hasInitialized = false
    @State private var notesError: String?
    @State private var gameDescription: String? = nil
    @State private var metacriticScore: Int? = nil
    
    
    private var quickPlatforms: [String] {
        guard let userId = supabase.currentUser?.id else { return GameLogView.popularPlatforms }
        let used = GameLogView.usedPlatforms(for: userId)
        if used.isEmpty {
            return GameLogView.popularPlatforms
        }
        return GameLogView.allPlatforms.filter { used.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GameInfoHeroView(
                        title: game.gameTitle,
                        coverURL: game.gameCoverURL,
                        releaseDate: game.gameReleaseDate,
                        metacriticScore: metacriticScore,
                        gameDescription: gameDescription
                    )
                    
                    // Rank badge
                    Text("Ranked #\(rank)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(rank == 1 ? .accentOrange : .primaryBlue)
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "gamecontroller")
                                        .font(.system(size: 16))
                                        .foregroundColor(.primaryBlue)
                                        .frame(width: 24)
                                    Text("Played on")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                }
                                
                                Spacer()
                                
                                if !isEditingPlatforms {
                                    Button {
                                        editedPlatforms = Set(displayedPlatforms)
                                        isEditingPlatforms = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: displayedPlatforms.isEmpty ? "plus" : "pencil")
                                                .font(.system(size: 11))
                                            Text(displayedPlatforms.isEmpty ? "Add" : "Edit")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                        .foregroundColor(.primaryBlue)
                                    }
                                }
                            }
                            
                            if isEditingPlatforms {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 10) {
                                    ForEach(quickPlatforms, id: \.self) { platform in
                                        PlatformButton(
                                            platform: platform,
                                            isSelected: editedPlatforms.contains(platform)
                                        ) {
                                            if editedPlatforms.contains(platform) {
                                                editedPlatforms.remove(platform)
                                            } else {
                                                editedPlatforms.insert(platform)
                                            }
                                        }
                                    }
                                }
                                
                                // Show any selected platforms not in quickPlatforms
                                let extraSelections = editedPlatforms.filter { !quickPlatforms.contains($0) }
                                if !extraSelections.isEmpty {
                                    FlowLayout(spacing: 8) {
                                        ForEach(Array(extraSelections).sorted(), id: \.self) { platform in
                                            HStack(spacing: 4) {
                                                Text(platform)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                Button {
                                                    editedPlatforms.remove(platform)
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 12))
                                                }
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.primaryBlue)
                                            .cornerRadius(16)
                                        }
                                    }
                                }
                                
                                Button {
                                    showAllPlatformsSheet = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle")
                                            .font(.system(size: 14))
                                        Text("More Platforms")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                    }
                                    .foregroundColor(.primaryBlue)
                                    .padding(.vertical, 4)
                                }
                                
                                HStack(spacing: 12) {
                                    Button {
                                        isEditingPlatforms = false
                                        customPlatform = ""
                                    } label: {
                                        Text("Cancel")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.adaptiveGray)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    
                                    Button {
                                        Task { await savePlatforms() }
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isSavingPlatforms {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else {
                                                Text("Save Platforms")
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.primaryBlue)
                                        .cornerRadius(8)
                                    }
                                    .disabled(isSavingPlatforms)
                                }
                            } else if !displayedPlatforms.isEmpty {
                                Text(displayedPlatforms.joined(separator: ", "))
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                                    .padding(.leading, 36)
                            } else {
                                Text("No platforms added. Tap Add to set them!")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                                    .italic()
                                    .padding(.leading, 36)
                            }
                        }
                        
                        // Notes section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 12) {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 16))
                                        .foregroundColor(.primaryBlue)
                                        .frame(width: 24)
                                    Text("Notes")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                }
                                
                                Spacer()
                                
                                if !isEditingNotes {
                                    Button {
                                        editedNotes = displayedNotes ?? ""
                                        isEditingNotes = true
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: displayedNotes?.isEmpty ?? true ? "plus" : "pencil")
                                                .font(.system(size: 11))
                                            Text(displayedNotes?.isEmpty ?? true ? "Add" : "Edit")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                        }
                                        .foregroundColor(.primaryBlue)
                                    }
                                }
                            }
                            
                            if isEditingNotes {
                                TextEditor(text: $editedNotes)
                                    .frame(minHeight: 100)
                                    .padding(12)
                                    .background(Color.secondaryBackground)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.adaptiveSilver, lineWidth: 1)
                                    )
                                    .overlay(
                                        Group {
                                            if editedNotes.isEmpty {
                                                Text("Favorite moments? Hot takes? (optional)")
                                                    .foregroundStyle(Color.adaptiveGray)
                                                    .padding(.leading, 16)
                                                    .padding(.top, 20)
                                            }
                                        },
                                        alignment: .topLeading
                                    )
                                
                                SpoilerHint()
                                                                
                                if let notesError = notesError {
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .font(.caption)
                                            .foregroundColor(.error)
                                        Text(notesError)
                                            .font(.caption)
                                            .foregroundColor(.error)
                                    }
                                }
                                
                                HStack(spacing: 12) {
                                    Button {
                                        isEditingNotes = false
                                        editedNotes = ""
                                    } label: {
                                        Text("Cancel")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color.adaptiveGray)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                    }
                                    
                                    Button {
                                        Task { await saveNotes() }
                                    } label: {
                                        HStack(spacing: 4) {
                                            if isSavingNotes {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else {
                                                Text("Save Notes")
                                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            }
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.primaryBlue)
                                        .cornerRadius(8)
                                    }
                                    .disabled(isSavingNotes)
                                }
                            } else if let notes = displayedNotes, !notes.isEmpty {
                                SpoilerTextView(notes, font: .system(size: 16, design: .rounded), color: .slate)
                                    .padding(.leading, 36)
                            } else {
                                Text("No notes yet. Tap Add to write a review!")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundStyle(Color.adaptiveGray)
                                    .italic()
                                    .padding(.leading, 36)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Re-rank button
                    Button {
                        Task {
                            await startReRank()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingReRank {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                            } else {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 13))
                                Text("Re-rank")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                        }
                        .foregroundColor(.primaryBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.primaryBlue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(isLoadingReRank)
                    .padding(.top, 8)
                    
                    // Remove game button
                    Button {
                        showRemoveConfirm = true
                    } label: {
                        HStack(spacing: 6) {
                            if isRemoving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .red))
                            } else {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
                                Text("Remove from List")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                            }
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .disabled(isRemoving)
                    .confirmationDialog(
                        "Remove \(game.gameTitle)?",
                        isPresented: $showRemoveConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Remove from Rankings", role: .destructive) {
                            Task {
                                await removeGame()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove the game from your rankings, feed, and all reactions. This can't be undone.")
                    }
                    
                    Spacer()
                }
                .padding(.top, 24)
            }
            .onAppear {
                if !hasInitialized {
                    displayedNotes = game.notes
                    displayedPlatforms = game.platformPlayed.sorted()
                    hasInitialized = true
                }
            }
            .task {
                do {
                    struct GameInfo: Decodable {
                        let rawg_id: Int
                        let description: String?
                        let metacritic_score: Int?
                    }
                    // Try by rawg_id first, fall back to local id
                    var results: [GameInfo] = []
                    if let rawgId = game.gameRawgId {
                        results = try await SupabaseManager.shared.client
                            .from("games")
                            .select("rawg_id, description, metacritic_score")
                            .eq("rawg_id", value: rawgId)
                            .limit(1)
                            .execute()
                            .value
                    }
                    if results.isEmpty {
                        results = try await SupabaseManager.shared.client
                            .from("games")
                            .select("rawg_id, description, metacritic_score")
                            .eq("id", value: game.gameId)
                            .limit(1)
                            .execute()
                            .value
                    }
                    
                    guard let result = results.first else {
                        debugLog("⚠️ No games row found for gameId \(game.gameId)")
                        return
                    }
                    
                    metacriticScore = result.metacritic_score
                    
                    if let cached = result.description, !cached.isEmpty {
                        gameDescription = cached
                        return
                    }
                    
                    let details = try await RAWGService.shared.getGameDetails(id: result.rawg_id)
                    gameDescription = details.gameDescription ?? details.gameDescriptionHtml
                    
                    if let desc = gameDescription, !desc.isEmpty {
                        _ = try? await SupabaseManager.shared.client
                            .from("games")
                            .update(["description": desc])
                            .eq("rawg_id", value: result.rawg_id)
                            .execute()
                    }
                } catch {
                    debugLog("⚠️ Could not fetch game description: \(error)")
                }
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
            .sheet(isPresented: $showAllPlatformsSheet) {
                PlatformPickerSheet(selectedPlatforms: $editedPlatforms)
            }
            .sheet(isPresented: $showComparison) {
                ComparisonView(
                    newGame: game.toGame(),
                    existingGames: existingUserGames,
                    onComplete: { newPosition in
                        Task {
                            await saveReRankedGame(newPosition: newPosition)
                            await onRankUpdated?()
                            dismiss()
                        }
                    }
                )
                .interactiveDismissDisabled()
            }
        }
    }
    
    // MARK: - Start Re-Rank
    private func startReRank() async {
        guard let userId = supabase.currentUser?.id else { return }
        isLoadingReRank = true
        oldRank = rank
        
        do {
            // Fetch all user's games EXCEPT this one, for comparisons
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
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id)")
                .eq("user_id", value: userId.uuidString)
                .neq("game_id", value: game.gameId)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            existingUserGames = rows.map { row in
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
            
            isLoadingReRank = false
            showComparison = true
            
        } catch {
            debugLog("❌ Error loading games for re-rank: \(error)")
            isLoadingReRank = false
        }
    }
    
    // MARK: - Save Re-Ranked Game
    private func saveReRankedGame(newPosition: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            let canonicalId = await RAWGService.shared.getParentGameId(for: game.gameRawgId ?? game.gameId) ?? (game.gameRawgId ?? game.gameId)
            
            try await supabase.client
                .rpc("rerank_game", params: [
                    "p_user_game_id": AnyJSON.string(game.id),
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_old_rank": AnyJSON.integer(rank),
                    "p_new_rank": AnyJSON.integer(newPosition),
                    "p_game_id": AnyJSON.integer(game.gameId),
                    "p_platform_played": AnyJSON.array(game.platformPlayed.map { AnyJSON.string($0) }),
                    "p_notes": AnyJSON.string(game.notes ?? ""),
                    "p_canonical_game_id": AnyJSON.integer(canonicalId)
                ])
                .execute()
            
            debugLog("✅ Re-ranked from #\(rank) → #\(newPosition)")
            
        } catch {
            debugLog("❌ Error saving re-ranked game: \(error)")
        }
    }

// MARK: - Remove Game
    private func removeGame() async {
        guard let userId = supabase.currentUser?.id else { return }
        isRemoving = true
        
        do {
            try await supabase.client
                .rpc("remove_game_and_rerank", params: [
                    "p_user_game_id": AnyJSON.string(game.id),
                    "p_user_id": AnyJSON.string(userId.uuidString)
                ])
                .execute()
            
            debugLog("✅ Removed \(game.gameTitle) from rankings")
            await onRankUpdated?()
            dismiss()
            
        } catch {
            debugLog("❌ Error removing game: \(error)")
            isRemoving = false
        }
    }
    
    // MARK: - Save Platforms
        private func savePlatforms() async {
            isSavingPlatforms = true
            
            do {
                try await supabase.client
                    .from("user_games")
                    .update(["platform_played": Array(editedPlatforms)])
                    .eq("id", value: game.id)
                    .execute()
                
                debugLog("✅ Platforms saved")
                displayedPlatforms = Array(editedPlatforms).sorted()
                isEditingPlatforms = false
                customPlatform = ""
                
                if let userId = supabase.currentUser?.id, !editedPlatforms.isEmpty {
                    GameLogView.saveUsedPlatforms(editedPlatforms, for: userId)
                }
                
            } catch {
                debugLog("❌ Error saving platforms: \(error)")
            }
            
            isSavingPlatforms = false
        }
    
    // MARK: - Save Notes
    private func saveNotes() async {
        isSavingNotes = true
        notesError = nil
        
        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !trimmed.isEmpty {
            let result = await ModerationService.shared.moderateGameNote(trimmed)
            if !result.allowed {
                notesError = result.reason
                isSavingNotes = false
                return
            }
        }
        
        do {
            try await supabase.client
                .from("user_games")
                .update(["notes": trimmed])
                .eq("id", value: game.id)
               
                .execute()
            
            debugLog("✅ Notes saved")
            displayedNotes = trimmed
            isEditingNotes = false
            
        } catch {
            debugLog("❌ Error saving notes: \(error)")
        }
        
        isSavingNotes = false
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.primaryBlue)
                    .frame(width: 24)
                
                Text(label)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            
            Text(value)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .padding(.leading, 36) // 24 (icon frame) + 12 (spacing)
        }
    }
}

extension Notification.Name {
    static let profileNudgeTapped = Notification.Name("profileNudgeTapped")
}

#Preview {
    ContentView()
}
