import Foundation

class RAWGService {
    static let shared = RAWGService()
    
    private let baseURL = "https://api.rawg.io/api"
    private var apiKey: String { Config.rawgAPIKey }
    
    private init() {}
    
    // MARK: - Search Games
    func searchGames(query: String) async throws -> [Game] {
        guard !query.isEmpty else { return [] }
        
        // Try original query first
        let results = try await performSearch(query: query)
        
        // If we got few results and query might be missing punctuation, try variations
        if results.count < 5 {
            let variations = generateQueryVariations(query)
            for variation in variations where variation != query.lowercased() {
                let moreResults = try await performSearch(query: variation)
                if moreResults.count > results.count {
                    return moreResults
                }
            }
        }
        
        return results
    }

    private func performSearch(query: String) async throws -> [Game] {
        let cleanedQuery = query
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)

        let encodedQuery = cleanedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cleanedQuery
        let urlString = "\(baseURL)/games?key=\(apiKey)&search=\(encodedQuery)&search_precise=true&page_size=40"

        print("🔍 Searching for: \(cleanedQuery)")
        
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

    private func generateQueryVariations(_ query: String) -> [String] {
        var variations: [String] = []
        let lower = query.lowercased()
        
        // Add apostrophe after common name endings
        let apostropheNames = [
            "baldurs": "baldur's",
            "zeldas": "zelda's",
            "luigis": "luigi's",
            "marios": "mario's",
            "simons": "simon's",
            "spyros": "spyro's",
            "crashs": "crash's",
            "kirbys": "kirby's"
        ]
        
        var modified = lower
        for (without, with) in apostropheNames {
            if modified.contains(without) {
                modified = modified.replacingOccurrences(of: without, with: with)
            }
        }
        if modified != lower {
            variations.append(modified)
        }
        
        // Convert trailing numbers to roman numerals
        let digitToRoman = [
            " 1": " I", " 2": " II", " 3": " III", " 4": " IV", " 5": " V",
            " 6": " VI", " 7": " VII", " 8": " VIII", " 9": " IX", " 10": " X"
        ]
        
        for (digit, roman) in digitToRoman {
            if modified.hasSuffix(digit.lowercased()) {
                let romanVersion = String(modified.dropLast(digit.count - 1)) + roman
                variations.append(romanVersion)
                break
            }
        }
        
        return variations
    }

    private func relevanceScore(name: String, query: String, queryWords: Set<String>) -> Int {
        var score = 0
        
        // Normalize both for comparison
        let normalizedName = normalizeForMatching(name)
        let normalizedQuery = normalizeForMatching(query)
        
        // Exact match (highest priority)
        if normalizedName == normalizedQuery {
            score += 1000
        }
        // Name starts with query
        else if normalizedName.hasPrefix(normalizedQuery) {
            score += 500
        }
        // Name contains query as substring
        else if normalizedName.contains(normalizedQuery) {
            score += 300
        }
        
        // Bonus for name length similarity to query
        let lengthRatio = Double(normalizedQuery.count) / Double(max(normalizedName.count, 1))
        score += Int(lengthRatio * 200)
        
        // Penalize remasters, remakes, editions, DLC, demos
        let penaltyTerms = ["remaster", "remake", "edition", "dlc", "demo", "pack", "bundle", "collection", "definitive", "ultimate", "complete", "goty", "game of the year", "anniversary", "enhanced", "hd", "classic"]
        for term in penaltyTerms {
            if normalizedName.contains(term) && !normalizedQuery.contains(term) {
                score -= 100
            }
        }
        
        // Bonus for each query word found in title
        for word in queryWords {
            let normalizedWord = word.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            if normalizedName.contains(normalizedWord) {
                score += 50
            }
        }
        
        return score
    }
    
    private func normalizeSearchQuery(_ query: String) -> String {
        var normalized = query.lowercased()
        
        // Remove punctuation that causes mismatches
        normalized = normalized.replacingOccurrences(of: "'", with: "")
        normalized = normalized.replacingOccurrences(of: "'", with: "")
        normalized = normalized.replacingOccurrences(of: ":", with: " ")
        normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        
        // Common game name substitutions
        let substitutions = [
            "baldurs gate": "baldur's gate",
            "zeldas": "zelda",
            "witcher3": "witcher 3",
            "gta": "grand theft auto",
            "cod": "call of duty",
            "ff": "final fantasy",
            "re": "resident evil",
            "mgs": "metal gear solid"
        ]
        
        for (shorthand, full) in substitutions {
            if normalized.contains(shorthand) {
                normalized = normalized.replacingOccurrences(of: shorthand, with: full)
            }
        }
        
        // Number to roman numeral mapping for trailing numbers
        let digitToRoman = [
            " 1": " i", " 2": " ii", " 3": " iii", " 4": " iv", " 5": " v",
            " 6": " vi", " 7": " vii", " 8": " viii", " 9": " ix", " 10": " x"
        ]
        
        for (digit, roman) in digitToRoman {
            if normalized.hasSuffix(digit) {
                normalized = String(normalized.dropLast(digit.count)) + roman
                break
            }
        }
        
        return normalized
    }
    
    private func normalizeForMatching(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        
        // Convert roman numerals to digits
        let romanToDigit = [
            " iii": " 3", " ii": " 2", " iv": " 4", " vi": " 6",
            " vii": " 7", " viii": " 8", " ix": " 9", " x": " 10",
            " v": " 5", " i": " 1"
        ]
        
        for (roman, digit) in romanToDigit {
            if normalized.hasSuffix(roman) || normalized.contains(roman + " ") {
                normalized = normalized.replacingOccurrences(of: roman, with: digit)
            }
        }
        
        // Convert digits to roman numerals (so "3" matches "III")
        let digitToRoman = [
            " 10": " x", " 9": " ix", " 8": " viii", " 7": " vii",
            " 6": " vi", " 5": " v", " 4": " iv", " 3": " iii",
            " 2": " ii", " 1": " i"
        ]
        
        // Create alternate version with digits converted
        var digitVersion = normalized
        for (digit, roman) in digitToRoman {
            if digitVersion.hasSuffix(digit) || digitVersion.contains(digit + " ") {
                digitVersion = digitVersion.replacingOccurrences(of: digit, with: roman)
            }
        }
        
        // Return whichever has digits (standardize on digits)
        for (roman, digit) in romanToDigit {
            normalized = normalized.replacingOccurrences(of: roman, with: digit)
        }
        
        return normalized
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
