import Foundation
import Supabase
import Combine

// MARK: - Recommendation Model

struct Recommendation: Identifiable, Codable {
    let id: Int64
    let userId: String
    let gameId: Int
    let source: String
    let sourceFriendId: String?
    let predictedPercentile: Double
    let predictedSummary: String
    let confidence: Int
    let tiersUsed: [String]
    let action: String
    let dismissReason: String?
    let actualRankPosition: Int?
    let actualPercentile: Double?
    let predictionAccuracy: Double?
    let recommendedAt: String?
    let actedAt: String?
    let rankedAt: String?
    let dismissedUntil: String?
    let roundNumber: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gameId = "game_id"
        case source
        case sourceFriendId = "source_friend_id"
        case predictedPercentile = "predicted_percentile"
        case predictedSummary = "predicted_summary"
        case confidence
        case tiersUsed = "tiers_used"
        case action
        case dismissReason = "dismiss_reason"
        case actualRankPosition = "actual_rank_position"
        case actualPercentile = "actual_percentile"
        case predictionAccuracy = "prediction_accuracy"
        case recommendedAt = "recommended_at"
        case actedAt = "acted_at"
        case rankedAt = "ranked_at"
        case dismissedUntil = "dismissed_until"
        case roundNumber = "round_number"
    }
}

// MARK: - Display model (joins recommendation + game info)

struct RecommendationDisplay: Identifiable {
    let id: Int64
    let recommendation: Recommendation
    let gameTitle: String
    let gameCoverUrl: String?
    let gameRawgId: Int
    let genres: [String]
    let platforms: [String]?
    let prediction: GamePrediction
    let sourceFriendName: String?
    let sourceFriendRankPosition: Int?
    let sourceFriendTotalGames: Int?
}

// MARK: - Recommendation Manager

class RecommendationManager: ObservableObject {
    static let shared = RecommendationManager()
    
    @Published var recommendations: [RecommendationDisplay] = []
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    
    private let supabase = SupabaseManager.shared
    
    // MARK: - Fetch Pending Recommendations
    
    func fetchPending() async -> [Recommendation] {
        guard let userId = supabase.currentUser?.id else { return [] }
        
        do {
            let recs: [Recommendation] = try await supabase.client
                .from("recommendations")
                .select("*")
                .eq("user_id", value: userId.uuidString)
                .eq("action", value: "pending")
                .order("predicted_percentile", ascending: false)
                .execute()
                .value
            
            return recs
        } catch {
            debugLog("❌ Error fetching recommendations: \(error)")
            return []
        }
    }
    
    // MARK: - Generate Recommendations (full flow)
    
    func generateRecommendations() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        isGenerating = true
        defer { isGenerating = false }
        
        // 1. Get current round number and expire pending recs
        var currentRound = 1
        do {
            struct MaxRound: Decodable { let round_number: Int? }
            let rows: [MaxRound] = try await supabase.client
                .from("recommendations")
                .select("round_number")
                .eq("user_id", value: userId.uuidString)
                .order("round_number", ascending: false)
                .limit(1)
                .execute()
                .value
            currentRound = (rows.first?.round_number ?? 0) + 1
        } catch {
            debugLog("⚠️ Error fetching max round: \(error)")
        }
        
        do {
            struct ExpireUpdate: Encodable { let action: String }
            try await supabase.client
                .from("recommendations")
                .update(ExpireUpdate(action: "expired"))
                .eq("user_id", value: userId.uuidString)
                .eq("action", value: "pending")
                .execute()
        } catch {
            debugLog("⚠️ Error expiring pending recommendations: \(error)")
        }
        
        let slotsToFill = 10
        debugLog("🎯 Starting round \(currentRound)")
        
        // 2. Build exclusion set
        let excludedGameIds = await buildExclusionSet(userId: userId.uuidString, existingPendingIds: Set(), currentRound: currentRound)
        
        // 2b. Build ranked title set for variant detection
        var rankedBaseTitles: Set<String> = []
        do {
            struct RankedTitle: Decodable { let id: Int; let title: String }
            let gameIds = excludedGameIds // already contains ranked game_ids
            let titles: [RankedTitle] = try await supabase.client
                .from("games")
                .select("id, title")
                .in("id", values: Array(gameIds))
                .execute()
                .value
            rankedBaseTitles = Set(titles.map { baseTitle($0.title) })
            debugLog("🎯 Ranked base titles (\(rankedBaseTitles.count)): \(rankedBaseTitles.sorted().prefix(20))")
        } catch {
            debugLog("⚠️ Error building ranked titles: \(error)")
        }
        
