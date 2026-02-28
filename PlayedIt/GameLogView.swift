import SwiftUI
import Supabase

struct GameLogView: View {
    let game: Game
    var source: String = "unknown"
    @Environment(\.dismiss) var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var selectedPlatforms: Set<String> = []
    @State private var customPlatform: String = ""
    @State private var notes: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showComparison = false
    @State private var savedGameId: Int?
    @State private var existingUserGames: [UserGame] = []
    @State private var existingUserGame: ExistingUserGame? = nil
    @State private var showReRankAlert = false
    @State private var showAllPlatforms = false
    @State private var gameDescription: String? = nil
    @State private var computedPredictedRange: (lower: Int, upper: Int)? = nil
    
    static let allPlatforms = [
        "Android", "Apple TV", "Apple Vision Pro",
        "Atari",
        "Dreamcast",
        "Game Boy", "Game Boy Advance", "Game Boy Advance SP",
        "Game Boy Color", "Game Gear", "GameCube",
        "iOS",
        "Linux",
        "Mac", "Meta Quest 3", "Meta Quest 3S",
        "Neo Geo", "NES", "Nintendo 3DS", "Nintendo 64", "Nintendo DS",
        "Nintendo Switch", "Nintendo Switch 2",
        "Oculus Quest", "Oculus Quest 2", "Oculus Rift",
        "PC",
        "PlayStation", "PlayStation 2", "PlayStation 3",
        "PlayStation 4", "PlayStation 5",
        "PlayStation Portable (PSP)", "PlayStation Vita",
        "PlayStation VR", "PlayStation VR2",
        "SNES", "Steam Deck",
        "Wii", "Wii U",
        "Xbox", "Xbox 360", "Xbox One",
        "Xbox Series S", "Xbox Series X"
    ]
    
    static let popularPlatforms = [
        "PC", "PlayStation 5", "PlayStation 4",
        "Xbox Series X", "Xbox One",
        "Nintendo Switch", "Nintendo Switch 2",
        "Steam Deck", "Nintendo 3DS", "Wii"
    ]
    
    // MARK: - UserDefaults Platform History
    static func usedPlatforms(for userId: UUID) -> Set<String> {
        let key = "used_platforms_\(userId.uuidString)"
        let array = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(array)
    }
    
    static func saveUsedPlatforms(_ platforms: Set<String>, for userId: UUID) {
        let key = "used_platforms_\(userId.uuidString)"
        var existing = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        existing.formUnion(platforms)
        UserDefaults.standard.set(Array(existing).sorted(), forKey: key)
    }
    
    static func backfillUsedPlatformsIfNeeded(for userId: UUID, client: SupabaseClient) async {
        let backfillKey = "used_platforms_backfilled_\(userId.uuidString)"
        guard !UserDefaults.standard.bool(forKey: backfillKey) else { return }
        
        do {
            struct PlatformRow: Decodable {
                let platform_played: [String]
            }
            let rows: [PlatformRow] = try await client
                .from("user_games")
                .select("platform_played")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            let allUsed = Set(rows.flatMap { $0.platform_played })
            if !allUsed.isEmpty {
                saveUsedPlatforms(allUsed, for: userId)
            }
            UserDefaults.standard.set(true, forKey: backfillKey)
        } catch {
            debugLog("⚠️ Platform backfill failed: \(error)")
        }
    }
    
