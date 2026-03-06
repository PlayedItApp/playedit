import Foundation
import Combine
import Auth
internal import PostgREST
import Supabase

@MainActor
final class FeedPreloader: ObservableObject {
    static let shared = FeedPreloader()
    @Published var combinedFeed: [FeedEntry] = []
    private(set) var hasPreloaded = false

    func preload() async {
        guard !hasPreloaded else { return }
        await fetchAndCache()
        hasPreloaded = true
    }

    private func fetchAndCache() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }

        do {
            struct Friendship: Decodable {
                let user_id: String
                let friend_id: String
            }
            let friendships: [Friendship] = try await SupabaseManager.shared.client
                .from("friendships")
                .select("user_id, friend_id")
                .or("user_id.eq.\(userId.uuidString),friend_id.eq.\(userId.uuidString)")
                .eq("status", value: "accepted")
                .execute()
                .value

            var feedUserIds = friendships.map { f in
                f.user_id.lowercased() == userId.uuidString.lowercased() ? f.friend_id : f.user_id
            }
            feedUserIds.append(userId.uuidString)

            struct CoverRow: Decodable {
                let id: String
                let post_type: String
                let user_games: UGRow?
                let metadata: MetaRow?
                struct UGRow: Decodable {
                    let games: GRow?
                    struct GRow: Decodable {
                        let cover_url: String?
                    }
                }
                struct MetaRow: Decodable {
                    let game_cover_url: String?
                }
            }

            var posts: [CoverRow] = try await SupabaseManager.shared.client
                .from("feed_posts")
                .select("id, post_type, metadata, user_games(games(cover_url))")
                .in("user_id", values: feedUserIds)
                .is("batch_post_id", value: nil)
                .order("created_at", ascending: false)
                .limit(30)
                .execute()
                .value

            let batchIds = posts.filter { $0.post_type == "batch_ranked" || $0.post_type == "batch_want_to_play" }.map { $0.id }

            if !batchIds.isEmpty {
                let children: [CoverRow] = try await SupabaseManager.shared.client
                    .from("feed_posts")
                    .select("id, post_type, metadata, user_games(games(cover_url))")
                    .in("batch_post_id", values: batchIds)
                    .execute()
                    .value
                posts.append(contentsOf: children)
            }

            let urls = posts.compactMap { $0.user_games?.games?.cover_url ?? $0.metadata?.game_cover_url }
            
            // Await the first 15 URLs (above-the-fold) before dismissing splash
            let priorityUrls = Array(urls.prefix(30))
            await withTaskGroup(of: Void.self) { group in
                for url in priorityUrls {
                    group.addTask {
                        _ = await ImageCache.shared.image(for: url)
                    }
                }
                for await _ in group { }
            }

            // Fire-and-forget the rest
            ImageCache.shared.prefetch(urls: Array(urls.dropFirst(30)))
        } catch {
            // best-effort
        }
    }
}
