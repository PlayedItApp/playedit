import Foundation

struct UserGame: Identifiable, Codable {
    let id: String
    let gameId: Int
    let userId: String
    var rankPosition: Int
    let platformPlayed: [String]
    let notes: String?
    let loggedAt: String?
    
    // Game details (joined from games table)
    let gameTitle: String
    let gameCoverURL: String?
    let gameReleaseDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case gameId = "game_id"
        case userId = "user_id"
        case rankPosition = "rank_position"
        case platformPlayed = "platform_played"
        case notes
        case loggedAt = "logged_at"
        case gameTitle = "game_title"
        case gameCoverURL = "game_cover_url"
        case gameReleaseDate = "game_release_date"
    }
}

extension UserGame {
    func toGame() -> Game {
        Game(
            from: RAWGGame(
                id: gameId,
                name: gameTitle,
                backgroundImage: gameCoverURL,
                released: gameReleaseDate,
                metacritic: nil,
                genres: nil,
                platforms: nil
            )
        )
    }
}
