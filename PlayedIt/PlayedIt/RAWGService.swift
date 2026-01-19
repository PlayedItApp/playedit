import Foundation

class RAWGService {
    static let shared = RAWGService()
    
    private let baseURL = "https://api.rawg.io/api"
    private var apiKey: String { Config.rawgAPIKey }
    
    private init() {}
    
    // MARK: - Search Games
    func searchGames(query: String) async throws -> [Game] {
        guard !query.isEmpty else { return [] }
        
        // Clean up the query - remove colons and extra spaces
        let cleanedQuery = query
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        
        let encodedQuery = cleanedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanedQuery
        let urlString = "\(baseURL)/games?key=\(apiKey)&search=\(encodedQuery)&page_size=40"
        
        guard let url = URL(string: urlString) else {
            throw RAWGError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RAWGError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let searchResponse = try decoder.decode(RAWGSearchResponse.self, from: data)
        
        let games = searchResponse.results.map { Game(from: $0) }
        
        // Sort by relevance to query
        let queryLower = query.lowercased()
        let queryWords = Set(queryLower.split(separator: " ").map { String($0) })
        
        let sortedGames = games.sorted { game1, game2 in
            let name1 = game1.title.lowercased()
            let name2 = game2.title.lowercased()
            
            let score1 = relevanceScore(name: name1, query: queryLower, queryWords: queryWords)
            let score2 = relevanceScore(name: name2, query: queryLower, queryWords: queryWords)
            
            if score1 == score2 {
                let year1 = Int(game1.releaseDate?.prefix(4) ?? "9999") ?? 9999
                let year2 = Int(game2.releaseDate?.prefix(4) ?? "9999") ?? 9999
                return year1 < year2
            }
            
            return score1 > score2
        }
        
        return Array(sortedGames.prefix(20))
    }

    private func relevanceScore(name: String, query: String, queryWords: Set<String>) -> Int {
        var score = 0
        
        // Exact match (highest priority)
        if name == query {
            score += 1000
        }
        // Name starts with query
        else if name.hasPrefix(query) {
            score += 500
        }
        // Name contains query as substring
        else if name.contains(query) {
            score += 300
        }
        
        // Bonus for name length similarity to query
        // Closer length = higher score (max 200 points)
        let lengthRatio = Double(query.count) / Double(max(name.count, 1))
        score += Int(lengthRatio * 200)
        
        // Penalize remasters, remakes, editions, DLC, demos
        let penaltyTerms = ["remaster", "remake", "edition", "dlc", "demo", "pack", "bundle", "collection", "definitive", "ultimate", "complete", "goty", "game of the year", "anniversary", "enhanced", "hd", "classic"]
        for term in penaltyTerms {
            if name.contains(term) && !query.contains(term) {
                score -= 100
            }
        }
        
        // Bonus for each query word found in title
        for word in queryWords {
            if name.contains(word) {
                score += 50
            }
        }
        
        return score
    }

    // MARK: - Get Game Details
    func getGameDetails(id: Int) async throws -> Game {
        let urlString = "\(baseURL)/games/\(id)?key=\(apiKey)"
        
        guard let url = URL(string: urlString) else {
            throw RAWGError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw RAWGError.invalidResponse
        }
        
        let decoder = JSONDecoder()
        let rawgGame = try decoder.decode(RAWGGame.self, from: data)
        
        return Game(from: rawgGame)
    }
}

// MARK: - Errors
enum RAWGError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .decodingError:
            return "Could not decode response"
        }
    }
}
