import Foundation

class RAWGService {
    static let shared = RAWGService()
    
    private let baseURL = "https://api.rawg.io/api"
    private var apiKey: String { Config.rawgAPIKey }
    
    private init() {}
    
    // MARK: - Search Games
    func searchGames(query: String) async throws -> [Game] {
        guard !query.isEmpty else { return [] }
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/games?key=\(apiKey)&search=\(encodedQuery)&page_size=20&search_precise=true"
        
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
                
        // Sort: exact matches first, then by year (newest first)
        let sortedGames = games.sorted { game1, game2 in
            let query = query.lowercased()
            let name1 = game1.title.lowercased()
            let name2 = game2.title.lowercased()
            
            // Exact match goes first
            let isExact1 = name1 == query
            let isExact2 = name2 == query
            
            if isExact1 && !isExact2 { return true }
            if isExact2 && !isExact1 { return false }
            
            // Then sort by year (newest first)
            let year1 = Int(game1.releaseDate?.prefix(4) ?? "0") ?? 0
            let year2 = Int(game2.releaseDate?.prefix(4) ?? "0") ?? 0
            
            return year1 > year2
        }
        
        return sortedGames
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
