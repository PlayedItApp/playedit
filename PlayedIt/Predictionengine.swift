import Foundation
import Supabase

// MARK: - Prediction Models

struct GamePrediction {
    let predictedPercentile: Double      // 0-100, where 100 = would be their #1
    let confidence: Int                   // 1-5 dots
    let confidenceLabel: String           // "Very High", "High", etc.
    let tiersUsed: [String]              // ["friends", "genre", "metacritic"]
    let friendSignals: [FriendSignal]    // Individual friend data points
    let topGenreAffinity: Double?        // User's avg percentile for this game's top genre
    let topTagAffinity: Double?          // User's avg percentile for this game's top tag
    
    var displayText: String {
        let rank = estimatedRankRange
        if rank.lower == rank.upper {
            return "~#\(rank.lower)"
        }
        return "~#\(rank.lower)–\(rank.upper)"
    }
    
    var estimatedRankRange: (lower: Int, upper: Int) {
        // Will be set by caller based on their list size
        (lower: 0, upper: 0)
    }
    
    func estimatedRank(inListOf size: Int) -> (lower: Int, upper: Int) {
        let center = max(1, Int(round(Double(size + 1) * (1.0 - predictedPercentile / 100.0))))
        let spread: Int
        switch confidence {
        case 5: spread = max(1, Int(Double(size) * 0.05))
        case 4: spread = max(2, Int(Double(size) * 0.10))
        case 3: spread = max(3, Int(Double(size) * 0.15))
        case 2: spread = max(4, Int(Double(size) * 0.20))
        default: spread = max(5, Int(Double(size) * 0.30))
        }
        let lower = max(1, center - spread)
        let upper = min(size + 1, center + spread)
        return (lower: lower, upper: upper)
    }
    
    var emoji: String {
        switch predictedPercentile {
        case 65...100: return "🔥"
        case 40..<65: return "🤔"
        default: return "👎"
        }
    }
    
    var summaryText: String {
        switch predictedPercentile {
        case 65...100: return "You'll love this"
        case 40..<65: return "Could go either way"
        default: return "Not your vibe"
        }
    }
    
    var summaryColor: String {
        switch predictedPercentile {
        case 65...100: return "primaryBlue"
        case 40..<65: return "silver"
        default: return "slate"
        }
    }
    
    var confidenceDots: String {
        String(repeating: "●", count: confidence) + String(repeating: "○", count: 5 - confidence)
    }
}

struct FriendSignal {
    let friendName: String
    let friendRankPercentile: Double  // Where they ranked it (100 = their #1)
    let tasteMatch: Int               // 0-100 match percentage
    let weight: Double                // Computed weight for blending
}

// MARK: - Prediction Context (caller fetches once, predicts many)

struct PredictionContext {
    let myGames: [RankedGameData]
    let friends: [FriendData]
    
    var myGameCount: Int { myGames.count }
    var hasEnoughData: Bool { myGames.count >= 5 }
}

struct RankedGameData {
    let gameId: Int
    let rawgId: Int
    let canonicalGameId: Int?
    let rankPosition: Int
    let genres: [String]
    let tags: [String]
    let metacriticScore: Int?
}

struct FriendData {
    let userId: String
    let username: String
    let tasteMatch: Int              // 0-100
    let games: [FriendRankedGame]
}

struct FriendRankedGame {
    let gameId: Int
    let rawgId: Int
    let canonicalGameId: Int?
    let rankPosition: Int
    let totalGames: Int
}

// MARK: - Game Data for Prediction Target

struct PredictionTarget {
    let rawgId: Int
    let canonicalGameId: Int?
    let genres: [String]
    let tags: [String]
    let metacriticScore: Int?
}

// MARK: - Prediction Engine

class PredictionEngine {
    static let shared = PredictionEngine()
    private init() {}
    
    // MARK: - Main Prediction
    
