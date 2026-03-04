import SwiftUI
import Supabase
import PhotosUI
import AuthenticationServices
import CryptoKit
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @State private var username = ""
    @State private var originalUsername = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var rankedGames: [UserGame] = []
    @State private var isLoadingGames = true
    @State private var avatarURL: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var selectedImage: UIImage?
    @State private var hasAppleLinked = false
    @State private var currentNonce: String?
    @State private var appleLinkDelegate: AppleLinkDelegate?
    @AppStorage("startTab") private var startTab = 0
    @AppStorage("hideNotifications") private var hideNotifications = false
    @EnvironmentObject var appearanceManager: AppearanceManager
    @State private var showGameSearch = false
    @State private var selectedListTab = 0
    @State private var showResetRankings = false
    @State private var showDiagnosticSheet = false
    @State private var diagnosticNotes = ""
    @State private var isSendingLogs = false
    @State private var logsSent = false
    @State private var showResetFlow = false
    @State private var hasUnrankedGames = false
    @State private var unrankedCount = 0
    @State private var showSteamImport = false
    @State private var showCSVImport = false
    @State private var hasSteamConnected = false
    @State private var pendingImport: PendingImport?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header - Avatar and Username side by side
                    HStack(spacing: 16) {
                        // Avatar
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack {
                                if let avatarURL = avatarURL, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.primaryBlue.opacity(0.2))
                                            .overlay(ProgressView())
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.primaryBlue.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Text(String(username.prefix(1)).uppercased())
                                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                                .foregroundColor(.primaryBlue)
                                        )
                                }
                                
                                if isUploadingPhoto {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                        .overlay(ProgressView().tint(.white))
                                } else if isEditing {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            VStack(spacing: 2) {
                                                Image(systemName: "camera")
                                                    .font(.system(size: 20))
                                                Text("Edit")
                                                    .font(.caption2)
                                            }
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                        }
                        .disabled(!isEditing)
                        
                        // Username and Stats
                        VStack(alignment: .leading, spacing: 8) {
                            if isEditing {
                                TextField("username", text: $username)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                
                                HStack(spacing: 12) {
                                    Button {
                                        username = originalUsername
                                        isEditing = false
                                        message = nil
                                    } label: {
                                        Text("Cancel")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    
                                    Button {
                                        Task { await saveUsername() }
                                    } label: {
                                        Text(isSaving ? "Saving..." : "Save")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(isSaving)
                                }
                            } else {
                                Text(username.isEmpty ? "Set a username" : username)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(username.isEmpty ? Color.adaptiveGray : Color.adaptiveSlate)
                                
                                Text("\(rankedGames.count) games ranked")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.adaptiveGray)
                                
                                Button {
                                    isEditing = true
                                } label: {
                                    Text("Edit Profile")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.adaptiveBlue)
                            }
                            
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(message.contains("saved") ? .success : .error)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Divider()
                        .overlay(Color.adaptiveDivider)
                        .padding(.horizontal, 20)
                    
                    // Tab Picker
                    Picker("List", selection: $selectedListTab) {
                        Text("Ranked").tag(0)
                        Text("Want to Play").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    
                    // List Content
                    VStack(alignment: .leading, spacing: 12) {
                        if selectedListTab == 0 {
                            // Ranked Games
                            if isLoadingGames {
                                ProgressView()
                                    .padding(.top, 20)
                            } else if rankedGames.isEmpty && hasUnrankedGames {
                                VStack(spacing: 12) {
                                    Text("🔄")
                                        .font(.system(size: 40))
                                    
                                    Text("Rankings reset in progress")
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                    
                                    Text("You started a reset but didn't finish. Pick up where you left off!")
                                        .font(.system(size: 15, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 40)
                                    
                                    Button {
                                        Task { await loadUnrankedAndResume() }
                                    } label: {
                                        Text("Continue Re-ranking")
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .padding(.horizontal, 24)
                                            .padding(.vertical, 10)
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .padding(.top, 4)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                            } else if rankedGames.isEmpty {
                                VStack(spacing: 8) {
                                    Text("No games ranked yet")
                                        .font(.body)
                                        .foregroundStyle(Color.adaptiveGray)
                                    Text("Your list is waiting. What's the first game?")
                                        .font(.caption)
                                        .foregroundStyle(Color.adaptiveSilver)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                            } else {
                                if let pending = pendingImport {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.down.circle.fill")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pending.source == "steam_import" ? "Steam import in progress" : "Import in progress")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                            Text("\(pending.currentIndex) of \(pending.totalCount) ranked")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            if pending.source == "steam_import" {
                                                showSteamImport = true
                                            } else if pending.source == "csv_import" {
                                                showCSVImport = true
                                            }
                                        } label: {
                                            Text("Continue")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(.accentOrange)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(Color.white)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.accentOrange)
                                    .cornerRadius(12)
                                    .padding(.horizontal, 20)
                                }
                                if hasUnrankedGames {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.accentOrange)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Re-ranking in progress")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Color.adaptiveSlate)
                                            Text("\(rankedGames.count) ranked, \(unrankedCount) to go")
                                                .font(.system(size: 12, design: .rounded))
                                                .foregroundStyle(Color.adaptiveGray)
                                        }
                                        
                                        Spacer()
                                        
                                        Button {
                                            Task { await loadUnrankedAndResume() }
                                        } label: {
                                            Text("Continue")
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 6)
                                                .background(Color.accentOrange)
                                                .cornerRadius(8)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.accentOrange.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.accentOrange.opacity(0.4), lineWidth: 1)
                                    )
                                    .cornerRadius(12)
                                    .padding(.horizontal, 20)
                                }
                                
                                ForEach(Array(rankedGames.enumerated()), id: \.element.id) { index, game in
                                    RankedGameRow(rank: index + 1, game: game) {
                                        await fetchRankedGames()
                                    }
                                }
                                .padding(.horizontal, 20)
                                .tourAnchor("rankedList")
                            }
                        } else {
                            // Want to Play
                            WantToPlayListView()
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 32)
                    .iPadReadableWidth()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGameSearch, onDismiss: {
                Task {
                    await fetchRankedGames()
                    await WantToPlayManager.shared.refreshMyIds()
                }
            }) {
                GameSearchView()
            }
            .fullScreenCover(isPresented: $showCSVImport, onDismiss: {
                Task {
                    await fetchRankedGames()
                    pendingImport = await PendingImportManager.shared.fetchAny()
                }
            }) {
                CSVImportView(resumingImport: pendingImport?.source == "csv_import" ? pendingImport : nil)
            }
            .alert("Start fresh?", isPresented: $showResetRankings) {
                Button("Yeah, let's start over", role: .destructive) {
                    showResetFlow = true
                }
                Button("Nevermind", role: .cancel) { }
            } message: {
                Text("This will reset all your rankings and take you through the comparison flow again from the top. Your games, notes, and platforms stay. Just the order gets wiped. This can't be undone!")
            }
            .sheet(isPresented: $showDiagnosticSheet) {
                NavigationStack {
                    VStack(spacing: 20) {
                        Image(systemName: "ladybug")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentOrange)
                        
                        Text("Send Diagnostic Logs")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        Text("This sends your recent session logs to the dev team to help debug issues. No personal data is included beyond your username.")
                            .font(.subheadline)
                            .foregroundStyle(Color.adaptiveGray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("\(LogCollector.shared.entryCount()) log entries this session")
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                        
                        TextEditor(text: $diagnosticNotes)
                            .frame(height: 100)
                            .padding(12)
                            .background(Color.secondaryBackground)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.adaptiveSilver, lineWidth: 1)
                            )
                            .overlay(
                                Group {
                                    if diagnosticNotes.isEmpty {
                                        Text("What went wrong? (optional)")
                                            .foregroundStyle(Color.adaptiveGray)
                                            .padding(.leading, 16)
                                            .padding(.top, 20)
                                    }
                                },
                                alignment: .topLeading
                            )
                            .padding(.horizontal)
                        
                        Button {
                            Task {
                                isSendingLogs = true
                                let success = await SupabaseManager.shared.submitDiagnosticLogs(notes: diagnosticNotes)
                                isSendingLogs = false
                                if success {
                                    logsSent = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        showDiagnosticSheet = false
                                        logsSent = false
                                        diagnosticNotes = ""
                                    }
                                }
                            }
                        } label: {
                            if isSendingLogs {
                                ProgressView()
                            } else if logsSent {
                                Label("Sent!", systemImage: "checkmark.circle.fill")
                            } else {
                                Text("Send Logs")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSendingLogs || logsSent)
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding(.top, 30)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showDiagnosticSheet = false }
                                .foregroundColor(.primaryBlue)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showResetFlow, onDismiss: {
                Task { await fetchRankedGames() }
            }) {
                ResetRankingsView(games: rankedGames, resuming: hasUnrankedGames) {
                    Task { await fetchRankedGames() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showGameSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                            .tourAnchor("plusButton")
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = "https://playedit.app/profile/\(username)"
                            message = "Profile link copied!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                message = nil
                            }
                        } label: {
                            Label("Share Profile Link", systemImage: "link")
                        }
                        
                        Menu {
                            NavigationLink {
                                FeedbackView()
                            } label: {
                                Label("Send Feedback", systemImage: "bubble.left.and.bubble.right")
                            }
                            
                            Button {
                                showDiagnosticSheet = true
                            } label: {
                                Label("Send Diagnostic Logs", systemImage: "ladybug")
                            }
                        } label: {
                            Label("Help & Feedback", systemImage: "questionmark.circle")
                        }
                        
                        // Settings submenu
                        Menu {
                            Menu {
                                Button { startTab = 0 } label: {
                                    HStack {
                                        Text("Feed")
                                        if startTab == 0 { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { startTab = 1 } label: {
                                    HStack {
                                        Text("Friends")
                                        if startTab == 1 { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { startTab = 2 } label: {
                                    HStack {
                                        Text("Profile")
                                        if startTab == 2 { Image(systemName: "checkmark") }
                                    }
                                }
                            } label: {
                                Label("Start Screen", systemImage: "house")
                            }
                            
                            Menu {
                                Button { appearanceManager.appearanceMode = 0 } label: {
                                    HStack {
                                        Text("System")
                                        if appearanceManager.appearanceMode == 0 { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { appearanceManager.appearanceMode = 1 } label: {
                                    HStack {
                                        Text("Light")
                                        if appearanceManager.appearanceMode == 1 { Image(systemName: "checkmark") }
                                    }
                                }
                                Button { appearanceManager.appearanceMode = 2 } label: {
                                    HStack {
                                        Text("Dark")
                                        if appearanceManager.appearanceMode == 2 { Image(systemName: "checkmark") }
                                    }
                                }
                            } label: {
                                Label("Appearance", systemImage: "moon.circle")
                            }
                            
                            Toggle(isOn: $hideNotifications) {
                                Label("Hide Notifications", systemImage: "bell.slash")
                            }
                            
                            Button {
                                showSteamImport = true
                            } label: {
                                Label(hasSteamConnected ? "Import from Steam (Connected ✓)" : "Import from Steam", systemImage: "arrow.down.circle")
                            }
                            
                            Button {
                                showCSVImport = true
                            } label: {
                                Label("Import from CSV", systemImage: "doc.text")
                            }
                            
                            if !hasAppleLinked {
                                Button {
                                    triggerAppleLinking()
                                } label: {
                                    Label("Link Apple ID", systemImage: "apple.logo")
                                }
                            }
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        
                        if rankedGames.count >= 2 {
                            Divider()
                            
                            Button(role: .destructive) {
                                showResetRankings = true
                            } label: {
                                Label("Reset Rankings", systemImage: "arrow.counterclockwise")
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            PushNotificationManager.shared.removeDeviceToken()
                            UIApplication.shared.unregisterForRemoteNotifications()
                            Task { await supabase.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.primaryBlue)
                            .tourAnchor("settingsButton")
                    }
                }
            }
        }
        .task {
            async let profileTask: () = fetchProfile()
            async let rankedTask: () = fetchRankedGames()
            async let appleTask = supabase.hasAppleIdentity()
            async let steamTask = SteamService.shared.getSteamId()
            async let pendingTask = PendingImportManager.shared.fetchAny()
            
            _ = await (profileTask, rankedTask)
            hasAppleLinked = await appleTask
            hasSteamConnected = await steamTask != nil
            pendingImport = await pendingTask
        }
        .onReceive(NotificationCenter.default.publisher(for: .profileNudgeTapped)) { _ in
                isEditing = true
            }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("profileShouldRefresh"))) { _ in
                Task { await fetchRankedGames() }
            }
        .onChange(of: selectedPhoto) { _, newValue in
            if let newValue = newValue {
                Task {
                    debugLog("📸 Photo selected, loading...")
                    do {
                        if let data = try await newValue.loadTransferable(type: Data.self) {
                            debugLog("📸 Data loaded: \(data.count) bytes")
                            if let uiImage = UIImage(data: data) {
                                debugLog("📸 Image created: \(uiImage.size)")
                                await MainActor.run {
                                    selectedImage = uiImage
                                }
                            } else {
                                debugLog("❌ Could not create UIImage from data")
                            }
                        } else {
                            debugLog("❌ Data was nil")
                        }
                    } catch {
                        debugLog("❌ Error loading photo: \(error)")
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedImage) { image in
            ImageCropperView(
                image: image,
                onCrop: { croppedImage in
                    selectedImage = nil
                    selectedPhoto = nil
                    Task { await uploadCroppedPhoto(croppedImage) }
                },
                onCancel: {
                    selectedImage = nil
                    selectedPhoto = nil
                }
            )
        }
    }
    
    private func fetchProfile() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct UserProfile: Decodable {
                let username: String?
                let avatar_url: String?
            }
            
            let profile: UserProfile = try await supabase.client
                .from("users")
                .select("username, avatar_url")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            username = profile.username ?? ""
            originalUsername = profile.username ?? ""
            avatarURL = profile.avatar_url
            
        } catch {
            debugLog("❌ Error fetching profile: \(error)")
        }
    }
    
    private func fetchRankedGames() async {
        guard let userId = supabase.currentUser?.id else {
            isLoadingGames = false
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
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                    let rawg_id: Int?
                    let description: String?
                    let curated_description: String?
                    let metacritic_score: Int?
                    let curated_genres: [String]?
                    let curated_tags: [String]?
                    let curated_platforms: [String]?
                    let curated_release_year: Int?
                }
            }
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date, rawg_id, description, curated_description, metacritic_score, curated_genres, curated_tags, curated_platforms, curated_release_year)")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            for row in rows {
                let desc = row.games.curated_description ?? row.games.description
                if desc != nil || row.games.metacritic_score != nil {
                    GameMetadataCache.shared.set(
                        gameId: row.game_id,
                        description: desc,
                        metacriticScore: row.games.metacritic_score,
                        releaseDate: row.games.release_date,
                        curatedGenres: row.games.curated_genres,
                        curatedTags: row.games.curated_tags,
                        curatedPlatforms: row.games.curated_platforms,
                        curatedReleaseYear: row.games.curated_release_year
                    )
                }
            }
            
            rankedGames = rows.map { row in
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
            
        } catch {
            debugLog("❌ Error fetching ranked games: \(error)")
        }
        
        // Check if user has unranked games (mid-reset)
        if let userId = supabase.currentUser?.id {
            do {
                let totalRows: Int = try await supabase.client
                    .from("user_games")
                    .select("*", head: true, count: .exact)
                    .eq("user_id", value: userId.uuidString)
                    .not("rank_position", operator: .is, value: "null")
                    .execute()
                    .count ?? 0
                
                // totalRows = games WITH a rank. If that's less than total user_games, some are unranked (mid-reset)
                let allRows: Int = try await supabase.client
                    .from("user_games")
                    .select("*", head: true, count: .exact)
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .count ?? 0
                
                unrankedCount = allRows - totalRows
                hasUnrankedGames = unrankedCount > 0
                debugLog("🔍 Ranked: \(totalRows), Unranked: \(unrankedCount), hasUnranked: \(hasUnrankedGames)")
            } catch {
                debugLog("❌ Error checking unranked games: \(error)")
            }
        }
        
        ImageCache.shared.prefetch(urls: rankedGames.compactMap { $0.gameCoverURL })
        isLoadingGames = false
        NotificationCenter.default.post(name: .wantToPlayShouldRefresh, object: nil)
    }
    private func loadUnrankedAndResume() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int?
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
                .execute()
                .value
            
            rankedGames = rows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position ?? 0,
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
            
            showResetFlow = true
            
        } catch {
            debugLog("❌ Error loading unranked games: \(error)")
        }
    }
    private func saveUsername() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        // Only save if username actually changed
        guard username != originalUsername else {
            isEditing = false
            return
        }
        
        isSaving = true
        message = nil
        
        // Check username moderation
        let moderationResult = await ModerationService.shared.moderateUsername(username)
        if !moderationResult.allowed {
            message = moderationResult.reason
            isSaving = false
            return
        }
        
        do {
            try await supabase.client
                .from("users")
                .update(["username": username])
                .eq("id", value: userId.uuidString)
                .execute()
            
            originalUsername = username
            message = "Username saved!"
            isEditing = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                message = nil
            }
            
        } catch {
            debugLog("❌ Error saving username: \(error)")
            message = "Couldn't save username"
        }
        
        isSaving = false
    }
    
    private func uploadCroppedPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        
        guard let userId = supabase.currentUser?.id else {
            isUploadingPhoto = false
            return
        }
        
        // Check image for sensitive content
        let photoResult = await PhotoModerator.shared.checkImage(image)
        if !photoResult.allowed {
            message = photoResult.reason
            isUploadingPhoto = false
            return
        }
        
        do {
            guard let compressedData = image.jpegData(compressionQuality: 0.7) else {
                debugLog("❌ Could not compress image")
                isUploadingPhoto = false
                return
            }
            
            let fileName = "\(userId.uuidString)/avatar.jpg"
            
            try await supabase.client.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: compressedData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.client.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            
            let urlWithCacheBuster = "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
            
            try await supabase.client
                .from("users")
                .update(["avatar_url": urlWithCacheBuster])
                .eq("id", value: userId.uuidString)
                .execute()
            
            // Clear the URL first to force AsyncImage to reload
            await MainActor.run {
                avatarURL = nil
            }
            
            // Small delay then set the new URL
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                avatarURL = urlWithCacheBuster
            }
            
        } catch {
            debugLog("❌ Error uploading photo: \(error)")
        }
        
        isUploadingPhoto = false
    }
    
    // MARK: - Apple ID Linking
    private func triggerAppleLinking() {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleLinkDelegate(nonce: nonce) { success in
            if success {
                hasAppleLinked = true
                message = "Apple ID linked!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    message = nil
                }
            }
        }
        appleLinkDelegate = delegate
        controller.delegate = delegate
        debugLog("🍎 Performing Apple auth request...")
        controller.performRequests()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple Link Delegate
class AppleLinkDelegate: NSObject, ASAuthorizationControllerDelegate {
    let nonce: String
    let completion: (Bool) -> Void
    
    init(nonce: String, completion: @escaping (Bool) -> Void) {
        self.nonce = nonce
        self.completion = completion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        debugLog("🍎 Apple auth completed successfully")
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            debugLog("❌ Missing Apple credential data")
            completion(false)
            return
        }
        debugLog("🍎 Got Apple ID token, calling Edge Function...")
        
        Task {
            let success = await SupabaseManager.shared.linkAppleID(idToken: idToken, nonce: nonce)
            debugLog("🍎 Edge Function result: \(success)")
            if let error = SupabaseManager.shared.errorMessage {
                debugLog("🍎 Error message: \(error)")
            }
            await MainActor.run {
                completion(success)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        debugLog("❌ Apple linking failed: \(error)")
        completion(false)
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: Int {
        hashValue
    }
}

#Preview {
    ProfileView()
}
