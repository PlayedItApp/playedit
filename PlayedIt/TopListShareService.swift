import SwiftUI

@MainActor
class TopListShareService {
    static let shared = TopListShareService()

    func renderTopList(games: [UserGame], username: String) async -> UIImage? {
        let topGames = Array(games.prefix(5))
        guard !topGames.isEmpty else { return nil }

        // Pre-warm image cache
        await withTaskGroup(of: Void.self) { group in
            for game in topGames {
                if let url = game.gameCoverURL {
                    group.addTask { _ = await ImageCache.shared.image(for: url) }
                }
            }
        }

        let card = TopListShareCardView(username: username, games: topGames, cornerRadius: 0)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3.0

        guard let uiImage = renderer.uiImage else { return nil }
        return uiImage
    }
}