    private var quickPlatforms: [String] {
        guard let userId = supabase.currentUser?.id else { return Self.popularPlatforms }
        let used = Self.usedPlatforms(for: userId)
        if used.isEmpty {
            return Self.popularPlatforms
        }
        return Self.allPlatforms.filter { used.contains($0) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Game Header
                    HStack(spacing: 16) {
                        CachedAsyncImage(url: game.coverURL) {
                            Rectangle()
                                .fill(Color.secondaryBackground)
                                .overlay(
                                    Image(systemName: "gamecontroller")
                                        .foregroundStyle(Color.adaptiveSilver)
                                )
                        }
                        .frame(width: 80, height: 107)
                        .cornerRadius(8)
                        .clipped()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                                .lineLimit(2)
                            
                            if let year = game.releaseDate?.prefix(4) {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.adaptiveGray)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Game description
                    if let desc = gameDescription, !desc.isEmpty {
                        GameDescriptionView(text: desc)
                            .padding(.horizontal, 20)
                    }
                    
                    // Platform Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where'd you play it? (optional)")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        Text("Select all that apply")
                            .font(.caption)
                            .foregroundStyle(Color.adaptiveGray)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(quickPlatforms, id: \.self) { platform in
                                PlatformButton(
                                    platform: platform,
                                    isSelected: selectedPlatforms.contains(platform)
                                ) {
                                    if selectedPlatforms.contains(platform) {
                                        selectedPlatforms.remove(platform)
                                    } else {
                                        selectedPlatforms.insert(platform)
                                    }
                                }
                            }
                        }
                        
                        // Show any selected platforms not in quickPlatforms
                        let extraSelections = selectedPlatforms.filter { !quickPlatforms.contains($0) }
                        if !extraSelections.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(extraSelections).sorted(), id: \.self) { platform in
                                    HStack(spacing: 4) {
                                        Text(platform)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                        Button {
                                            selectedPlatforms.remove(platform)
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
                        
                        // More Platforms button
                        Button {
                            showAllPlatforms = true
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
                    }
                    .padding(.horizontal, 20)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Any thoughts?")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                        
                        TextEditor(text: $notes)
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
                                    if notes.isEmpty {
                                        Text("Favorite moments? Hot takes? (optional)")
                                            .foregroundStyle(Color.adaptiveGray)
                                            .padding(.leading, 16)
                                            .padding(.top, 20)
                                    }
                                },
                                alignment: .topLeading
                            )
                        SpoilerHint()
                    }
                    .padding(.horizontal, 20)
                    
                    // Error Message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.error)
                            Text(error)
                                .font(.callout)
                                .foregroundColor(.error)
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Spacer().frame(height: 20)
                }
            }
            .navigationTitle("Log Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.primaryBlue)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveGame()
                        }
                    } label: {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(isLoading ? .gray : .primaryBlue)
                    .disabled(isLoading)
                }
            }
            .sheet(isPresented: $showAllPlatforms) {
                PlatformPickerSheet(selectedPlatforms: $selectedPlatforms)
            }
            .sheet(isPresented: $showComparison) {
                if let gameId = savedGameId {
                    ComparisonView(
                        newGame: game,
                        existingGames: existingUserGames,
                        predictedPosition: computedPredictedRange.map { ($0.lower + $0.upper) / 2 },
                        predictedRange: computedPredictedRange,
                        onComplete: { position in
                            Task {
                                await saveUserGame(gameId: gameId, position: position)
                                dismiss()
                            }
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
            .task {
                await checkIfAlreadyRanked()
                await fetchDescription()
            }
            .alert("Already Ranked", isPresented: $showReRankAlert) {
                Button("Re-rank") {
                    Task {
                        await deleteExistingAndReRank()
                    }
                }
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
            } message: {
                if let existing = existingUserGame {
                    Text("\(game.title) is already ranked at #\(existing.rank_position). Would you like to re-rank it?")
                }
            }
        }
    }
    
    // MARK: - Fetch Description
    private func fetchDescription() async {
        // Check Supabase cache first
        do {
            struct GameDesc: Decodable { let description: String? }
            let results: [GameDesc] = try await SupabaseManager.shared.client
                .from("games")
                .select("description")
                .eq("rawg_id", value: game.rawgId)
                .limit(1)
                .execute()
                .value
            
            if let cached = results.first?.description, !cached.isEmpty {
                gameDescription = cached
                return
            }
        } catch {
            debugLog("⚠️ Could not check cached description: \(error)")
        }
        
        // Fall back to RAWG
        do {
            let details = try await RAWGService.shared.getGameDetails(id: game.rawgId)
            gameDescription = details.gameDescription ?? details.gameDescriptionHtml
            
            // Upsert game row so description is cached even if user doesn't rank
            let desc = details.gameDescriptionHtml ?? details.gameDescription
            
            struct GameUpsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String?
                let metacritic_score: Int
                let description: String?
            }
            
            let upsert = GameUpsert(
                rawg_id: game.rawgId,
                title: game.title,
                cover_url: game.coverURL ?? "",
                genres: game.genres,
                platforms: game.platforms,
                release_date: game.releaseDate,
                metacritic_score: game.metacriticScore ?? 0,
                description: desc
            )
            
            _ = try? await SupabaseManager.shared.client
                .from("games")
                .upsert(upsert, onConflict: "rawg_id")
                .execute()
            debugLog("📖 Upserted game + description for \(game.title)")
        } catch {
            debugLog("⚠️ Could not fetch game description: \(error)")
        }
    }
    
    // MARK: - Check If Already Ranked
    private func checkIfAlreadyRanked() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct GameIdLookup: Decodable {
                let id: Int
            }
            
            let gameRecords: [GameIdLookup] = try await supabase.client
                .from("games")
                .select("id")
                .eq("rawg_id", value: game.rawgId)
                .execute()
                .value
            
            guard let gameRecord = gameRecords.first else {
                return
            }
            
            let response: [ExistingUserGame] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .eq("game_id", value: gameRecord.id)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            
            if let existing = response.first {
                existingUserGame = existing
                showReRankAlert = true
            }
        } catch {
            debugLog("Failed to check existing game: \(error)")
        }
    }
    
    // MARK: - Start Re-Rank Flow
    private func deleteExistingAndReRank() async {
        // Just trigger the save flow - it will handle re-ranking
        // We pass a flag by keeping existingUserGame set
        await saveGame()
    }
    
    // MARK: - Predicted Position for Comparison Bias
    private func predictedPositionForGame(
        genres: [String],
        tags: [String],
        metacriticScore: Int?
    ) -> Int? {
        if existingUserGames.count < 6 {
            debugLog("🎯 predictedPositionForGame: bail (not enough games) existingGames=\(existingUserGames.count)")
            return nil
        }

        debugLog("🎯 predictedPositionForGame: existingGames=\(existingUserGames.count), cachedContext=\(PredictionEngine.shared.cachedContext != nil)")

        guard let context = PredictionEngine.shared.cachedContext else {
            debugLog("🎯 predictedPositionForGame: bail (context=nil)")
            return nil
        }

        let target = PredictionTarget(
            rawgId: game.rawgId,
            canonicalGameId: nil,
            genres: genres,
            tags: tags,
            metacriticScore: metacriticScore
        )

        guard let prediction = PredictionEngine.shared.predict(game: target, context: context) else {
            debugLog("🎯 predictedPositionForGame: bail (prediction=nil) rawgId=\(game.rawgId) genres=\(genres.count) tags=\(tags.count) metacritic=\(String(describing: metacriticScore))")
            return nil
        }

        let totalGames = existingUserGames.count + 1
        let position = max(1, Int(round(Double(totalGames) * (1.0 - prediction.predictedPercentile / 100.0))))

        debugLog("🎯 Predicted position for \(game.title): #\(position) of \(totalGames) (percentile: \(Int(prediction.predictedPercentile))%)")

        return position
    }
    
    // MARK: - Save Game
    private func saveGame() async {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        // Moderate game notes if provided
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            let result = await ModerationService.shared.moderateGameNote(trimmedNotes)
            if !result.allowed {
                errorMessage = result.reason
                isLoading = false
                return
            }
        }
        
        do {
            struct GameInsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String?
                let metacritic_score: Int
                let tags: [String]
            }
            
            // Fetch prediction inputs from RAWG detail endpoint (search results don't include them reliably)
            var predictionGenres = game.genres
            var predictionTags = game.tags
            var predictionMetacritic = game.metacriticScore

            if predictionGenres.isEmpty || predictionTags.isEmpty || predictionMetacritic == nil {
                if let details = try? await RAWGService.shared.getGameDetails(id: game.rawgId) {
                    if predictionGenres.isEmpty {
                        predictionGenres = details.genres
                    }
                    if predictionTags.isEmpty {
                        predictionTags = details.tags
                    }
                    if predictionMetacritic == nil {
                        predictionMetacritic = details.metacriticScore
                    }
                }
            }

            // Filter out non-useful tags for taste prediction
            let excludedTags: Set<String> = [
                "Steam Achievements", "Steam Cloud", "Full controller support",
                "Steam Leaderboards", "Steam Trading Cards", "Steam Workshop",
                "controller support", "cloud saves", "overlay", "online",
                "achievements", "stats", "console", "offline",
                "Includes level editor", "Early Access", "Free to Play"
            ]

            predictionTags = predictionTags.filter { tag in
                !excludedTags.contains(tag) &&
                tag.allSatisfy { $0.isASCII || $0 == " " || $0 == "-" }
            }

            debugLog("🏷️ Prediction inputs for \(game.title): genres=\(predictionGenres.count) tags=\(predictionTags.count) metacritic=\(String(describing: predictionMetacritic))")
            
            let gameInsert = GameInsert(
                rawg_id: game.rawgId,
                title: game.title,
                cover_url: game.coverURL ?? "",
                genres: predictionGenres,
                platforms: game.platforms,
                release_date: game.releaseDate,
                metacritic_score: predictionMetacritic ?? 0,
                tags: predictionTags
            )
            
            try await supabase.client.from("games")
                .upsert(gameInsert, onConflict: "rawg_id")
                .execute()
            
            struct GameIdResponse: Decodable {
                let id: Int
            }
            
            let gameRecord: GameIdResponse = try await supabase.client.from("games")
                .select("id")
                .eq("rawg_id", value: game.rawgId)
                .single()
                .execute()
                .value
            
            let gameId = gameRecord.id
                        
            // Cache game description in background (only if not already cached)
            Task {
                do {
                    struct DescCheck: Decodable { let description: String? }
                    let existing: [DescCheck] = try await supabase.client
                        .from("games")
                        .select("description")
                        .eq("rawg_id", value: game.rawgId)
                        .limit(1)
                        .execute()
                        .value
                    
                    // Skip if description already exists
                    if let cached = existing.first?.description, !cached.isEmpty {
                        debugLog("📖 Description already cached for \(game.title), skipping RAWG call")
                        return
                    }
                    
                    let details = try await RAWGService.shared.getGameDetails(id: game.rawgId)
                    if let desc = details.gameDescriptionHtml ?? details.gameDescription, !desc.isEmpty {
                        _ = try? await supabase.client
                            .from("games")
                            .update(["description": desc])
                            .eq("rawg_id", value: game.rawgId)
                            .execute()
                        debugLog("📖 Cached description for \(game.title)")
                    }
                } catch {
                    debugLog("⚠️ Background description cache failed: \(error)")
                }
            }
            
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
                .neq("game_id", value: gameId)
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
            // Save used platforms to UserDefaults
            if !selectedPlatforms.isEmpty {
                Self.saveUsedPlatforms(selectedPlatforms, for: userId)
            }
            // Build prediction context for comparison bias
            if existingUserGames.count >= 6 {
                let _ = await PredictionEngine.shared.refreshContext()
            }

            isLoading = false
            self.savedGameId = gameId
            if existingUserGames.count >= 6,
               let context = PredictionEngine.shared.cachedContext {
                let target = PredictionTarget(
                    rawgId: game.rawgId,
                    canonicalGameId: nil,
                    genres: predictionGenres,
                    tags: predictionTags,
                    metacriticScore: predictionMetacritic
                )
                if let prediction = PredictionEngine.shared.predict(game: target, context: context) {
                    let range = prediction.estimatedRank(inListOf: existingUserGames.count)
                    self.computedPredictedRange = (lower: range.lower, upper: range.upper)
                    debugLog("🎯 Stored computedPredictedRange: ~#\(range.lower)–\(range.upper)")
                }
            }

            if existingUserGames.isEmpty && existingUserGame == nil {
                // First game ever - no comparison needed, save at #1
                await saveUserGame(gameId: gameId, position: 1)
                dismiss()
            } else {
                // Show comparison (either new game with existing list, or re-ranking)
                showComparison = true
            }
            
        } catch {
            debugLog("❌ Error saving game: \(error)")
            
            let errorString = String(describing: error)
            if errorString.contains("duplicate") || errorString.contains("unique") {
                errorMessage = "You've already ranked this one!"
            } else {
                errorMessage = "Couldn't save game: \(error.localizedDescription)"
            }
            
            isLoading = false
        }
    }
    
    // MARK: - Save User Game
        private func saveUserGame(gameId: Int, position: Int) async {
            guard let userId = supabase.currentUser?.id else { return }
            
            do {
                // If re-ranking, use the rerank RPC
                if let existing = existingUserGame {
                    let canonicalId = await RAWGService.shared.getParentGameId(for: game.rawgId) ?? game.rawgId
                    debugLog("🔗 Game: \(game.title), rawgId: \(game.rawgId), canonicalId: \(canonicalId)")
                    
                    try await supabase.client
                        .rpc("rerank_game", params: [
                            "p_user_game_id": AnyJSON.string(existing.id),
                            "p_user_id": AnyJSON.string(userId.uuidString),
                            "p_old_rank": AnyJSON.integer(existing.rank_position),
                            "p_new_rank": AnyJSON.integer(position),
                            "p_game_id": AnyJSON.integer(gameId),
                            "p_platform_played": AnyJSON.array(Array(selectedPlatforms).map { AnyJSON.string($0) }),
                            "p_notes": AnyJSON.string(notes),
                            "p_canonical_game_id": AnyJSON.integer(canonicalId)
                        ])
                        .execute()
                    
                    debugLog("✅ Re-ranked at position \(position)")
                        existingUserGame = nil
                        PredictionEngine.shared.invalidateContext()
                        await WantToPlayManager.shared.removeGameIfPresent(rawgId: game.rawgId)
                    } else {
                    // New game — use insert RPC
                    let canonicalId = await RAWGService.shared.getParentGameId(for: game.rawgId) ?? game.rawgId
                    debugLog("🔗 Game: \(game.title), rawgId: \(game.rawgId), canonicalId: \(canonicalId)")
                    
                    try await supabase.client
                        .rpc("insert_game_at_rank", params: [
                            "p_user_id": AnyJSON.string(userId.uuidString),
                            "p_game_id": AnyJSON.integer(gameId),
                            "p_rank": AnyJSON.integer(position),
                            "p_platform_played": AnyJSON.array(Array(selectedPlatforms).map { AnyJSON.string($0) }),
                            "p_notes": AnyJSON.string(notes),
                            "p_canonical_game_id": AnyJSON.integer(canonicalId),
                            "p_batch_source": AnyJSON.string("manual"),
                            "p_steam_appid": AnyJSON.null,
                            "p_steam_playtime_minutes": AnyJSON.null
                        ])
                        .execute()
                        
                        debugLog("✅ Game logged at position \(position)")
                        PredictionEngine.shared.invalidateContext()
                        await WantToPlayManager.shared.removeGameIfPresent(rawgId: game.rawgId)
                    }
                
            } catch {
                debugLog("❌ Error saving user game: \(error)")
            }
            
            // Silently log prediction accuracy if we had a prediction
            if true {
                await logPredictionAccuracy(gameId: gameId, actualPosition: position, totalGames: existingUserGames.count + 1)
            }
        }
    
    // MARK: - Prediction Logging
    private func logPredictionAccuracy(gameId: Int, actualPosition: Int, totalGames: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        let actualPercentile = (1.0 - (Double(actualPosition - 1) / Double(max(totalGames - 1, 1)))) * 100.0
        
        // Recalculate prediction at rank time for comparison
        guard let context = await PredictionEngine.shared.getContext() else {
            debugLog("📊 Prediction log skipped: no context")
            return
        }
        
        let target = PredictionTarget(
            rawgId: game.rawgId,
            canonicalGameId: nil,
            genres: game.genres,
            tags: game.tags,
            metacriticScore: game.metacriticScore
        )
        
        guard let recalcPrediction = PredictionEngine.shared.predict(game: target, context: context) else {
            debugLog("📊 Prediction log skipped: recalc failed")
            return
        }
        
        // Get the original prediction that was shown to the user
        // We stored the range, so derive the original percentile from the midpoint
        guard let range = computedPredictedRange else { return }
        let originalMidpoint = Double(range.lower + range.upper) / 2.0
        let originalPercentile = (1.0 - (originalMidpoint - 1.0) / Double(max(totalGames - 1, 1))) * 100.0
        
        // We don't have the original confidence/tiers stored separately,
        // so use recalc values as approximation for original
        // (In practice these are very close since ranking just happened)
        
        struct PredictionLogInsert: Encodable {
            let user_id: String
            let game_id: Int
            let original_percentile: Double
            let original_confidence: Int
            let original_tiers: [String]
            let original_created_at: String
            let recalc_percentile: Double
            let recalc_confidence: Int
            let recalc_tiers: [String]
            let actual_percentile: Double
            let source: String
            let days_between_prediction_and_rank: Int
        }
        
        let log = PredictionLogInsert(
            user_id: userId.uuidString,
            game_id: gameId,
            original_percentile: originalPercentile,
            original_confidence: recalcPrediction.confidence,
            original_tiers: recalcPrediction.tiersUsed,
            original_created_at: ISO8601DateFormatter().string(from: Date()),
            recalc_percentile: recalcPrediction.predictedPercentile,
            recalc_confidence: recalcPrediction.confidence,
            recalc_tiers: recalcPrediction.tiersUsed,
            actual_percentile: actualPercentile,
            source: source,
            days_between_prediction_and_rank: 0
        )
        
        do {
            try await supabase.client
                .from("prediction_logs")
                .insert(log)
                .execute()
            
            let originalDelta = abs(originalPercentile - actualPercentile)
            let recalcDelta = abs(recalcPrediction.predictedPercentile - actualPercentile)
            debugLog("📊 Prediction logged: original=\(Int(originalPercentile))%, recalc=\(Int(recalcPrediction.predictedPercentile))%, actual=\(Int(actualPercentile))%, originalΔ=\(Int(originalDelta))%, recalcΔ=\(Int(recalcDelta))%")
        } catch {
            debugLog("⚠️ Failed to log prediction: \(error)")
        }
    }
}

