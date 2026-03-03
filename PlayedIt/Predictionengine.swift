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
    let releaseYear: Int?
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
    var releaseYear: Int? = nil
}

// MARK: - Prediction Engine

class PredictionEngine {
    static let shared = PredictionEngine()
    private init() {}
    
    // MARK: - Cached Context
    private(set) var cachedContext: PredictionContext?
    private var contextLastBuilt: Date?
    
    /// Returns cached context if fresh, otherwise rebuilds
    func getContext(maxAge: TimeInterval = 300) async -> PredictionContext? {
        if let cached = cachedContext,
           let lastBuilt = contextLastBuilt,
           Date().timeIntervalSince(lastBuilt) < maxAge {
            return cached
        }
        return await refreshContext()
    }
    
    /// Force rebuild and cache
    @discardableResult
    func refreshContext() async -> PredictionContext? {
        let context = await PredictionEngine.buildContext()
        cachedContext = context
        contextLastBuilt = Date()
        debugLog("🎯 Prediction context refreshed: \(context?.myGameCount ?? 0) games, \(context?.friends.count ?? 0) friends")
        return context
    }
    
    /// Invalidate cache (call when data changes)
    func invalidateContext() {
        cachedContext = nil
        contextLastBuilt = nil
        debugLog("🎯 Prediction context invalidated")
    }
    
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
        
        // Tier 3: Metacritic correlation (disabled — not used in blend)
        let metacriticScore: Double? = nil
        
        // Track which tiers contributed
        if let fr = friendResult, !fr.signals.isEmpty { tiersUsed.append("friends") }
        if genreTagScore != nil { tiersUsed.append("genre") }
        
        // Blend tiers
        let blended = blendTiers(
            friendResult: friendResult,
            genreTagScore: genreTagScore,
            metacriticScore: metacriticScore,
            context: context,
            targetReleaseYear: game.releaseYear
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
            
            // Rank-weighted average: higher-ranked games contribute more
            var weightedSum: Double = 0
            var totalWeight: Double = 0
            for game in matchingGames {
                let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
                // Weight = percentile itself, so top-ranked games in genre dominate
                let weight = max(10, percentile)
                weightedSum += percentile * weight
                totalWeight += weight
            }
            let weightedAvg = weightedSum / totalWeight
            
            // Boost to create separation (no library size gate)
            let countBoost: Double = matchingGames.count >= 5 ? 1.0 : matchingGames.count >= 3 ? 0.9 : 0.75
            var adjusted = weightedAvg
            if weightedAvg > 50 {
                let boost = (weightedAvg - 50) * 0.5 * countBoost
                adjusted = weightedAvg + boost
            }
            
            genrePercentiles.append(adjusted)
        }
        
        guard !genrePercentiles.isEmpty else { return nil }
        