        // 3. Build owned platforms set (platforms with 2+ ranked games)
        let ownedPlatforms = await buildOwnedPlatforms(userId: userId.uuidString)
        debugLog("🎯 Owned platforms: \(ownedPlatforms)")
        
        // 4. Build prediction context
        guard let context = await PredictionEngine.shared.getContext() else {
            await buildDisplayList()
            return
        }
        
        debugLog("🎯 Building recommendations. Slots to fill: \(slotsToFill)")
        debugLog("🎯 Excluded game IDs: \(excludedGameIds.count)")
        debugLog("🎯 Context: \(context.myGames.count) games, \(context.friends.count) friends")
        for friend in context.friends {
            debugLog("   🤝 \(friend.username): \(friend.tasteMatch)% taste match, \(friend.games.count) games")
        }
        
        // 5. Gather candidates from all sources
        var candidates: [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] = []
        
        // Source 1: Friend-ranked games (70%+ taste match, top 50%)
        let friendCandidates = await gatherFriendCandidates(context: context, excludedIds: excludedGameIds, ownedPlatforms: ownedPlatforms, rankedBaseTitles: rankedBaseTitles)
        candidates.append(contentsOf: friendCandidates)
        
        // Source 2: PlayedIt games table (genre/tag discovery)
        let genreCandidates = await gatherGenreCandidates(context: context, excludedIds: excludedGameIds.union(Set(candidates.map { $0.gameId })), ownedPlatforms: ownedPlatforms, rankedBaseTitles: rankedBaseTitles)
        candidates.append(contentsOf: genreCandidates)
        
        // Source 3: RAWG API discovery (always run for fresh games)
        let rawgCandidates = await gatherRAWGCandidates(context: context, excludedIds: excludedGameIds.union(Set(candidates.map { $0.gameId })), ownedPlatforms: ownedPlatforms, rankedBaseTitles: rankedBaseTitles)
        candidates.append(contentsOf: rawgCandidates)
        
        debugLog("🎯 Pre-filter — Friend: \(friendCandidates.count), Genre: \(genreCandidates.count), RAWG: \(rawgCandidates.count)")
        
        // 6. Score all candidates through PredictionEngine
        var scoredCandidates: [(candidate: (gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?), prediction: GamePrediction)] = []
        
        for candidate in candidates {
            let target = PredictionTarget(
                rawgId: candidate.rawgId,
                canonicalGameId: nil,
                genres: candidate.genres,
                tags: candidate.tags,
                metacriticScore: candidate.metacritic
            )
            
            if let pred = PredictionEngine.shared.predict(game: target, context: context) {
                scoredCandidates.append((candidate: candidate, prediction: pred))
            }
        }
        
        debugLog("🎯 Total scored candidates: \(scoredCandidates.count)")
        for sc in scoredCandidates.sorted(by: { $0.prediction.predictedPercentile > $1.prediction.predictedPercentile }).prefix(15) {
            let p = sc.prediction
            let genreStr = p.topGenreAffinity.map { "genre=\(Int($0))%" } ?? "genre=n/a"
            let tagStr = p.topTagAffinity.map { "tag=\(Int($0))%" } ?? "tag=n/a"
            let friendStr = p.friendSignals.isEmpty ? "friends=none" : "friends=\(p.friendSignals.map { "\($0.friendName)(\(Int($0.friendRankPercentile))%)" }.joined(separator: ","))"
            debugLog("   🔮 \(sc.candidate.title): \(Int(p.predictedPercentile))% [\(sc.candidate.source)] | \(genreStr) \(tagStr) \(friendStr) | tiers=\(p.tiersUsed) conf=\(p.confidenceLabel)")
        }
        
