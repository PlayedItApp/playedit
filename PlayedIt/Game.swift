import Foundation

// MARK: - RAWG API Response
struct RAWGSearchResponse: Codable {
    let results: [RAWGGame]
}

struct RAWGGame: Codable, Identifiable {
    let id: Int
    let name: String
    let backgroundImage: String?
    let released: String?
    let metacritic: Int?
    let genres: [RAWGGenre]?
    let platforms: [RAWGPlatformWrapper]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, released, metacritic, genres, platforms
        case backgroundImage = "background_image"
    }
}

struct RAWGGenre: Codable {
    let id: Int
    let name: String
}

struct RAWGPlatformWrapper: Codable {
    let platform: RAWGPlatform
}

struct RAWGPlatform: Codable {
    let id: Int
    let name: String
}

// MARK: - App Game Model
struct Game: Identifiable, Codable {
    let id: Int
    let rawgId: Int
    let title: String
    let coverURL: String?
    let genres: [String]
    let platforms: [String]
    let releaseDate: String?
    let metacriticScore: Int?
    
    init(from rawgGame: RAWGGame) {
        self.id = rawgGame.id
        self.rawgId = rawgGame.id
        self.title = rawgGame.name
        self.coverURL = rawgGame.backgroundImage
        self.genres = rawgGame.genres?.map { $0.name } ?? []
        self.platforms = rawgGame.platforms?.map { $0.platform.name } ?? []
        self.releaseDate = rawgGame.released
        self.metacriticScore = rawgGame.metacritic
    }
}
