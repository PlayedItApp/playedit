import SwiftUI
import Auth
internal import PostgREST
import Supabase

@MainActor
class GameShareService {
    
    static let shared = GameShareService()
    
    func shareGame(
        gameTitle: String,
        coverURL: String?,
        rankPosition: Int? = nil,
        platforms: [String] = [],
        totalGames: Int = 0,
        gameId: Int
    ) async {
        guard let username = await fetchUsername() else { return }
        
        // Pre-fetch cover image so ImageRenderer doesn't deal with async loading
        let coverImage = await fetchCoverImage(urlString: coverURL)
        
        let cardView = GameShareCardView(
            gameTitle: gameTitle,
            coverURL: coverURL,
            rankPosition: rankPosition,
            username: username,
            platforms: platforms,
            totalGames: totalGames,
            coverImage: coverImage
        )
        
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = 3.0
        
        guard let image = renderer.uiImage else {
            debugLog("❌ Failed to render share card image")
            return
        }
        
        // Build URL with share context for OG image generation
        var urlString = "https://playedit.app/game/\(gameId)"
        var params: [String] = []
        if let rank = rankPosition { params.append("rank=\(rank)") }
        if totalGames > 0 { params.append("total=\(totalGames)") }
        params.append("user=\(username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username)")
        if !params.isEmpty { urlString += "?" + params.joined(separator: "&") }
        
        let shareURL = URL(string: urlString)!
        
        let activityVC = UIActivityViewController(
            activityItems: [shareURL],
            applicationActivities: nil
        )
        
        // Present
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            var presenter = rootVC
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            
            // iPad popover support
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            presenter.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Helpers
    
    private func fetchUsername() async -> String? {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return nil }
        
        do {
            struct UserRow: Decodable {
                let username: String?
            }
            
            let users: [UserRow] = try await SupabaseManager.shared.client
                .from("users")
                .select("username")
                .eq("id", value: userId.uuidString)
                .limit(1)
                .execute()
                .value
            
            return users.first?.username ?? "A friend"
        } catch {
            debugLog("❌ Error fetching username for share: \(error)")
            return nil
        }
    }
    
    private func fetchCoverImage(urlString: String?) async -> UIImage? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return UIImage(data: data)
        } catch {
            debugLog("⚠️ Couldn't fetch cover for share card: \(error)")
            return nil
        }
    }
}
