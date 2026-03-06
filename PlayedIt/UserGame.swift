import Foundation
import SwiftUI

enum GameStatus: String, Codable, CaseIterable {
    case played
    case playing
    case replaying
    case tried
    case abandoned

    var displayName: String {
        switch self {
        case .played: return "Played"
        case .playing: return "Playing"
        case .replaying: return "Replaying"
        case .tried: return "Tried"
        case .abandoned: return "Abandoned"
        }
    }

    var icon: String {
        switch self {
        case .played: return "checkmark.circle.fill"
        case .playing: return "gamecontroller.fill"
        case .replaying: return "arrow.counterclockwise.circle.fill"
        case .tried: return "hand.thumbsdown.fill"
        case .abandoned: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .played: return .primaryBlue
        case .playing: return .accentOrange
        case .replaying: return .teal
        case .tried: return .adaptiveGray
        case .abandoned: return .error
        }
    }
}

struct UserGame: Identifiable, Codable {
    let id: String
    let gameId: Int
    let userId: String
    var rankPosition: Int
    let platformPlayed: [String]
    let notes: String?
    let loggedAt: String?
    let canonicalGameId: Int?
    var status: GameStatus
    
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
        case status
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