    func predict(game: PredictionTarget, context: PredictionContext) -> GamePrediction? {
        guard context.hasEnoughData else { return nil }
        
        var tiersUsed: [String] = []
        
        // Tier 1: Friend-weighted rankings
        let friendResult = computeFriendWeightedRank(game: game, context: context)
        
        // Tier 2: Genre/Tag affinity
        let genreAffinity = computeGenreAffinity(genres: game.genres, context: context)
        let tagAffinity = computeTagAffinity(tags: game.tags, context: context)
        let genreTagScore = blendGenreTag(genre: genreAffinity, tag: tagAffinity)
        
        // Tier 3: Metacritic correlation
        let metacriticScore = computeMetacriticCorrelation(
            metacritic: game.metacriticScore,
            context: context
        )
        
        // Track which tiers contributed
        if let fr = friendResult, !fr.signals.isEmpty { tiersUsed.append("friends") }
        if genreTagScore != nil { tiersUsed.append("genre") }
        if metacriticScore != nil { tiersUsed.append("metacritic") }
        
        // Blend tiers
        let blended = blendTiers(
            friendResult: friendResult,
            genreTagScore: genreTagScore,
            metacriticScore: metacriticScore,
            context: context
        )
        
        guard let finalPercentile = blended else { return nil }
        
        // Calculate confidence
        let confidence = calculateConfidence(
            friendResult: friendResult,
            genreTagScore: genreTagScore,
            metacriticScore: metacriticScore,
            context: context
        )
        
        let confidenceLabels = ["", "Guess", "Low", "Medium", "High", "Very High"]
        
        return GamePrediction(
            predictedPercentile: finalPercentile,
            confidence: confidence,
            confidenceLabel: confidenceLabels[confidence],
            tiersUsed: tiersUsed,
            friendSignals: friendResult?.signals ?? [],
            topGenreAffinity: genreAffinity,
            topTagAffinity: tagAffinity
        )
    }
    
    // MARK: - Tier 1: Friend-Weighted Rankings
    
    private struct FriendResult {
        let percentile: Double
        let signals: [FriendSignal]
    }
    
    private func computeFriendWeightedRank(game: PredictionTarget, context: PredictionContext) -> FriendResult? {
        let targetId = game.canonicalGameId ?? game.rawgId
        
        var signals: [FriendSignal] = []
        
        for friend in context.friends {
            // Only use friends with 30%+ taste match
            guard friend.tasteMatch >= 30 else { continue }
            
            // Find this game in friend's list
            let match = friend.games.first(where: { friendGame in
                let friendCanonical = friendGame.canonicalGameId ?? friendGame.rawgId
                return friendCanonical == targetId || friendGame.rawgId == game.rawgId
            })
            
            guard let friendGame = match else { continue }
            
            // Convert rank to percentile (1st out of 50 = 100th percentile)
            let percentile = (1.0 - (Double(friendGame.rankPosition - 1) / Double(max(friendGame.totalGames - 1, 1)))) * 100.0
            
            // Weight by taste match (normalized 0-1, with floor at 0.3)
            let tasteWeight = Double(friend.tasteMatch) / 100.0
            
            signals.append(FriendSignal(
                friendName: friend.username,
                friendRankPercentile: percentile,
                tasteMatch: friend.tasteMatch,
                weight: tasteWeight
            ))
        }
        
        guard !signals.isEmpty else { return nil }
        
        // Weighted average
        let totalWeight = signals.reduce(0.0) { $0 + $1.weight }
        let weightedSum = signals.reduce(0.0) { $0 + $1.friendRankPercentile * $1.weight }
        let percentile = weightedSum / totalWeight
        
        return FriendResult(percentile: percentile, signals: signals)
    }
    
    // MARK: - Tier 2: Genre Affinity
    
    private func computeGenreAffinity(genres: [String], context: PredictionContext) -> Double? {
        guard !genres.isEmpty, context.myGameCount >= 5 else { return nil }
        
        // For each genre, find user's average rank percentile
        var genrePercentiles: [Double] = []
        
        for genre in genres {
            let matchingGames = context.myGames.filter { $0.genres.contains(genre) }
            guard !matchingGames.isEmpty else { continue }
            
            let avgPercentile = matchingGames.reduce(0.0) { sum, game in
                let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
                return sum + percentile
            } / Double(matchingGames.count)
            
            // Weight by how many games in this genre — more games = more reliable signal
            let countBoost: Double
            if matchingGames.count >= 5 {
                countBoost = 1.0  // Strong signal, no adjustment needed
            } else if matchingGames.count >= 3 {
                countBoost = 0.9  // Decent signal
            } else {
                countBoost = 0.75 // Weak signal — pull toward neutral
            }
            
            // Blend toward the raw average but amplify if user clearly likes the genre
            // For small libraries: if avg is above 50%, boost it slightly to create separation
            var adjusted = avgPercentile
            if context.myGameCount < 30 && avgPercentile > 50 {
                let boost = (avgPercentile - 50) * 0.3 * countBoost  // Up to ~15% boost
                adjusted = avgPercentile + boost
            }
            
            genrePercentiles.append(adjusted)
        }
        
        guard !genrePercentiles.isEmpty else { return nil }
        
        // Average across all matching genres
        return max(20, genrePercentiles.reduce(0.0, +) / Double(genrePercentiles.count))
    }
    
