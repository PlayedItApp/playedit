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
        }
    }
    
    private func saveGame() async {
        guard let userId = supabase.currentUser?.id else {
            errorMessage = "Not logged in"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // First, make sure the game exists in our games table
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
            
            // Get the game's ID from our database
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
            
            // Fetch existing ranked games for comparison
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
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            // Convert to UserGame
            existingUserGames = rows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date
                )
            }
            
            isLoading = false
            
            // Store game ID for later
            self.savedGameId = gameId
            
            if existingUserGames.isEmpty {
                // First game - no comparison needed, just save at #1
                await saveUserGame(gameId: gameId, position: 1)
                dismiss()
            } else {
                // Show comparison flow
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
    
    private func saveUserGame(gameId: Int, position: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            // Get all games at or below the new position
            struct RankUpdate: Encodable {
                let rank_position: Int
            }
            
            // First, get games that need to shift
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
            
            // Shift each one down (starting from bottom to avoid conflicts)
            for game in gamesToShift {
                try await supabase.client
                    .from("user_games")
                    .update(["rank_position": game.rank_position + 1])
                    .eq("id", value: game.id)
                    .execute()
            }
            
            // Save the user's game entry
            struct UserGameInsert: Encodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let platform_played: [String]
                let notes: String
            }
            
            let userGameInsert = UserGameInsert(
                user_id: userId.uuidString,
                game_id: gameId,
                rank_position: position,
                platform_played: Array(selectedPlatforms),
                notes: notes
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

#Preview {
    GameLogView(game: Game(
        from: RAWGGame(
            id: 1,
            name: "The Legend of Zelda: Breath of the Wild",
            backgroundImage: nil,
            released: "2017-03-03",
            metacritic: 97,
            genres: [RAWGGenre(id: 1, name: "Action")],
            platforms: [RAWGPlatformWrapper(platform: RAWGPlatform(id: 1, name: "Nintendo Switch"))]
        )
    ))
}