        return genrePercentiles.reduce(0.0, +) / Double(genrePercentiles.count)
    }
    
    // MARK: - Tier 2: Tag Affinity
    
    private func computeTagAffinity(tags: [String], context: PredictionContext) -> Double? {
        guard !tags.isEmpty, context.myGameCount >= 5 else { return nil }
        
        var tagPercentiles: [Double] = []
        
        for tag in tags {
            let matchingGames = context.myGames.filter { $0.tags.contains(tag) }
            guard matchingGames.count >= 2 else { continue }
            
            // Rank-weighted average
            var weightedSum: Double = 0
            var totalWeight: Double = 0
            for game in matchingGames {
                let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
                let weight = max(10, percentile)
                weightedSum += percentile * weight
                totalWeight += weight
            }
            let weightedAvg = weightedSum / totalWeight
            
            let countBoost: Double = matchingGames.count >= 3 ? 0.9 : 0.75
            var adjusted = weightedAvg
            if weightedAvg > 50 {
                let boost = (weightedAvg - 50) * 0.5 * countBoost
                adjusted = weightedAvg + boost
            }
            
            tagPercentiles.append(adjusted)
        }
        
        guard !tagPercentiles.isEmpty else { return nil }
        
        return tagPercentiles.reduce(0.0, +) / Double(tagPercentiles.count)
    }
    
    // MARK: - Blend Genre + Tag
    
    private func blendGenreTag(genre: Double?, tag: Double?) -> Double? {
        switch (genre, tag) {
        case let (g?, t?):
            // Tags are more specific signals than genre
            return g * 0.3 + t * 0.7
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
        context: PredictionContext,
        targetReleaseYear: Int? = nil
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
        
        if friendCount >= 2 {
            // Strong friend signal, but genre/tag leads
            friendWeight = 0.30
            genreTagWeight = hasGenreTag ? 0.70 : 0.0
        } else if friendCount == 1 {
            // Single friend
            friendWeight = 0.25
            genreTagWeight = hasGenreTag ? 0.75 : 0.0
        } else {
            // No friends ranked this game — genre/tag only
            friendWeight = 0.0
            genreTagWeight = hasGenreTag ? 1.0 : 0.0
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
        
        debugLog("🧮 Blend: friend=\(friendResult?.percentile ?? -1), genreTag=\(genreTagScore ?? -1), blended=\(blended)")
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
        
        // Era modifier: boost/penalize based on how candidate's era matches user preference
        if let targetYear = targetReleaseYear {
            let eraModifier = computeEraModifier(targetYear: targetYear, context: context)
            if eraModifier != 0 {
                debugLog("🕰️ Era modifier: \(eraModifier > 0 ? "+" : "")\(String(format: "%.1f", eraModifier)) for year \(targetYear)")
            }
            blended += eraModifier
        }
        
        return max(0, min(100, blended))
    }
    
    // MARK: - Era Modifier
    
    private func computeEraModifier(targetYear: Int, context: PredictionContext) -> Double {
        func era(_ year: Int) -> Int {
            switch year {
            case ..<1995: return 0
            case 1995...2004: return 1
            case 2005...2012: return 2
            case 2013...2019: return 3
            default: return 4
            }
        }
        
        let gamesWithYear = context.myGames.filter { $0.releaseYear != nil }
        guard gamesWithYear.count >= 5 else { return 0 }
        
        let targetEra = era(targetYear)
        let matchingGames = gamesWithYear.filter { era($0.releaseYear!) == targetEra }
        guard !matchingGames.isEmpty else { return -5 }
        
        // Rank-weighted average percentile for games in this era
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        for game in matchingGames {
            let percentile = (1.0 - (Double(game.rankPosition - 1) / Double(max(context.myGameCount - 1, 1)))) * 100.0
            let weight = max(10, percentile)
            weightedSum += percentile * weight
            totalWeight += weight
        }
        let eraAffinity = weightedSum / totalWeight
        
        // Neutral at 50%, max ±10 points
        return (eraAffinity - 50) / 50.0 * 10.0
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
                    let curated_genres: [String]?
                    let curated_tags: [String]?
                    let metacritic_score: Int?
                    let curated_release_year: Int?
                }
            }
            
            let myRows: [MyGameRow] = try await SupabaseManager.shared.client
                .from("user_games")
                .select("id, game_id, rank_position, canonical_game_id, games(rawg_id, genres, tags, curated_genres, curated_tags, metacritic_score, curated_release_year)")
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
                    genres: row.games.curated_genres ?? row.games.genres ?? [],
                    tags: row.games.curated_tags ?? row.games.tags ?? [],
                    metacriticScore: row.games.metacritic_score,
                    releaseYear: row.games.curated_release_year
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
            
            // Batch fetch all friend usernames in one query
            struct UserInfo: Decodable {
                let id: String
                let username: String?
            }
            
            let allUserInfos: [UserInfo] = friendIds.isEmpty ? [] : try await SupabaseManager.shared.client
                .from("users")
                .select("id, username")
                .in("id", values: friendIds)
                .execute()
                .value
            
            let usernameMap = Dictionary(uniqueKeysWithValues: allUserInfos.map { ($0.id.lowercased(), $0.username ?? "Friend") })
            
            // Batch fetch all friends' ranked games in one query
            struct FriendGameRow: Decodable {
                let user_id: String
                let game_id: Int
                let rank_position: Int
                let canonical_game_id: Int?
                let games: FriendGameData
                
                struct FriendGameData: Decodable {
                    let rawg_id: Int
                }
            }
            
            let allFriendRows: [FriendGameRow] = friendIds.isEmpty ? [] : try await SupabaseManager.shared.client
                .from("user_games")
                .select("user_id, game_id, rank_position, canonical_game_id, games(rawg_id)")
                .in("user_id", values: friendIds)
                .not("rank_position", operator: .is, value: "null")
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            // Group by friend
            let rowsByFriend = Dictionary(grouping: allFriendRows, by: { $0.user_id.lowercased() })
            
            var friends: [FriendData] = []
            
            for friendId in friendIds {
                let friendRows = rowsByFriend[friendId.lowercased()] ?? []
                
                let friendGames = friendRows.map { row in
                    FriendRankedGame(
                        gameId: row.game_id,
                        rawgId: row.games.rawg_id,
                        canonicalGameId: row.canonical_game_id,
                        rankPosition: row.rank_position,
                        totalGames: friendRows.count
                    )
                }
                
                let tasteMatch = computeTasteMatch(
                    myGames: myGames,
                    friendGames: friendGames
                )
                
                friends.append(FriendData(
                    userId: friendId,
                    username: usernameMap[friendId.lowercased()] ?? "Friend",
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