        // 7. Only show "You'll love this" tier (65%+)
        scoredCandidates = scoredCandidates.filter { $0.prediction.predictedPercentile >= 65 }
        scoredCandidates.sort {
        if $0.prediction.confidence != $1.prediction.confidence {
            return $0.prediction.confidence > $1.prediction.confidence
        }
        return $0.prediction.predictedPercentile > $1.prediction.predictedPercentile
    }
        let topCandidates = Array(scoredCandidates.prefix(slotsToFill))
        
        // 8. Insert into Supabase
        for item in topCandidates {
            let c = item.candidate
            let p = item.prediction
            
            struct Insert: Encodable {
                let user_id: String
                let game_id: Int
                let source: String
                let source_friend_id: String?
                let predicted_percentile: Double
                let predicted_summary: String
                let confidence: Int
                let tiers_used: [String]
                let round_number: Int
            }
            
            do {
                try await supabase.client
                    .from("recommendations")
                    .upsert(Insert(
                        user_id: userId.uuidString,
                        game_id: c.gameId,
                        source: c.source,
                        source_friend_id: c.sourceFriendId,
                        predicted_percentile: p.predictedPercentile,
                        predicted_summary: p.summaryText,
                        confidence: p.confidence,
                        tiers_used: p.tiersUsed,
                        round_number: currentRound
                    ))
                    .execute()
            } catch {
                debugLog("⚠️ Error inserting recommendation for \(c.title): \(error)")
            }
        }
        