    // MARK: - Tier 2: Tag Affinity
    
    private func computeTagAffinity(tags: [String], context: PredictionContext) -> Double? {
        guard !tags.isEmpty, context.myGameCount >= 5 else { return nil }
        
        var tagPercentiles: [Double] = []
        
        for tag in tags {
            let matchingGames = context.myGames.filter { $0.tags.contains(tag) }
            // Need at least 2 games with this tag for it to be meaningful
            guard matchingGames.count >= 2 else { continue }
            
            let avgPercentile = matchingGames.reduce(0.0) { sum, game in
                let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
                return sum + percentile
            } / Double(matchingGames.count)
            
            var adjusted = avgPercentile
            if context.myGameCount < 30 && avgPercentile > 50 {
                let countBoost = matchingGames.count >= 3 ? 0.9 : 0.75
                let boost = (avgPercentile - 50) * 0.3 * countBoost
                adjusted = avgPercentile + boost
            }
            
            tagPercentiles.append(adjusted)
        }
        
        guard !tagPercentiles.isEmpty else { return nil }
        
        return max(20, tagPercentiles.reduce(0.0, +) / Double(tagPercentiles.count))
    }
    
    // MARK: - Blend Genre + Tag
    
    private func blendGenreTag(genre: Double?, tag: Double?) -> Double? {
        switch (genre, tag) {
        case let (g?, t?):
            return g * 0.5 + t * 0.5  // Equal weight genre and tags
        case let (g?, nil):
            return g
        case let (nil, t?):
            return t
        case (nil, nil):
            return nil
        }
    }
    
    // MARK: - Tier 3: Metacritic Correlation
    
    private func computeMetacriticCorrelation(metacritic: Int?, context: PredictionContext) -> Double? {
        guard let targetScore = metacritic, targetScore > 0 else { return nil }
        
        // Get games with metacritic scores
        let gamesWithMeta = context.myGames.filter { ($0.metacriticScore ?? 0) > 0 }
        guard gamesWithMeta.count >= 5 else { return nil }
        
        // Compute Pearson correlation between user rank percentile and metacritic
        let n = Double(gamesWithMeta.count)
        
        var sumX: Double = 0   // metacritic scores
        var sumY: Double = 0   // rank percentiles
        var sumXY: Double = 0
        var sumX2: Double = 0
        var sumY2: Double = 0
        
        for game in gamesWithMeta {
            let x = Double(game.metacriticScore!)
            let y = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
            sumY2 += y * y
        }
        
        // Ensure there's enough variance for regression
        let varianceX = n * sumX2 - sumX * sumX
        guard varianceX > 0 else { return nil }
        
        // Linear regression: y = a + b*x
        let meanX = sumX / n
        let meanY = sumY / n
        let b = (n * sumXY - sumX * sumY) / varianceX
        let a = meanY - b * meanX
        
        let predicted = a + b * Double(targetScore)
        return max(0, min(100, predicted))
    }
    
    // MARK: - Blend All Tiers
    
