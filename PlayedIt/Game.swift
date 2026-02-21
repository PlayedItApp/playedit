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
    let added: Int?
    let rating: Double?
    let descriptionRaw: String?
    let descriptionHtml: String?
    let tags: [RAWGTag]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, released, metacritic, genres, platforms, added, rating
        case backgroundImage = "background_image"
        case descriptionRaw = "description_raw"
        case descriptionHtml = "description"
        case tags
    }
}

struct RAWGTag: Codable {
    let id: Int
    let name: String
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
    let added: Int?
    let rating: Double?
    let gameDescription: String?
    let gameDescriptionHtml: String?
    let tags: [String]
    
    init(id: Int, rawgId: Int, title: String, coverURL: String?, genres: [String], platforms: [String], releaseDate: String?, metacriticScore: Int?, added: Int?, rating: Double?, gameDescription: String?, gameDescriptionHtml: String? = nil, tags: [String]) {
            self.id = id
            self.rawgId = rawgId
            self.title = title
            self.coverURL = coverURL
            self.genres = genres
            self.platforms = platforms
            self.releaseDate = releaseDate
            self.metacriticScore = metacriticScore
            self.added = added
            self.rating = rating
            self.gameDescription = gameDescription
            self.gameDescriptionHtml = gameDescriptionHtml
            self.tags = tags
        }
    
    init(from rawgGame: RAWGGame) {
        self.id = rawgGame.id
        self.rawgId = rawgGame.id
        self.title = rawgGame.name
        self.coverURL = rawgGame.backgroundImage
        self.genres = rawgGame.genres?.map { $0.name } ?? []
        self.platforms = rawgGame.platforms?.map { $0.platform.name } ?? []
        self.releaseDate = rawgGame.released
        self.metacriticScore = rawgGame.metacritic
        self.added = rawgGame.added
        self.rating = rawgGame.rating
        self.gameDescription = rawgGame.descriptionRaw
        self.gameDescriptionHtml = rawgGame.descriptionHtml
        self.tags = rawgGame.tags?.map { $0.name } ?? []
    }
}
