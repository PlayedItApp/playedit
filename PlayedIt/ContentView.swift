import SwiftUI
import Supabase
import Combine

struct ContentView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var isCheckingAuth = true
    
    var body: some View {
        Group {
            if isCheckingAuth {
                SplashView()
            } else if supabase.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: isCheckingAuth)
        .task {
            await supabase.checkSession()
            isCheckingAuth = false
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
                    .font(.largeTitle)
                    .foregroundColor(.slate)
                Text("it")
                    .font(.largeTitle)
                    .foregroundColor(.accentOrange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

// MARK: - Main Tab View
struct MainTabView: View {
    @AppStorage("startTab") private var startTab = 0
    @State private var selectedTab = 0
    @State private var pendingRequestCount = 0
    @State private var unreadNotificationCount = 0
    @State private var showWhatsNew = false
    @ObservedObject var supabase = SupabaseManager.shared
    
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
        .task {
            selectedTab = startTab
            await fetchPendingCount()
            await fetchUnreadNotificationCount()
            await WantToPlayManager.shared.refreshMyIds()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await fetchUnreadNotificationCount()
            }
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
            print("❌ Error fetching pending count: \(error)")
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
                print("🔔 MainTab unread count: \(count) for user: \(userId.uuidString)")
                
            } catch {
            print("❌ Error fetching notification count: \(error)")
        }
    }
}

// MARK: - Ranked Game Row
struct RankedGameRow: View {
    let rank: Int
    let game: UserGame
    var onUpdate: (() -> Void)? = nil
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
                
                AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
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
                    Text(game.gameTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.slate)
                        .lineLimit(2)
                    
                    if let year = game.gameReleaseDate?.prefix(4) {
                        Text(String(year))
                            .font(.caption)
                            .foregroundColor(.grayText)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.silver)
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail, onDismiss: {
            onUpdate?()
        }) {
            GameDetailSheet(game: game, rank: rank)
        }
    }
    
    private var rankColor: Color {
        switch rank {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        default: return .slate
        }
    }
}