    private func blendTiers(
        friendResult: FriendResult?,
        genreTagScore: Double?,
        metacriticScore: Double?,
        context: PredictionContext
    ) -> Double? {
        let friendCount = friendResult?.signals.count ?? 0
        let hasFriends = friendCount > 0
        let hasGenreTag = genreTagScore != nil
        let hasMetacritic = metacriticScore != nil
        
        // At least one signal needed
        guard hasFriends || hasGenreTag || hasMetacritic else { return nil }
        
        // Determine weights based on available signals
        var friendWeight: Double = 0
        var genreTagWeight: Double = 0
        var metacriticWeight: Double = 0
        
        if context.myGameCount < 5 {
            // Very thin data — lean on metacritic
            friendWeight = hasFriends ? 0.0 : 0.0
            genreTagWeight = hasGenreTag ? 0.20 : 0.0
            metacriticWeight = hasMetacritic ? 0.80 : 0.0
        } else if friendCount >= 2 {
            // Strong friend signal
            friendWeight = 0.60
            genreTagWeight = hasGenreTag ? 0.30 : 0.0
            metacriticWeight = hasMetacritic ? 0.10 : 0.0
        } else if friendCount == 1 {
            // Single friend
            friendWeight = 0.55
            genreTagWeight = hasGenreTag ? 0.30 : 0.0
            metacriticWeight = hasMetacritic ? 0.15 : 0.0
        } else {
            // No friends ranked this game
            friendWeight = 0.0
            genreTagWeight = hasGenreTag ? 0.70 : 0.0
            metacriticWeight = hasMetacritic ? 0.30 : 0.0
        }
        
        // Normalize weights to sum to 1
        let totalWeight = friendWeight + genreTagWeight + metacriticWeight
        guard totalWeight > 0 else { return nil }
        
        friendWeight /= totalWeight
        genreTagWeight /= totalWeight
        metacriticWeight /= totalWeight
        
        var blended: Double = 0
        if let fr = friendResult { blended += fr.percentile * friendWeight }
        if let gt = genreTagScore { blended += gt * genreTagWeight }
        if let mc = metacriticScore { blended += mc * metacriticWeight }
        
        debugLog("🧮 Blend: friend=\(friendResult?.percentile ?? -1), genreTag=\(genreTagScore ?? -1), metacritic=\(metacriticScore ?? -1), blended=\(blended)")
        // Genre drag: if friends love it but genre/tag affinity doesn't match, limit friend influence
        if let fr = friendResult, !fr.signals.isEmpty {
            if let gt = genreTagScore {
                if gt < 50 {
                    // Strong genre mismatch
                    let penalty = (50 - gt) / 50.0 * 20.0
                    blended -= penalty
                } else if gt < 70 && fr.percentile > 80 {
                    // Friend ranked it very high but genre/tag fit is only moderate
                    // Reduce friend contribution proportionally
                    let reductionFactor = (70 - gt) / 20.0 * 0.4
                    let friendContribution = fr.percentile * friendWeight
                    blended -= friendContribution * reductionFactor
                }
            }
        }
        
        return max(0, min(100, blended))
    }
    
    // MARK: - Confidence Calculation
    
    private func calculateConfidence(
        friendResult: FriendResult?,
        genreTagScore: Double?,
        metacriticScore: Double?,
        context: PredictionContext
    ) -> Int {
        let friendCount = friendResult?.signals.count ?? 0
        let hasStrongGenreTag = genreTagScore != nil && context.myGameCount >= 10
        let hasMetacritic = metacriticScore != nil
        
        // Average taste match of contributing friends
        let avgTasteMatch = friendResult.map { result in
            result.signals.reduce(0) { $0 + $1.tasteMatch } / max(result.signals.count, 1)
        } ?? 0
        
        if friendCount >= 3 && avgTasteMatch >= 50 && hasStrongGenreTag {
            return 5  // Very High
        } else if friendCount >= 2 && avgTasteMatch >= 40 {
            return 4  // High
        } else if (friendCount >= 2) || (hasStrongGenreTag && hasMetacritic) {
            return 4  // High
        } else if friendCount == 1 && hasStrongGenreTag {
            return 3  // Medium
        } else if hasStrongGenreTag {
            return 3  // Medium
        } else if genreTagScore != nil {
            return 2  // Low
        } else if hasMetacritic {
            return 1  // Guess
        } else {
            return 1  // Guess
        }
    }
    
    // MARK: - Context Builder (fetches data from Supabase)
    
    static func buildContext() async -> PredictionContext? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            // Fetch user's ranked games with genre/tag/metacritic data
            struct MyGameRow: Decodable {
                let id: String
                let game_id: Int
                let rank_position: Int
                let canonical_game_id: Int?
                let games: GameData
                
                struct GameData: Decodable {
                    let rawg_id: Int
                    let genres: [String]?
                    let tags: [String]?
                    let metacritic_score: Int?
                }
            }
            
            let myRows: [MyGameRow] = try await SupabaseManager.shared.client
                .from("user_games")
                .select("id, game_id, rank_position, canonical_game_id, games(rawg_id, genres, tags, metacritic_score)")
                .eq("user_id", value: userId.uuidString)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            let myGames = myRows.map { row in
                RankedGameData(
                    gameId: row.game_id,
                    rawgId: row.games.rawg_id,
                    canonicalGameId: row.canonical_game_id,
                    rankPosition: row.rank_position,
                    genres: row.games.genres ?? [],
                    tags: row.games.tags ?? [],
                    metacriticScore: row.games.metacritic_score
                )
            }
            
            // Fetch accepted friendships
            struct FriendshipRow: Decodable {
                let user_id: String
                let friend_id: String
            }
            
            let friendships: [FriendshipRow] = try await SupabaseManager.shared.client
                .from("friendships")
                .select("user_id, friend_id")
                .eq("status", value: "accepted")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .execute()
                .value
            
            let friendIds = friendships.map { f in
                f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
            }
            
            // Fetch each friend's data
            var friends: [FriendData] = []
            