        // 9. Build display list
        await buildDisplayList()
    }
    
    // MARK: - Build Owned Platforms
    private func buildOwnedPlatforms(userId: String) async -> Set<String> {
        do {
            struct PlatformRow: Decodable { let platform_played: [String] }
            let rows: [PlatformRow] = try await supabase.client
                .from("user_games")
                .select("platform_played")
                .eq("user_id", value: userId)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            
            var counts: [String: Int] = [:]
            for row in rows {
                for platform in row.platform_played {
                    counts[platform, default: 0] += 1
                }
            }
            
            return Set(counts.filter { $0.value >= 2 }.map { $0.key })
        } catch {
            debugLog("⚠️ Error building owned platforms: \(error)")
            return []
        }
    }
    
    // MARK: - Title Variant Detection
        private static let titleSuffixes = [" Remastered", " Remake", " Definitive Edition", " HD Collection", " HD Remaster", " HD", " Game of the Year Edition", " GOTY Edition", " Director's Cut", " Royal Edition", " Complete Edition", " Ultimate Edition", " Enhanced Edition", " Special Edition", " Part I"]
        
        private func baseTitle(_ title: String) -> String {
            var t = title
            for suffix in Self.titleSuffixes {
                if t.lowercased().hasSuffix(suffix.lowercased()) {
                    t = String(t.dropLast(suffix.count))
                    break
                }
            }
            return t.lowercased().trimmingCharacters(in: .whitespaces)
        }
    
    // MARK: - Build Exclusion Set
    private func buildExclusionSet(userId: String, existingPendingIds: Set<Int>, currentRound: Int) async -> Set<Int> {
        var excluded = existingPendingIds
        
        do {
            // Games user has already ranked
            struct RankedRow: Decodable { let game_id: Int }
            let ranked: [RankedRow] = try await supabase.client
                .from("user_games")
                .select("game_id")
                .eq("user_id", value: userId)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            excluded.formUnion(ranked.map { $0.game_id })
            
            // Games on Want to Play list
            struct WTPRow: Decodable { let game_id: Int }
            let wtp: [WTPRow] = try await supabase.client
                .from("want_to_play")
                .select("game_id")
                .eq("user_id", value: userId)
                .execute()
                .value
            excluded.formUnion(wtp.map { $0.game_id })
            
            // Actively dismissed recommendations (dismissed_until > now)
            struct DismissedRow: Decodable { let game_id: Int }
            let dismissed: [DismissedRow] = try await supabase.client
                .from("recommendations")
                .select("game_id")
                .eq("user_id", value: userId)
                .eq("action", value: "dismissed")
                .gt("dismissed_until", value: ISO8601DateFormatter().string(from: Date()))
                .execute()
                .value
            excluded.formUnion(dismissed.map { $0.game_id })
                        
            // Recently recommended games (last 5 rounds)
            struct RecentRecRow: Decodable { let game_id: Int }
            let recentRecs: [RecentRecRow] = try await supabase.client
                .from("recommendations")
                .select("game_id")
                .eq("user_id", value: userId)
                .gte("round_number", value: max(1, currentRound - 5))
                .execute()
                .value
            excluded.formUnion(recentRecs.map { $0.game_id })
            
        } catch {
            debugLog("⚠️ Error building exclusion set: \(error)")
        }
        
        return excluded
    }
    
    // MARK: - Source 1: Friend Candidates
    
    private func gatherFriendCandidates(context: PredictionContext, excludedIds: Set<Int>, ownedPlatforms: Set<String>, rankedBaseTitles: Set<String>) async -> [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] {
        var candidates: [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] = []
        
        // Only friends with 70%+ taste match
        let qualifyingFriends = context.friends.filter { $0.tasteMatch >= 70 }
        
        // Collect all candidate (gameId, friend metadata) pairs without querying yet
        struct PendingCandidate {
            let gameId: Int
            let friendUserId: String
            let friendUsername: String
            let friendRank: Int
            let friendTotal: Int
        }
        var seen: Set<Int> = []
        var pending: [PendingCandidate] = []

        for friend in qualifyingFriends {
            let topHalfCount = max(1, friend.games.count / 2)
            let topGames = friend.games.sorted { $0.rankPosition < $1.rankPosition }.prefix(topHalfCount)
            for friendGame in topGames {
                guard !excludedIds.contains(friendGame.gameId) else { continue }
                guard seen.insert(friendGame.gameId).inserted else { continue }
                pending.append(PendingCandidate(
                    gameId: friendGame.gameId,
                    friendUserId: friend.userId,
                    friendUsername: friend.username,
                    friendRank: friendGame.rankPosition,
                    friendTotal: friend.games.count
                ))
            }
        }

        guard !pending.isEmpty else { return [] }

        // Single batch query for all candidate game details
        struct GameInfo: Decodable {
            let id: Int
            let rawg_id: Int
            let title: String
            let cover_url: String?
            let genres: [String]?
            let tags: [String]?
            let curated_genres: [String]?
            let curated_tags: [String]?
            let curated_platforms: [String]?
            let metacritic_score: Int?
        }

        do {
            let allGameIds = pending.map { $0.gameId }
            let infos: [GameInfo] = try await supabase.client
                .from("games")
                .select("id, rawg_id, title, cover_url, genres, tags, curated_genres, curated_tags, curated_platforms, metacritic_score")
                .in("id", values: allGameIds)
                .execute()
                .value

            let infoMap = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })

            for p in pending {
                guard let info = infoMap[p.gameId] else { continue }

                let candidateBase = baseTitle(info.title)
                if rankedBaseTitles.contains(candidateBase) {
                    debugLog("🚫 Skipping variant: \(info.title) → base: \(candidateBase)")
                    continue
                }

                guard let curatedPlats = info.curated_platforms, !curatedPlats.isEmpty else { continue }
                if !ownedPlatforms.isEmpty {
                    guard !Set(curatedPlats).intersection(ownedPlatforms).isEmpty else { continue }
                }

                candidates.append((
                    gameId: info.id,
                    rawgId: info.rawg_id,
                    title: info.title,
                    coverUrl: info.cover_url,
                    genres: info.curated_genres ?? info.genres ?? [],
                    tags: info.curated_tags ?? info.tags ?? [],
                    metacritic: info.metacritic_score,
                    source: "friend_ranked",
                    sourceFriendId: p.friendUserId,
                    sourceFriendName: p.friendUsername,
                    sourceFriendRank: p.friendRank,
                    sourceFriendTotal: p.friendTotal
                ))
            }
        } catch {
            debugLog("⚠️ Error batch-fetching friend candidate game details: \(error)")
        }
        
        return candidates
    }
    
    // MARK: - Source 2: Genre Discovery (PlayedIt games table)
    
    private func gatherGenreCandidates(context: PredictionContext, excludedIds: Set<Int>, ownedPlatforms: Set<String>, rankedBaseTitles: Set<String>) async -> [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] {
        // Find user's top genres (from their top-ranked games)
        var genreCounts: [String: (count: Int, totalPercentile: Double)] = [:]
        for game in context.myGames {
            let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
            for genre in game.genres {
                let existing = genreCounts[genre] ?? (count: 0, totalPercentile: 0)
                genreCounts[genre] = (count: existing.count + 1, totalPercentile: existing.totalPercentile + percentile)
            }
        }
        
        // Sort by average percentile (genres the user ranks highly)
        let topGenres = genreCounts
            .map { (genre: $0.key, avgPercentile: $0.value.totalPercentile / Double($0.value.count), count: $0.value.count) }
            .filter { $0.count >= 2 }  // Need at least 2 games in genre
            .sorted { $0.avgPercentile > $1.avgPercentile }
            .prefix(3)
            .map { $0.genre }
        
        guard !topGenres.isEmpty else { return [] }
        
        var candidates: [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] = []
        
        do {
            struct GameRow: Decodable {
                let id: Int
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let genres: [String]?
                let tags: [String]?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let curated_platforms: [String]?
                let metacritic_score: Int?
            }
            
            // Fetch games from PlayedIt table that overlap with user's top genres
            let games: [GameRow] = try await supabase.client
                .from("games")
                .select("id, rawg_id, title, cover_url, genres, tags, curated_genres, curated_tags, curated_platforms, metacritic_score")
                .not("curated_platforms", operator: .is, value: "null")
                .limit(50)
                .execute()
                .value
            
            for game in games {
                guard !excludedIds.contains(game.id) else { continue }
                guard !candidates.contains(where: { $0.gameId == game.id }) else { continue }
                                
                // Skip title variants of already-ranked games
                if rankedBaseTitles.contains(baseTitle(game.title)) { continue }
                
                // Skip if no curated platforms or no overlap with owned platforms
                guard let curatedPlats = game.curated_platforms, !curatedPlats.isEmpty else { continue }
                if !ownedPlatforms.isEmpty {
                    guard !Set(curatedPlats).intersection(ownedPlatforms).isEmpty else { continue }
                }
                
                // Check genre overlap
                let gameGenres = game.curated_genres ?? game.genres ?? []
                let hasGenreOverlap = gameGenres.contains(where: { topGenres.contains($0) })
                guard hasGenreOverlap else { continue }
                
                candidates.append((
                    gameId: game.id,
                    rawgId: game.rawg_id,
                    title: game.title,
                    coverUrl: game.cover_url,
                    genres: gameGenres,
                    tags: game.curated_tags ?? game.tags ?? [],
                    metacritic: game.metacritic_score,
                    source: "genre_discovery",
                    sourceFriendId: nil,
                    sourceFriendName: nil,
                    sourceFriendRank: nil,
                    sourceFriendTotal: nil
                ))
                
                if candidates.count >= 20 { break }
            }
        } catch {
            debugLog("⚠️ Error fetching genre candidates: \(error)")
        }
        
        return candidates
    }
    
    // MARK: - Source 3: RAWG Discovery
    private func gatherRAWGCandidates(context: PredictionContext, excludedIds: Set<Int>, ownedPlatforms: Set<String>, rankedBaseTitles: Set<String>) async -> [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] {
        // Find user's top genres from their highest-ranked games
        var genreCounts: [String: (count: Int, totalPercentile: Double)] = [:]
        for game in context.myGames {
            let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
            for genre in game.genres {
                let existing = genreCounts[genre] ?? (count: 0, totalPercentile: 0)
                genreCounts[genre] = (count: existing.count + 1, totalPercentile: existing.totalPercentile + percentile)
            }
        }
        
        let topGenres = genreCounts
            .map { (genre: $0.key, avgPercentile: $0.value.totalPercentile / Double($0.value.count), count: $0.value.count) }
            .filter { $0.count >= 2 }
            .sorted { $0.avgPercentile > $1.avgPercentile }
            .prefix(3)
            .map { $0.genre }
        
        guard !topGenres.isEmpty else { return [] }
        
        var candidates: [(gameId: Int, rawgId: Int, title: String, coverUrl: String?, genres: [String], tags: [String], metacritic: Int?, source: String, sourceFriendId: String?, sourceFriendName: String?, sourceFriendRank: Int?, sourceFriendTotal: Int?)] = []
        
        let excludedRawgIds = Set(context.myGames.map { $0.rawgId })
        
        // Use RAWG discover endpoint — fetch top-rated games in user's preferred genres
        debugLog("🔍 RAWG discover genres: \(topGenres)")
        
        do {
            let results = try await RAWGService.shared.discoverGames(genres: Array(topGenres.prefix(2)))
            
            for game in results {
                guard !excludedRawgIds.contains(game.rawgId) else { continue }
                guard candidates.count < 15 else { break }
                
                let gameId = await ensureGameInTable(game: game)
                guard let gId = gameId else { continue }
                guard !excludedIds.contains(gId) else { continue }
                guard !candidates.contains(where: { $0.gameId == gId }) else { continue }
                                
                // Skip title variants of already-ranked games
                if rankedBaseTitles.contains(baseTitle(game.title)) { continue }
                
                // Check for curated data if game already existed in table
                var useGenres = game.genres
                var useTags = game.tags
                if let curatedData = await fetchCuratedData(gameId: gId) {
                    if let cg = curatedData.curatedGenres { useGenres = cg }
                    if let ct = curatedData.curatedTags { useTags = ct }
                    
                    // Skip if no curated platforms or no overlap with owned platforms
                    guard let curatedPlats = curatedData.curatedPlatforms, !curatedPlats.isEmpty else { continue }
                    if !ownedPlatforms.isEmpty {
                        guard !Set(curatedPlats).intersection(ownedPlatforms).isEmpty else { continue }
                    }
                } else {
                    // No curated data at all — don't recommend
                    continue
                }
                
                candidates.append((
                    gameId: gId,
                    rawgId: game.rawgId,
                    title: game.title,
                    coverUrl: game.coverURL,
                    genres: useGenres,
                    tags: useTags,
                    metacritic: game.metacriticScore,
                    source: "rawg_discovery",
                    sourceFriendId: nil,
                    sourceFriendName: nil,
                    sourceFriendRank: nil,
                    sourceFriendTotal: nil
                ))
            }
            
            debugLog("🔍 RAWG discover found: \(candidates.count) candidates")
        } catch {
            debugLog("⚠️ RAWG discover failed: \(error)")
        }
        
        return candidates
    }
    
    // MARK: - Ensure Game Exists in Table
    private func ensureGameInTable(game: Game) async -> Int? {
        do {
            struct ExistingGame: Decodable { let id: Int }
            
            // Check if already exists
            let existing: [ExistingGame] = try await supabase.client
                .from("games")
                .select("id")
                .eq("rawg_id", value: game.rawgId)
                .execute()
                .value
            
            if let first = existing.first {
                return first.id
            }
            
            // Insert new game
            struct NewGame: Encodable {
                let rawg_id: Int
                let title: String
                let cover_url: String?
                let genres: [String]
                let tags: [String]
                let metacritic_score: Int?
            }
            
            try await supabase.client
                .from("games")
                .upsert(NewGame(
                    rawg_id: game.rawgId,
                    title: game.title,
                    cover_url: game.coverURL,
                    genres: game.genres,
                    tags: game.tags,
                    metacritic_score: game.metacriticScore
                ), onConflict: "rawg_id")
                .execute()
            
            struct InsertedGame: Decodable { let id: Int }
            let fetched: [InsertedGame] = try await supabase.client
                .from("games")
                .select("id")
                .eq("rawg_id", value: game.rawgId)
                .limit(1)
                .execute()
                .value
            
            return fetched.first?.id
            
        } catch {
            debugLog("⚠️ Error ensuring game in table: \(error)")
            return nil
        }
    }
    
    // MARK: - Fetch Curated Data If Available
    private func fetchCuratedData(gameId: Int) async -> (curatedGenres: [String]?, curatedTags: [String]?, curatedPlatforms: [String]?, curatedReleaseYear: Int?)? {
        struct CuratedRow: Decodable {
            let curated_genres: [String]?
            let curated_tags: [String]?
            let curated_platforms: [String]?
            let curated_release_year: Int?
        }
        
        guard let row = try? await supabase.client
            .from("games")
            .select("curated_genres, curated_tags, curated_platforms, curated_release_year")
            .eq("id", value: gameId)
            .single()
            .execute()
            .value as CuratedRow else { return nil }
        
        guard row.curated_genres != nil || row.curated_tags != nil || row.curated_platforms != nil || row.curated_release_year != nil else { return nil }
        return (curatedGenres: row.curated_genres, curatedTags: row.curated_tags, curatedPlatforms: row.curated_platforms, curatedReleaseYear: row.curated_release_year)
    }
    
    // MARK: - Build Display List
    func buildDisplayList() async {
        guard let context = await PredictionEngine.shared.getContext() else { return }
        let pending = await fetchPending()
        
        var displays: [RecommendationDisplay] = []
        
        // Batch fetch all game info for pending recommendations in one query
        struct GameInfo: Decodable {
            let id: Int
            let rawg_id: Int
            let title: String
            let cover_url: String?
            let genres: [String]?
            let tags: [String]?
            let curated_genres: [String]?
            let curated_tags: [String]?
            let platforms: [String]?
            let curated_platforms: [String]?
            let metacritic_score: Int?
        }
        let allRecGameIds = pending.map { $0.gameId }
        let allGameInfos: [GameInfo]
        do {
            allGameInfos = try await supabase.client
                .from("games")
                .select("id, rawg_id, title, cover_url, genres, tags, curated_genres, curated_tags, platforms, curated_platforms, metacritic_score")
                .in("id", values: allRecGameIds)
                .execute()
                .value
        } catch {
            debugLog("⚠️ Error batch-fetching recommendation game info: \(error)")
            return
        }
        let gameInfoMap = Dictionary(uniqueKeysWithValues: allGameInfos.map { ($0.id, $0) })

        for rec in pending {
            guard let info = gameInfoMap[rec.gameId] else { continue }
                let target = PredictionTarget(
                    rawgId: info.rawg_id,
                    canonicalGameId: nil,
                    genres: info.curated_genres ?? info.genres ?? [],
                    tags: info.curated_tags ?? info.tags ?? [],
                    metacriticScore: info.metacritic_score
                )
                
                let prediction = PredictionEngine.shared.predict(game: target, context: context)
                guard let pred = prediction else { continue }
                
                // Get friend name if friend-sourced
                var friendName: String? = nil
                var friendRank: Int? = nil
                var friendTotal: Int? = nil
                
                if rec.source == "friend_ranked", let friendId = rec.sourceFriendId {
                    if let friend = context.friends.first(where: { $0.userId == friendId }) {
                        friendName = friend.username
                        if let friendGame = friend.games.first(where: { $0.gameId == rec.gameId }) {
                            friendRank = friendGame.rankPosition
                            friendTotal = friend.games.count
                        }
                    }
                }
                
                displays.append(RecommendationDisplay(
                    id: rec.id,
                    recommendation: rec,
                    gameTitle: info.title,
                    gameCoverUrl: info.cover_url,
                    gameRawgId: info.rawg_id,
                    genres: info.curated_genres ?? info.genres ?? [],
                    platforms: info.curated_platforms ?? info.platforms,
                    prediction: pred,
                    sourceFriendName: friendName,
                    sourceFriendRankPosition: friendRank,
                    sourceFriendTotalGames: friendTotal
                ))
        }
        
        // Sort by confidence first, then predicted percentile
        recommendations = displays.sorted {
            if $0.prediction.confidence != $1.prediction.confidence {
                return $0.prediction.confidence > $1.prediction.confidence
            }
            return $0.prediction.predictedPercentile > $1.prediction.predictedPercentile
        }
    }
    
    // MARK: - User Actions
    
    func dismiss(recommendationId: Int64, reason: String?) async -> Bool {
        do {
            let sixMonthsFromNow = Calendar.current.date(byAdding: .month, value: 6, to: Date())!
            let formatter = ISO8601DateFormatter()
            
            struct Update: Encodable {
                let action: String
                let dismiss_reason: String?
                let acted_at: String
                let dismissed_until: String
            }
            
            try await supabase.client
                .from("recommendations")
                .update(Update(
                    action: "dismissed",
                    dismiss_reason: reason,
                    acted_at: formatter.string(from: Date()),
                    dismissed_until: formatter.string(from: sixMonthsFromNow)
                ))
                .eq("id", value: String(recommendationId))
                .execute()
            
            // Remove from display
            recommendations.removeAll { $0.id == recommendationId }
            return true
        } catch {
            debugLog("❌ Error dismissing recommendation: \(error)")
            return false
        }
    }
    
    func markAsWantToPlay(recommendationId: Int64) async -> Bool {
        do {
            let formatter = ISO8601DateFormatter()
            
            struct Update: Encodable {
                let action: String
                let acted_at: String
            }
            
            try await supabase.client
                .from("recommendations")
                .update(Update(
                    action: "want_to_play",
                    acted_at: formatter.string(from: Date())
                ))
                .eq("id", value: String(recommendationId))
                .execute()
            
            // Remove from display
            recommendations.removeAll { $0.id == recommendationId }
            return true
        } catch {
            debugLog("❌ Error marking recommendation as want to play: \(error)")
            return false
        }
    }
    
    func markAsRanked(recommendationId: Int64, rankPosition: Int, totalGames: Int) async -> Bool {
        do {
            let formatter = ISO8601DateFormatter()
            let actualPercentile = (1.0 - (Double(rankPosition - 1) / Double(max(totalGames - 1, 1)))) * 100.0
            
            // Get the original predicted percentile
            let rec = recommendations.first { $0.id == recommendationId }
            let predictedPercentile = rec?.recommendation.predictedPercentile ?? 0
            let accuracy = predictedPercentile - actualPercentile
            
            struct Update: Encodable {
                let action: String
                let actual_rank_position: Int
                let actual_percentile: Double
                let prediction_accuracy: Double
                let acted_at: String
                let ranked_at: String
            }
            
            try await supabase.client
                .from("recommendations")
                .update(Update(
                    action: "ranked",
                    actual_rank_position: rankPosition,
                    actual_percentile: actualPercentile,
                    prediction_accuracy: accuracy,
                    acted_at: formatter.string(from: Date()),
                    ranked_at: formatter.string(from: Date())
                ))
                .eq("id", value: String(recommendationId))
                .execute()
            
            // Remove from display
            recommendations.removeAll { $0.id == recommendationId }
            return true
        } catch {
            debugLog("❌ Error marking recommendation as ranked: \(error)")
            return false
        }
    }
    
    // MARK: - Update Recommendation When Game is Ranked (call from GameLogView)
    
    static func checkAndUpdateOnRank(gameId: Int, rankPosition: Int, totalGames: Int) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        do {
            struct RecRow: Decodable {
                let id: Int64
                let predicted_percentile: Double
            }
            
            let recs: [RecRow] = try await SupabaseManager.shared.client
                .from("recommendations")
                .select("id, predicted_percentile")
                .eq("user_id", value: userId.uuidString)
                .eq("game_id", value: gameId)
                .execute()
                .value
            
            guard let rec = recs.first else { return }
            
            let actualPercentile = (1.0 - (Double(rankPosition - 1) / Double(max(totalGames - 1, 1)))) * 100.0
            let accuracy = rec.predicted_percentile - actualPercentile
            let formatter = ISO8601DateFormatter()
            
            struct Update: Encodable {
                let action: String
                let actual_rank_position: Int
                let actual_percentile: Double
                let prediction_accuracy: Double
                let ranked_at: String
            }
            
            try await SupabaseManager.shared.client
                .from("recommendations")
                .update(Update(
                    action: "ranked",
                    actual_rank_position: rankPosition,
                    actual_percentile: actualPercentile,
                    prediction_accuracy: accuracy,
                    ranked_at: formatter.string(from: Date())
                ))
                .eq("id", value: String(rec.id))
                .execute()
            
            debugLog("✅ Updated recommendation outcome: predicted=\(Int(rec.predicted_percentile))%, actual=\(Int(actualPercentile))%, accuracy=\(Int(accuracy))")
                        
                // Remove from display list
                await MainActor.run {
                    RecommendationManager.shared.recommendations.removeAll { $0.id == rec.id }
                }
                
            } catch {
                // Not an error if no recommendation exists for this game
            }
        }
    
    // MARK: - Check if User Has Enough Games
    
    func userHasEnoughGames() async -> Bool {
        guard let userId = supabase.currentUser?.id else { return false }
        
        do {
            struct CountRow: Decodable { let count: Int }
            
            let _: [CountRow] = try await supabase.client
                .from("user_games")
                .select("count", head: false)
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .execute()
                .value
            
            // Supabase returns count differently - let's use a simpler approach
            return true  // We'll check in the view with context.myGameCount
        } catch {
            return false
        }
    }
}
