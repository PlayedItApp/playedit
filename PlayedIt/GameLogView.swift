import SwiftUI
import Supabase

struct GameLogView: View {
    let game: Game
    @Environment(\.dismiss) var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var selectedPlatforms: Set<String> = []
    @State private var notes: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showComparison = false
    @State private var savedGameId: Int?
    @State private var existingUserGames: [UserGame] = []
    @State private var existingUserGame: ExistingUserGame? = nil
    @State private var showReRankAlert = false
    
    // Platform options based on what the game supports
    var availablePlatforms: [String] {
        game.platforms.isEmpty ? Self.allPlatforms : game.platforms
    }
    
    static let allPlatforms = [
        "PC", "PlayStation 5", "PlayStation 4", "PlayStation 3",
        "Xbox Series S/X", "Xbox One", "Xbox 360",
        "Nintendo Switch", "Wii U", "Wii", "Nintendo 3DS",
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
                                .fill(Color.lightGray)
                                .overlay(
                                    Image(systemName: "gamecontroller")
                                        .foregroundColor(.silver)
                                )
                        }
                        .frame(width: 80, height: 107)
                        .cornerRadius(8)
                        .clipped()
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.title)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.slate)
                                .lineLimit(2)
                            
                            if let year = game.releaseDate?.prefix(4) {
                                Text(String(year))
                                    .font(.subheadline)
                                    .foregroundColor(.grayText)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    // Platform Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Where'd you play it?")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        
                        Text("Select all that apply")
                            .font(.caption)
                            .foregroundColor(.grayText)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 10) {
                            ForEach(availablePlatforms, id: \.self) { platform in
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
                    }
                    .padding(.horizontal, 20)
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Any thoughts?")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
                        
                        TextEditor(text: $notes)
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
                                    if notes.isEmpty {
                                        Text("Favorite moments? Hot takes? (optional)")
                                            .foregroundColor(.grayText)
                                            .padding(.leading, 16)
                                            .padding(.top, 20)
                                    }
                                },
                                alignment: .topLeading
                            )
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
                    .foregroundColor(selectedPlatforms.isEmpty ? .gray : .primaryBlue)
                    .disabled(selectedPlatforms.isEmpty || isLoading)
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
                .execute()
                .value
            
            if let existing = response.first {
                existingUserGame = existing
                showReRankAlert = true
            }
        } catch {
            print("Failed to check existing game: \(error)")
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
        
        do {
            struct GameInsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String
                let metacritic_score: Int
            }
            
            let gameInsert = GameInsert(
                rawg_id: game.rawgId,
                title: game.title,
                cover_url: game.coverURL ?? "",
                genres: game.genres,
                platforms: game.platforms,
                release_date: game.releaseDate ?? "",
                metacritic_score: game.metacriticScore ?? 0
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
                .neq("game_id", value: gameId)
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
            print("❌ Error saving game: \(error)")
            
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
                
                print("✅ Deleted old entry at position \(existing.rank_position)")
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
            print("🔗 Game: \(game.title), rawgId: \(game.rawgId), canonicalId: \(canonicalId)")
            
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
                platform_played: Array(selectedPlatforms),
                notes: notes,
                canonical_game_id: canonicalId
            )
            
            try await supabase.client.from("user_games")
                .insert(userGameInsert)
                .execute()
            
            print("✅ Game logged at position \(position)")
            
        } catch {
            print("❌ Error saving user game: \(error)")
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
                        .fill(isSelected ? Color.primaryBlue : Color.lightGray)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.primaryBlue : Color.silver, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ExistingUserGame: Decodable {
    let id: String
    let rank_position: Int
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
            rating: nil
        )
    ))
}
