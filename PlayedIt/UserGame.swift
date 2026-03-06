import Foundation

struct UserGame: Identifiable, Codable {
    let id: String
    let gameId: Int
    let userId: String
    var rankPosition: Int
    let platformPlayed: [String]
    let notes: String?
    let loggedAt: String?
    let canonicalGameId: Int?
    
    // Game details (joined from games table)
    let gameTitle: String
    let gameCoverURL: String?
    let gameReleaseDate: String?
    let gameRawgId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gameId = "game_id"
        case userId = "user_id"
        case rankPosition = "rank_position"
        case platformPlayed = "platform_played"
        case notes
        case loggedAt = "logged_at"
        case canonicalGameId = "canonical_game_id"
        case gameTitle = "game_title"
        case gameCoverURL = "game_cover_url"
        case gameReleaseDate = "game_release_date"
        case gameRawgId = "game_rawg_id"
    }
}

extension UserGame {
    func toGame() -> Game {
        Game(
            id: gameId,
            rawgId: gameRawgId ?? 0,
            title: gameTitle,
            coverURL: gameCoverURL,
            genres: [],
            platforms: [],
            releaseDate: gameReleaseDate,
            metacriticScore: nil,
            added: nil,
            rating: nil,
            gameDescription: nil,
            gameDescriptionHtml: nil,
            tags: []
        )
    }
}
