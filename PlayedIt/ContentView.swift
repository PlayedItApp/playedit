import SwiftUI
import Supabase
import Combine
import UserNotifications
import Network

struct iPadReadableWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) var sizeClass
    
    func body(content: Content) -> some View {
        if sizeClass == .regular {
            content
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func iPadReadableWidth() -> some View {
        modifier(iPadReadableWidthModifier())
    }
}

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
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
            
            if supabase.isAuthenticated {
                await checkOnboardingStatus()
                // Small delay lets the first view's images start loading
                // before we dismiss the splash, so users don't see a flash of placeholders
                await FeedPreloader.shared.preload()
            }
            
            isCheckingAuth = false
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
    @State private var isPulsing = false
    var body: some View {
        VStack(spacing: 16) {
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .scaleEffect(isPulsing ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
                .onAppear { isPulsing = true }
            
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
    @AppStorage("hideNotifications") private var hideNotifications = false
    @Environment(\.scenePhase) var scenePhase
    @State private var selectedTab: Int = 0
    @State private var pendingRequestCount = 0
    @State private var unreadNotificationCount = 0
    @State private var showWhatsNew = false
    @EnvironmentObject var supabase: SupabaseManager
    @AppStorage("profileNudgeDismissCount") private var profileNudgeDismissCount = 0
    @State private var userAvatarURL: String?
    @State private var userUsername: String = ""
    @State private var profileNudgeVisible = false
    @State private var isOffline = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FeedView(unreadNotificationCount: $unreadNotificationCount)
                .tabItem {
                    Image(systemName: "newspaper")
                    Text("Feed")
                }
                .tag(0)
                .badge(!hideNotifications && unreadNotificationCount > 0 ? unreadNotificationCount : 0)
            
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
            PushNotificationManager.shared.requestPermissionAndRegister()
            await fetchPendingCount()
            if !hideNotifications {
                await fetchUnreadNotificationCount()
            }
            await WantToPlayManager.shared.refreshMyIds()
            if let userId = supabase.currentUser?.id {
                    await GameLogView.backfillUsedPlatformsIfNeeded(for: userId, client: supabase.client)
                }
                await fetchProfileForNudge()
            }
        .overlay(alignment: .top) {
            if isOffline {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("You're offline")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color.red.opacity(0.85))
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: isOffline)
            }
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
        .task(id: "network-monitor") {
            let monitor = NWPathMonitor()
            let stream = AsyncStream<Bool> { continuation in
                monitor.pathUpdateHandler = { path in
                    continuation.yield(path.status != .satisfied)
                }
                monitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
            }
            for await offline in stream {
                await MainActor.run { isOffline = offline }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase == .inactive {
                Task {
                    await supabase.validateSession()
                    await fetchPendingCount()
                    if !hideNotifications {
                        await fetchUnreadNotificationCount()
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            guard !hideNotifications else { return }
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
                try? await UNUserNotificationCenter.current().setBadgeCount(count)
                
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
                    GameArtworkPlaceholder(genre: nil, size: .medium)
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
                        Text(game.platformPlayed.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.joined(separator: " • "))
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
    @EnvironmentObject var supabase: SupabaseManager
    
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
    @State private var showGameDataReport = false
    @State private var metacriticScore: Int? = nil
    @State private var curatedGenres: [String]? = nil
    @State private var curatedTags: [String]? = nil
    @State private var curatedPlatforms: [String]? = nil
    @State private var curatedReleaseYear: Int? = nil
    @State private var totalRankedGames: Int = 0
    @State private var isSharing = false
    @State private var friendRankings: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
    @State private var isLoadingFriendRankings = true
    @State private var computedPredictedRange: (lower: Int, upper: Int)? = nil
    
    
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
                        releaseDate: curatedReleaseYear.map { String($0) } ?? game.gameReleaseDate,
                        metacriticScore: metacriticScore,
                        gameDescription: gameDescription,
                        curatedGenres: curatedGenres,
                        curatedTags: curatedTags,
                        curatedPlatforms: curatedPlatforms
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
                    
                    // Friend rankings
                    if !friendRankings.isEmpty || isLoadingFriendRankings {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How friends ranked this")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            if isLoadingFriendRankings {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(Array(friendRankings.enumerated()), id: \.offset) { index, ranking in
                                        HStack(spacing: 12) {
                                            if let avatarURL = ranking.avatarURL, let url = URL(string: avatarURL) {
                                                AsyncImage(url: url) { image in
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } placeholder: {
                                                    friendInitialsCircle(ranking.username, size: 32)
                                                }
                                                .frame(width: 32, height: 32)
                                                .clipShape(Circle())
                                            } else {
                                                friendInitialsCircle(ranking.username, size: 32)
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(ranking.username)
                                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Color.adaptiveSlate)
                                                
                                                if ranking.username != "You",
                                                   friendRankings.filter({ $0.username != "You" }).count >= 2,
                                                   ranking.tasteMatch == friendRankings.filter({ $0.username != "You" }).map({ $0.tasteMatch }).max(),
                                                   ranking.tasteMatch >= 50 {
                                                    Text("Closest taste · \(ranking.tasteMatch)%")
                                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                                        .foregroundColor(.teal)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            Text("#\(ranking.rank)")
                                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                                .foregroundColor(ranking.rank <= 3 ? .accentOrange : .primaryBlue)
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        
                                        if index < friendRankings.count - 1 {
                                            Divider()
                                                .padding(.horizontal, 16)
                                        }
                                    }
                                }
                                .background(Color.cardBackground)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
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
                    
                    // Report bad game data
                    Button {
                        showGameDataReport = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 13))
                            Text("Report incorrect game info")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.adaptiveGray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.adaptiveGray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
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
                    .iPadReadableWidth()
                }
                .onAppear {
                    if !hasInitialized {
                    displayedNotes = game.notes
                    displayedPlatforms = game.platformPlayed.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    hasInitialized = true
                }
            }
            .task {
                // Instantly apply cached metadata if available
                if let cached = GameMetadataCache.shared.get(gameId: game.gameId) {
                    metacriticScore = cached.metacriticScore
                    gameDescription = cached.description
                    curatedGenres = cached.curatedGenres
                    curatedTags = cached.curatedTags
                    curatedPlatforms = cached.curatedPlatforms
                    curatedReleaseYear = cached.curatedReleaseYear
                }
                
                // Fetch total ranked game count for share card
                if let userId = supabase.currentUser?.id {
                    let count: Int = (try? await supabase.client
                        .from("user_games")
                        .select("*", head: true, count: .exact)
                        .eq("user_id", value: userId.uuidString)
                        .not("rank_position", operator: .is, value: "null")
                        .execute()
                        .count) ?? 0
                    totalRankedGames = count
                }
                
                await fetchFriendRankingsForSheet()
                
                // Skip DB+RAWG if we already have description from cache
                guard gameDescription == nil else { return }
                
                do {
                    struct GameInfo: Decodable {
                        let rawg_id: Int
                        let description: String?
                        let curated_description: String?
                        let metacritic_score: Int?
                        let curated_genres: [String]?
                        let curated_tags: [String]?
                        let curated_platforms: [String]?
                        let curated_release_year: Int?
                    }
                    var results: [GameInfo] = []
                    if let rawgId = game.gameRawgId {
                        results = try await SupabaseManager.shared.client
                            .from("games")
                            .select("rawg_id, description, curated_description, metacritic_score, curated_genres, curated_tags, curated_platforms, curated_release_year")
                            .eq("rawg_id", value: rawgId)
                            .limit(1)
                            .execute()
                            .value
                    }
                    if results.isEmpty {
                        results = try await SupabaseManager.shared.client
                            .from("games")
                            .select("rawg_id, description, curated_description, metacritic_score, curated_genres, curated_tags, curated_platforms, curated_release_year")
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
                    curatedGenres = result.curated_genres
                    curatedTags = result.curated_tags
                    curatedPlatforms = result.curated_platforms
                    curatedReleaseYear = result.curated_release_year
                    
                    if let desc = result.curated_description ?? result.description, !desc.isEmpty {
                        gameDescription = desc
                        GameMetadataCache.shared.set(gameId: game.gameId, description: desc, metacriticScore: result.metacritic_score, releaseDate: game.gameReleaseDate, curatedGenres: result.curated_genres, curatedTags: result.curated_tags, curatedPlatforms: result.curated_platforms, curatedReleaseYear: result.curated_release_year)
                        return
                    }
                    
                    let details = try await RAWGService.shared.getGameDetails(id: result.rawg_id)
                    gameDescription = details.gameDescription ?? details.gameDescriptionHtml
                    
                    if let desc = gameDescription, !desc.isEmpty {
                        GameMetadataCache.shared.set(gameId: game.gameId, description: desc, metacriticScore: result.metacritic_score, releaseDate: game.gameReleaseDate, curatedGenres: result.curated_genres, curatedTags: result.curated_tags, curatedPlatforms: result.curated_platforms, curatedReleaseYear: result.curated_release_year)
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.adaptiveSilver)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSharing = true
                        Task {
                            await GameShareService.shared.shareGame(
                                gameTitle: game.gameTitle,
                                coverURL: game.gameCoverURL,
                                rankPosition: rank,
                                platforms: displayedPlatforms,
                                totalGames: totalRankedGames,
                                gameId: game.gameRawgId ?? game.gameId
                            )
                            isSharing = false
                        }
                    } label: {
                        if isSharing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .adaptiveSilver))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.primaryBlue)
                        }
                    }
                    .disabled(isSharing)
                }
            }
            .sheet(isPresented: $showGameDataReport) {
                ReportGameDataView(
                    gameId: game.gameId,
                    rawgId: game.gameRawgId ?? game.gameId,
                    gameTitle: game.gameTitle
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .sheet(isPresented: $showAllPlatformsSheet) {
                PlatformPickerSheet(selectedPlatforms: $editedPlatforms)
            }
            .sheet(isPresented: $showComparison) {
                ComparisonView(
                    newGame: game.toGame(),
                    existingGames: existingUserGames,
                    predictedPosition: computedPredictedRange.map { ($0.lower + $0.upper) / 2 },
                    predictedRange: computedPredictedRange,
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
    
    private func quickTasteMatch(myGames: [(canonicalId: Int, rank: Int)], theirGames: [(canonicalId: Int, rank: Int)]) -> Int {
            let theirDict = Dictionary(theirGames.map { ($0.canonicalId, $0.rank) }, uniquingKeysWith: { first, _ in first })
            var shared: [(myRank: Int, theirRank: Int)] = []
            for myGame in myGames {
                if let theirRank = theirDict[myGame.canonicalId] {
                    shared.append((myRank: myGame.rank, theirRank: theirRank))
                }
            }
            
            guard shared.count >= 2 else {
                if shared.count == 1 {
                    let maxDiff = max(myGames.count, theirGames.count)
                    guard maxDiff > 0 else { return 100 }
                    let diff = abs(shared[0].myRank - shared[0].theirRank)
                    return max(0, min(100, 100 - Int((Double(diff) / Double(maxDiff)) * 100)))
                }
                return 0
            }
            
            let sortedByMine = shared.indices.sorted { shared[$0].myRank < shared[$1].myRank }
            let sortedByTheirs = shared.indices.sorted { shared[$0].theirRank < shared[$1].theirRank }
            
            var myRelative = Array(repeating: 0, count: shared.count)
            var theirRelative = Array(repeating: 0, count: shared.count)
            
            for (rank, idx) in sortedByMine.enumerated() { myRelative[idx] = rank + 1 }
            for (rank, idx) in sortedByTheirs.enumerated() { theirRelative[idx] = rank + 1 }
            
            let n = Double(shared.count)
            var sumDSquared: Double = 0
            for i in shared.indices {
                let d = Double(myRelative[i] - theirRelative[i])
                sumDSquared += d * d
            }
            
            let denom = n * (n * n - 1)
            guard denom != 0 else { return 50 }
            let rho = 1 - (6 * sumDSquared) / denom
            return max(0, min(100, Int(((rho + 1) / 2) * 100)))
        }
    
    // MARK: - Friend Rankings
    private func fetchFriendRankingsForSheet() async {
        guard let userId = supabase.currentUser?.id else {
            isLoadingFriendRankings = false
            return
        }
        
        do {
            struct FriendshipRow: Decodable {
                let user_id: String
                let friend_id: String
            }
            
            let friendships: [FriendshipRow] = try await supabase.client
                .from("friendships")
                .select("user_id, friend_id")
                .eq("status", value: "accepted")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .execute()
                .value
            
            let friendIds = friendships.map { f in
                f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
            }
            
            guard !friendIds.isEmpty else {
                isLoadingFriendRankings = false
                return
            }
            
            let targetGameId = game.gameId
            let targetCanonicalId = game.canonicalGameId ?? game.gameId
            
            struct RankingRow: Decodable {
                let user_id: String
                let rank_position: Int
                let game_id: Int
                let canonical_game_id: Int?
            }
            
            // Only fetch friends (not self — we already show our own rank)
            let rankings: [RankingRow] = try await supabase.client
                .from("user_games")
                .select("user_id, rank_position, game_id, canonical_game_id")
                .in("user_id", values: friendIds)
                .or("game_id.eq.\(targetGameId),canonical_game_id.eq.\(targetCanonicalId)")
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            let matchedRankings = rankings.filter { r in
                r.game_id == targetGameId ||
                r.game_id == targetCanonicalId ||
                (r.canonical_game_id != nil && r.canonical_game_id == targetCanonicalId)
            }
            
            let rankedUserIds = Array(Set(matchedRankings.map { $0.user_id }))
            
            guard !rankedUserIds.isEmpty else {
                isLoadingFriendRankings = false
                return
            }
            
            struct UserInfo: Decodable {
                let id: String
                let username: String?
                let avatar_url: String?
            }
            
            let users: [UserInfo] = try await supabase.client
                .from("users")
                .select("id, username, avatar_url")
                .in("id", values: rankedUserIds)
                .execute()
                .value
            
            let userMap = Dictionary(uniqueKeysWithValues: users.map { ($0.id.lowercased(), $0) })
            
            // Fetch current user's games for taste match
            struct MyGameRow: Decodable {
                let game_id: Int
                let rank_position: Int
                let canonical_game_id: Int?
            }
            let myGameRows: [MyGameRow] = try await supabase.client
                .from("user_games")
                .select("game_id, rank_position, canonical_game_id")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            let myMapped = myGameRows.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
            
            // Fetch each friend's games for taste match
            var friendGameCache: [String: [(canonicalId: Int, rank: Int)]] = [:]
            for friendId in rankedUserIds {
                let fGames: [MyGameRow] = try await supabase.client
                    .from("user_games")
                    .select("game_id, rank_position, canonical_game_id")
                    .eq("user_id", value: friendId)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .value
                friendGameCache[friendId.lowercased()] = fGames.map { (canonicalId: $0.canonical_game_id ?? $0.game_id, rank: $0.rank_position) }
            }
            
            var results: [(username: String, rank: Int, avatarURL: String?, tasteMatch: Int)] = []
            
            for ranking in matchedRankings {
                if let user = userMap[ranking.user_id.lowercased()] {
                    let theirMapped = friendGameCache[ranking.user_id.lowercased()] ?? []
                    let tm = quickTasteMatch(myGames: myMapped, theirGames: theirMapped)
                    results.append((
                        username: user.username ?? "Unknown",
                        rank: ranking.rank_position,
                        avatarURL: user.avatar_url,
                        tasteMatch: tm
                    ))
                }
            }
            
            friendRankings = results.sorted { $0.rank < $1.rank }
            
        } catch {
            debugLog("❌ Error fetching friend rankings: \(error)")
        }
        
        isLoadingFriendRankings = false
    }
    
    private func friendInitialsCircle(_ name: String, size: CGFloat) -> some View {
        Circle()
            .fill(Color.primaryBlue.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundColor(.primaryBlue)
            )
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
            
            // Compute prediction bias for re-rank
            if existingUserGames.count >= 6 {
                let _ = await PredictionEngine.shared.refreshContext()
                if let context = PredictionEngine.shared.cachedContext {
                    let genres = curatedGenres ?? []
                    let tags = curatedTags ?? []
                    let mc = metacriticScore
                    let rawgId = game.gameRawgId ?? game.gameId
                    debugLog("🎯 Re-rank prediction inputs: genres=\(genres.count) tags=\(tags.count) metacritic=\(String(describing: mc)) rawgId=\(rawgId)")
                    
                    let target = PredictionTarget(
                        rawgId: rawgId,
                        canonicalGameId: nil,
                        genres: genres,
                        tags: tags,
                        metacriticScore: mc
                    )
                    if let prediction = PredictionEngine.shared.predict(game: target, context: context) {
                        let range = prediction.estimatedRank(inListOf: existingUserGames.count)
                        computedPredictedRange = (lower: range.lower, upper: range.upper)
                        debugLog("🎯 Re-rank prediction: ~#\(range.lower)–\(range.upper) (percentile: \(Int(prediction.predictedPercentile))%, confidence: \(prediction.confidence))")
                    } else {
                        debugLog("🎯 Re-rank prediction returned nil")
                    }
                } else {
                    debugLog("🎯 Re-rank: cachedContext is nil")
                }
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
                displayedPlatforms = Array(editedPlatforms).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