// MARK: - Platform Picker Sheet
struct PlatformPickerSheet: View {
    @Binding var selectedPlatforms: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var customPlatform: String = ""
    @State private var customError: String?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(GameLogView.allPlatforms, id: \.self) { platform in
                        Button {
                            if selectedPlatforms.contains(platform) {
                                selectedPlatforms.remove(platform)
                            } else {
                                selectedPlatforms.insert(platform)
                            }
                        } label: {
                            HStack {
                                Text(platform)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                                Spacer()
                                if selectedPlatforms.contains(platform) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.primaryBlue)
                                        .font(.system(size: 20))
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundStyle(Color.adaptiveSilver)
                                        .font(.system(size: 20))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Custom Platform") {
                    HStack(spacing: 10) {
                        TextField("Other platform...", text: $customPlatform)
                            .font(.system(size: 14, design: .rounded))
                        
                        Button {
                            let trimmed = customPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let result = ContentModerator.shared.checkUsername(trimmed)
                            if !result.allowed {
                                customError = "Platform name contains inappropriate language."
                                return
                            }
                            selectedPlatforms.insert(trimmed)
                            customPlatform = ""
                            customError = nil
                        } label: {
                            Text("Add")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.adaptiveSilver : Color.primaryBlue)
                                .cornerRadius(8)
                        }
                        .disabled(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if let error = customError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.error)
                    }
                    
                    let customSelections = selectedPlatforms.filter { !GameLogView.allPlatforms.contains($0) }
                    if !customSelections.isEmpty {
                        ForEach(Array(customSelections).sorted(), id: \.self) { platform in
                            HStack {
                                Text(platform)
                                    .font(.system(size: 16, design: .rounded))
                                    .foregroundStyle(Color.adaptiveSlate)
                                Spacer()
                                Button {
                                    selectedPlatforms.remove(platform)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.7))
                                        .font(.system(size: 20))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("All Platforms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.primaryBlue)
                }
            }
        }
    }
}

// MARK: - Platform Button
struct PlatformButton: View {
    let platform: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(platform)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : .slate)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.primaryBlue : Color.secondaryBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primaryBlue : Color.adaptiveSilver, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ExistingUserGame: Decodable {
    let id: String
    let rank_position: Int
}

// MARK: - Flow Layout
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    GameLogView(game: Game(
        from: RAWGGame(
            id: 1,
            name: "The Legend of Zelda: Breath of the Wild",
            backgroundImage: nil,
            released: "2017-03-03",
            metacritic: 97,
            genres: [RAWGGenre(id: 1, name: "Action")],
            platforms: [RAWGPlatformWrapper(platform: RAWGPlatform(id: 1, name: "Nintendo Switch"))],
            added: nil,
            rating: nil,
            descriptionRaw: nil,
            descriptionHtml: nil,
            tags: nil
        )
    ))
}
