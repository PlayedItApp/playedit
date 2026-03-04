import SwiftUI
import Supabase

struct OnboardingRankingFlowView: View {
    let games: [OnboardingGame]
    let onComplete: () -> Void
    
    @EnvironmentObject var supabase: SupabaseManager
    @State private var currentIndex = 0
    @State private var existingUserGames: [UserGame] = []
    @State private var showComparison = false
    @State private var currentGameId: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private var currentGame: OnboardingGame? {
        guard currentIndex < games.count else { return nil }
        return games[currentIndex]
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Progress
                VStack(spacing: 8) {
                    Text("Ranking your games")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text("Game \(max(currentIndex, 1)) of \(games.count)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                    
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondaryBackground)
                                .frame(height: 8)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primaryBlue)
                                .frame(width: geometry.size.width * CGFloat(currentIndex) / CGFloat(max(games.count, 1)), height: 8)
                                .animation(.easeInOut, value: currentIndex)
                        }
                    }
                    .frame(height: 8)
                    .padding(.horizontal, 40)
                }
                .padding(.top, 20)
                
                if let game = currentGame {
                    // Current game card
                    VStack(spacing: 12) {
                        CachedAsyncImage(url: game.coverUrl) {
                            Rectangle()
                                .fill(Color.secondaryBackground)
                                .overlay(
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.adaptiveSilver)
                                )
                        }
                        .frame(width: 160, height: 200)
                        .clipped()
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        
                        Text(game.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                            .multilineTextAlignment(.center)
                    }
                    
                    if isSaving {
                        ProgressView("Saving...")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.error)
                    }
                }
                
                Spacer()
            }
            .task {
                await processCurrentGame()
            }
            .sheet(isPresented: $showComparison) {
                if let gameId = currentGameId, let game = currentGame {
                    ComparisonView(
                        newGame: game.toGame(),
                        existingGames: existingUserGames,
                        skipCelebration: true,
                        hideCancel: true,
                        onComplete: { position in
                            Task {
                                await saveUserGame(gameId: gameId, position: position)
                                await moveToNext()
                            }
                        }
                    )
                    .interactiveDismissDisabled()
                }
            }
        }
    }
    
    // MARK: - Process Current Game
    private func processCurrentGame() async {
        debugLog("🎯 processCurrentGame: index=\(currentIndex), total=\(games.count)")
        guard let game = currentGame else {
            debugLog("🎯 No more games, calling onComplete")
            if let userId = supabase.currentUser?.id {
                _ = try? await supabase.client
                    .rpc("renormalize_ranks", params: [
                        "p_user_id": AnyJSON.string(userId.uuidString)
                    ])
                    .execute()
            }
            onComplete()
            return
        }
        
        guard let userId = supabase.currentUser?.id else { return }
        
        isSaving = true
        errorMessage = nil
        
        struct GameIdResponse: Decodable {
            let id: Int
        }
        
        do {
            // 1. Upsert game into games table
            struct GameInsert: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String
                let genres: [String]
                let platforms: [String]
                let release_date: String?
                let metacritic_score: Int
            }
            
            let gameInsert = GameInsert(
                rawg_id: game.rawgId,
                title: game.title,
                cover_url: game.coverUrl ?? "",
                genres: game.genres,
                platforms: game.platforms,
                release_date: game.releaseDate,
                metacritic_score: game.metacritic ?? 0
            )
            
            // Try insert first, ignore conflict if game already exists
            do {
                try await supabase.client.from("games")
                    .upsert(gameInsert, onConflict: "rawg_id")
                    .execute()
            } catch {
                debugLog("⚠️ Game upsert failed, trying to fetch existing: \(error)")
                // Game might already exist, that's fine — we'll fetch it below
            }
            
        var gameRecords: [GameIdResponse] = try await supabase.client.from("games")
                        .select("id")
                        .eq("rawg_id", value: game.rawgId)
                        .limit(1)
                        .execute()
                        .value
                    
                    // If game doesn't exist in DB, fetch from RAWG and insert
                    if gameRecords.isEmpty {
                        debugLog("🔍 Game not in DB, fetching from RAWG: \(game.title) (rawg_id: \(game.rawgId))")
                        let rawgGame = try await RAWGService.shared.getGameDetails(id: game.rawgId)
                        
                        struct GameInsertFallback: Encodable {
                            let rawg_id: Int
                            let title: String
                            let cover_url: String
                            let genres: [String]
                            let platforms: [String]
                            let release_date: String?
                            let metacritic_score: Int
                        }
                        
                        let fallbackInsert = GameInsertFallback(
                            rawg_id: rawgGame.rawgId,
                            title: rawgGame.title,
                            cover_url: rawgGame.coverURL ?? "",
                            genres: rawgGame.genres,
                            platforms: rawgGame.platforms,
                            release_date: rawgGame.releaseDate,
                            metacritic_score: rawgGame.metacriticScore ?? 0
                        )
                        
                        try await supabase.client.from("games")
                            .insert(fallbackInsert)
                            .execute()
                        
                        gameRecords = try await supabase.client.from("games")
                            .select("id")
                            .eq("rawg_id", value: game.rawgId)
                            .limit(1)
                            .execute()
                            .value
                    }
                    
                    guard let gameRecord = gameRecords.first else {
                        debugLog("⚠️ Still can't find game after RAWG fetch, skipping: \(game.title)")
                        isSaving = false
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        await moveToNext()
                        return
                    }
            
            let gameId = gameRecord.id
            currentGameId = gameId
            
            // 3. Fetch existing ranked games for comparison
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
            
            isSaving = false
                        
            if existingUserGames.isEmpty {
                // Silently save first game and immediately move to second
                // User's first comparison will be game 2 vs game 1
                await saveUserGame(gameId: gameId, position: 1)
                isSaving = false
                await moveToNext()
            } else {
                showComparison = true
            }
            
        } catch {
            debugLog("❌ Error processing game: \(error)")
            errorMessage = "Something went wrong. Skipping..."
            isSaving = false
            
            // Skip to next after a delay
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await moveToNext()
        }
    }
    
    // MARK: - Save User Game
    
    private func saveUserGame(gameId: Int, position: Int) async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            let canonicalId = await RAWGService.shared.getParentGameId(for: currentGame?.rawgId ?? gameId) ?? gameId
            
            try await supabase.client
                .rpc("insert_game_at_rank", params: [
                    "p_user_id": AnyJSON.string(userId.uuidString),
                    "p_game_id": AnyJSON.integer(gameId),
                    "p_rank": AnyJSON.integer(position),
                    "p_platform_played": AnyJSON.array([]),
                    "p_notes": AnyJSON.string(""),
                    "p_canonical_game_id": AnyJSON.integer(canonicalId),
                    "p_batch_source": AnyJSON.string("onboarding"),
                    "p_steam_appid": AnyJSON.null,
                    "p_steam_playtime_minutes": AnyJSON.null
                ])
                .execute()
            
            debugLog("✅ Onboarding: \(currentGame?.title ?? "Unknown") ranked at #\(position)")
            
        } catch {
            debugLog("❌ Error saving user game during onboarding: \(error)")
        }
    }
    
    // MARK: - Move to Next
    
    @MainActor
    private func moveToNext() async {
        showComparison = false
        currentIndex += 1
        debugLog("🎯 moveToNext: now at index \(currentIndex) of \(games.count)")
        
        if currentIndex >= games.count {
            // Safety net: renormalize in case any gaps occurred
            if let userId = supabase.currentUser?.id {
                _ = try? await supabase.client
                    .rpc("renormalize_ranks", params: [
                        "p_user_id": AnyJSON.string(userId.uuidString)
                    ])
                    .execute()
            }
            // All done!
            onComplete()
        } else {
            // Small delay between games
            try? await Task.sleep(nanoseconds: 300_000_000)
            await processCurrentGame()
        }
    }
}

#Preview {
    OnboardingRankingFlowView(
        games: [],
        onComplete: {}
    )
}
