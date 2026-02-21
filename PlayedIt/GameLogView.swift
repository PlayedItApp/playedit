import SwiftUI
import Supabase

struct GameLogView: View {
    let game: Game
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
    
    static let allPlatforms = [
        "PC", "PlayStation 5", "PlayStation 4", "PlayStation 3",
        "Xbox Series S/X", "Xbox One", "Xbox 360",
        "Nintendo Switch", "Nintendo 64", "Wii U", "Wii", "Nintendo 3DS",
        "iOS", "Android", "macOS", "Linux"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Game Header
                    HStack(spacing: 16) {
                        AsyncImage(url: URL(string: game.coverURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
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
                            ForEach(Self.allPlatforms, id: \.self) { platform in
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
                        
                        // Custom platform
                        HStack(spacing: 10) {
                            TextField("Other platform...", text: $customPlatform)
                                .font(.system(size: 14, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.secondaryBackground)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.adaptiveSilver, lineWidth: 1)
                                )
                            
                            Button {
                                let trimmed = customPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                let result = ContentModerator.shared.checkUsername(trimmed)
                                if !result.allowed {
                                    errorMessage = "Platform name contains inappropriate language."
                                    return
                                }
                                selectedPlatforms.insert(trimmed)
                                customPlatform = ""
                            } label: {
                                Text("Add")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.adaptiveSilver : Color.primaryBlue)
                                    .cornerRadius(8)
                            }
                            .disabled(customPlatform.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        // Show custom selections that aren't in the grid
                        let customSelections = selectedPlatforms.filter { !Self.allPlatforms.contains($0) }
                        if !customSelections.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(Array(customSelections).sorted(), id: \.self) { platform in
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
            .sheet(isPresented: $showComparison) {
                if let gameId = savedGameId {
                    ComparisonView(
                        newGame: game,
                        existingGames: existingUserGames,
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
                let release_date: String
                let metacritic_score: Int
                let tags: [String]
            }
            
            // Fetch tags from RAWG detail endpoint (search results don't include them)
            var gameTags = game.tags
            if gameTags.isEmpty {
                if let details = try? await RAWGService.shared.getGameDetails(id: game.rawgId) {
                    gameTags = details.tags
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
            gameTags = gameTags.filter { tag in
                !excludedTags.contains(tag) &&
                tag.allSatisfy { $0.isASCII || $0 == " " || $0 == "-" }
            }
            
            let gameInsert = GameInsert(
                rawg_id: game.rawgId,
                title: game.title,
                cover_url: game.coverURL ?? "",
                genres: game.genres,
                platforms: game.platforms,
                release_date: game.releaseDate ?? "",
                metacritic_score: game.metacriticScore ?? 0,
                tags: gameTags
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
                        
            // Cache game description in background
            Task {
                do {
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
            
            isLoading = false
            self.savedGameId = gameId
            
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
            // If re-ranking, delete the old entry first and adjust positions
            if let existing = existingUserGame {
                // Delete the old entry
                try await supabase.client
                    .from("user_games")
                    .delete()
                    .eq("id", value: existing.id)
                    .execute()
                
                // Shift games that were below the old position up by 1
                struct GameToShiftUp: Decodable {
                    let id: String
                    let rank_position: Int
                }
                
                let gamesToShiftUp: [GameToShiftUp] = try await supabase.client
                    .from("user_games")
                    .select("id, rank_position")
                    .eq("user_id", value: userId.uuidString)
                    .not("rank_position", operator: .is, value: "null")
                    .gt("rank_position", value: existing.rank_position)
                    .execute()
                    .value
                for game in gamesToShiftUp {
                    try await supabase.client
                        .from("user_games")
                        .update(["rank_position": game.rank_position - 1])
                        .eq("id", value: game.id)
                        .execute()
                }
                
                debugLog("✅ Deleted old entry at position \(existing.rank_position)")
                existingUserGame = nil
            }
            
            // Now shift games at or below the new position down by 1
            struct GameToShift: Decodable {
                let id: String
                let rank_position: Int
            }
            
            let gamesToShift: [GameToShift] = try await supabase.client
                .from("user_games")
                .select("id, rank_position")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .gte("rank_position", value: position)
                .order("rank_position", ascending: false)
                .execute()
                .value
            
            for game in gamesToShift {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": game.rank_position + 1])
                    .eq("id", value: game.id)
                    .execute()
            }
            
            // Resolve canonical game ID
            let canonicalId = await RAWGService.shared.getParentGameId(for: game.rawgId) ?? game.rawgId
            debugLog("🔗 Game: \(game.title), rawgId: \(game.rawgId), canonicalId: \(canonicalId)")
            
            // Insert the new entry
            struct UserGameInsert: Encodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let platform_played: [String]
                let notes: String
                let canonical_game_id: Int
            }
            
            let userGameInsert = UserGameInsert(
                user_id: userId.uuidString,
                game_id: gameId,
                rank_position: position,
                platform_played: selectedPlatforms.isEmpty ? [] : Array(selectedPlatforms),
                notes: notes,
                canonical_game_id: canonicalId
            )
            
            try await supabase.client.from("user_games")
                .insert(userGameInsert)
                .execute()
            
            debugLog("✅ Game logged at position \(position)")
            
        } catch {
            debugLog("❌ Error saving user game: \(error)")
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