// MARK: - Game Detail Sheet
struct GameDetailSheet: View {
    let game: UserGame
    let rank: Int
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
    @State private var displayedNotes: String? = nil
    @State private var displayedPlatforms: [String] = []
    @State private var hasInitialized = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cover art
                    AsyncImage(url: URL(string: game.gameCoverURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.lightGray)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .font(.system(size: 40))
                                    .foregroundColor(.silver)
                            )
                    }
                    .frame(width: 150, height: 200)
                    .cornerRadius(12)
                    .clipped()
                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
                    
                    // Title and rank
                    VStack(spacing: 8) {
                        Text(game.gameTitle)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.slate)
                            .multilineTextAlignment(.center)
                        
                        Text("Ranked #\(rank)")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(rank == 1 ? .accentOrange : .primaryBlue)
                    }
                    
                    Divider()
                        .padding(.horizontal, 40)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Played on", systemImage: "gamecontroller")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.grayText)
                                
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
                                    ForEach(GameLogView.allPlatforms, id: \.self) { platform in
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
                                
                                HStack(spacing: 10) {
                                    TextField("Other platform...", text: $customPlatform)
                                        .font(.system(size: 14, design: .rounded))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Color.lightGray)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.silver, lineWidth: 1)
                                        )
                                    
                                    Button {
                                        let trimmed = customPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
                                        guard !trimmed.isEmpty else { return }
                                        editedPlatforms.insert(trimmed)
                                        customPlatform = ""
                                    } label: {
                                        Text("Add")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.silver : Color.primaryBlue)
                                            .cornerRadius(8)
                                    }
                                    .disabled(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                                
                                // Show custom selections not in the standard list
                                let customSelections = editedPlatforms.filter { !GameLogView.allPlatforms.contains($0) }
                                if !customSelections.isEmpty {
                                    FlowLayout(spacing: 8) {
                                        ForEach(Array(customSelections).sorted(), id: \.self) { platform in
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
                                
                                HStack(spacing: 12) {
                                    Button {
                                        isEditingPlatforms = false
                                        customPlatform = ""
                                    } label: {
                                        Text("Cancel")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.grayText)
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
                                    .foregroundColor(.slate)
                            } else {
                                Text("No platforms added. Tap Add to set them!")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.grayText)
                                    .italic()
                            }
                        }
                        
                        if let year = game.gameReleaseDate?.prefix(4) {
                            DetailRow(
                                icon: "calendar",
                                label: "Released",
                                value: String(year)
                            )
                        }
                        
                        // Notes section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Notes", systemImage: "note.text")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.grayText)
                                
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
                                    .background(Color.lightGray)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.silver, lineWidth: 1)
                                    )
                                    .overlay(
                                        Group {
                                            if editedNotes.isEmpty {
                                                Text("Favorite moments? Hot takes? (optional)")
                                                    .foregroundColor(.grayText)
                                                    .padding(.leading, 16)
                                                    .padding(.top, 20)
                                            }
                                        },
                                        alignment: .topLeading
                                    )
                                
                                SpoilerHint()
                                
                                HStack(spacing: 12) {
                                    Button {
                                        isEditingNotes = false
                                        editedNotes = ""
                                    } label: {
                                        Text("Cancel")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(.grayText)
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
                            } else {
                                Text("No notes yet. Tap Add to write a review!")
                                    .font(.system(size: 14, design: .rounded))
                                    .foregroundColor(.grayText)
                                    .italic()
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
                    displayedPlatforms = game.platformPlayed
                    hasInitialized = true
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
                            .foregroundColor(.silver)
                    }
                }
            }
            .sheet(isPresented: $showComparison) {
                ComparisonView(
                    newGame: game.toGame(),
                    existingGames: existingUserGames,
                    onComplete: { newPosition in
                        Task {
                            await saveReRankedGame(newPosition: newPosition)
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
                }
            }
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: userId.uuidString)
                .neq("game_id", value: game.gameId)
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
                    gameReleaseDate: row.games.release_date
                )
            }
            
            isLoadingReRank = false
            showComparison = true
            
        } catch {
            print("❌ Error loading games for re-rank: \(error)")
            isLoadingReRank = false
        }
    }
    
    // MARK: - Save Re-Ranked Game
    private func saveReRankedGame(newPosition: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            // 1. Delete the old entry
            try await supabase.client
                .from("user_games")
                .delete()
                .eq("id", value: game.id)
                .execute()
            
            // 2. Shift games that were below the old rank up by 1
            struct GameToShift: Decodable {
                let id: String
                let rank_position: Int
            }
            
            let gamesToShiftUp: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .gt("rank_position", value: rank)
                .execute()
                .value
            
            for g in gamesToShiftUp {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position - 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            // 3. Shift games at or below the new position down by 1
            let gamesToShiftDown: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .gte("rank_position", value: newPosition)
                .order("rank_position", ascending: false)
                .execute()
                .value
            
            for g in gamesToShiftDown {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position + 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            // Resolve canonical game ID
            let canonicalId = await RAWGService.shared.getParentGameId(for: game.gameId) ?? game.gameId
            
            // 4. Insert at new position
            struct UserGameInsert: Encodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let platform_played: [String]
                let notes: String
                let canonical_game_id: Int
            }
            
            let insert = UserGameInsert(
                user_id: userId.uuidString,
                game_id: game.gameId,
                rank_position: newPosition,
                platform_played: game.platformPlayed,
                notes: game.notes ?? "",
                canonical_game_id: canonicalId
            )
            
            try await supabase.client.from("user_games")
                .insert(insert)
                .execute()
            
            print("✅ Re-ranked from #\(rank) → #\(newPosition)")
            
        } catch {
            print("❌ Error saving re-ranked game: \(error)")
        }
    }
    
    // MARK: - Remove Game
    private func removeGame() async {
        guard let userId = supabase.currentUser?.id else { return }
        isRemoving = true
        
        do {
            // 1. Delete reactions and comments on this entry
            try await supabase.client
                .from("feed_reactions")
                .delete()
                .eq("user_game_id", value: game.id)
                .execute()
            
            try await supabase.client
                .from("feed_comments")
                .delete()
                .eq("user_game_id", value: game.id)
                .execute()
            
            // 2. Delete the user_game entry
            try await supabase.client
                .from("user_games")
                .delete()
                .eq("id", value: game.id)
                .execute()
            
            // 3. Shift all games ranked below this one up by 1
            struct GameToShift: Decodable {
                let id: String
                let rank_position: Int
            }
            
            let gamesToShift: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .gt("rank_position", value: rank)
                .execute()
                .value
            
            for g in gamesToShift {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": g.rank_position - 1])
                    .eq("id", value: g.id)
                    .execute()
            }
            
            print("✅ Removed \(game.gameTitle) from rankings")
            dismiss()
            
        } catch {
            print("❌ Error removing game: \(error)")
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
                
                print("✅ Platforms saved")
                displayedPlatforms = Array(editedPlatforms)
                isEditingPlatforms = false
                customPlatform = ""
                
            } catch {
                print("❌ Error saving platforms: \(error)")
            }
            
            isSavingPlatforms = false
        }
    
    // MARK: - Save Notes
    private func saveNotes() async {
        isSavingNotes = true
        
        do {
            let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            
            try await supabase.client
                .from("user_games")
                .update(["notes": trimmed])
                .eq("id", value: game.id)
               
                .execute()
            
            print("✅ Notes saved")
            displayedNotes = trimmed
            isEditingNotes = false
            
        } catch {
            print("❌ Error saving notes: \(error)")
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.primaryBlue)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.grayText)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, design: .rounded))
                .foregroundColor(.slate)
        }
    }
}

#Preview {
    ContentView()
}