            for friendId in friendIds {
                // Get friend username
                struct UserInfo: Decodable {
                    let username: String?
                }
                
                let userInfo: UserInfo = try await SupabaseManager.shared.client
                    .from("users")
                    .select("username")
                    .eq("id", value: friendId)
                    .single()
                    .execute()
                    .value
                
                // Get friend's ranked games
                struct FriendGameRow: Decodable {
                    let game_id: Int
                    let rank_position: Int
                    let canonical_game_id: Int?
                    let games: FriendGameData
                    
                    struct FriendGameData: Decodable {
                        let rawg_id: Int
                    }
                }
                
                let friendRows: [FriendGameRow] = try await SupabaseManager.shared.client
                    .from("user_games")
                    .select("game_id, rank_position, canonical_game_id, games(rawg_id)")
                    .eq("user_id", value: friendId)
                    .not("rank_position", operator: .is, value: "null")
                    .order("rank_position", ascending: true)
                    .execute()
                    .value
                
                let friendGames = friendRows.map { row in
                    FriendRankedGame(
                        gameId: row.game_id,
                        rawgId: row.games.rawg_id,
                        canonicalGameId: row.canonical_game_id,
                        rankPosition: row.rank_position,
                        totalGames: friendRows.count
                    )
                }
                
                // Compute taste match using same Spearman logic
                let tasteMatch = computeTasteMatch(
                    myGames: myGames,
                    friendGames: friendGames
                )
                
                friends.append(FriendData(
                    userId: friendId,
                    username: userInfo.username ?? "Friend",
                    tasteMatch: tasteMatch,
                    games: friendGames
                ))
            }
            
            return PredictionContext(myGames: myGames, friends: friends)
            
        } catch {
            debugLog("❌ Error building prediction context: \(error)")
            return nil
        }
    }
    
    // MARK: - Taste Match (Spearman) — mirrors FriendProfileView logic
    
    private static func computeTasteMatch(myGames: [RankedGameData], friendGames: [FriendRankedGame]) -> Int {
        // Find shared games by canonical ID
        var shared: [(myRank: Int, theirRank: Int)] = []
        
        for myGame in myGames {
        // Match by canonical RAWG ID
        let myCanonical = myGame.canonicalGameId ?? myGame.rawgId
        if let theirGame = friendGames.first(where: {
            ($0.canonicalGameId ?? $0.rawgId) == myCanonical
        }) {
                shared.append((myRank: myGame.rankPosition, theirRank: theirGame.rankPosition))
            }
        }
        
        guard !shared.isEmpty else { return 0 }
        debugLog("📊 Taste match: \(shared.count) shared games, myGames=\(myGames.count), friendGames=\(friendGames.count)")
        for s in shared {
            debugLog("   📊 myRank=\(s.myRank), theirRank=\(s.theirRank)")
        }
        
        if shared.count == 1 {
            let maxDiff = max(myGames.count, friendGames.count)
            let actualDiff = abs(shared[0].myRank - shared[0].theirRank)
            if maxDiff == 0 { return 100 }
            return max(0, min(100, 100 - Int((Double(actualDiff) / Double(maxDiff)) * 100)))
        }
        
        let n = Double(shared.count)
        
        // Assign relative ranks
        let myOrder = shared.indices.sorted { shared[$0].myRank < shared[$1].myRank }
        var myRelative = Array(repeating: 0, count: shared.count)
        for (rank, idx) in myOrder.enumerated() { myRelative[idx] = rank + 1 }
        
        let theirOrder = shared.indices.sorted { shared[$0].theirRank < shared[$1].theirRank }
        var theirRelative = Array(repeating: 0, count: shared.count)
        for (rank, idx) in theirOrder.enumerated() { theirRelative[idx] = rank + 1 }
        
        var sumDSquared: Double = 0
        for i in shared.indices {
            let d = Double(myRelative[i] - theirRelative[i])
            sumDSquared += d * d
        }
        
        let denominator = n * (n * n - 1)
        guard denominator != 0 else { return 50 }
        
        let rho = 1 - (6 * sumDSquared) / denominator
        return max(0, min(100, Int(((rho + 1) / 2) * 100)))
    }
    
    // MARK: - Convenience: Single Game Prediction
    
    /// Fetches context and predicts for a single game. Use `buildContext()` + `predict()` for multiple games.
    static func quickPredict(game: PredictionTarget) async -> GamePrediction? {
        guard let context = await buildContext() else { return nil }
        return PredictionEngine.shared.predict(game: game, context: context)
    }
}
