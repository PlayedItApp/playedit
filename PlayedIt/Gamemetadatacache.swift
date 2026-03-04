import Foundation

/// Simple in-memory cache for game descriptions and metacritic scores
/// so detail sheets open instantly on repeat views.
class GameMetadataCache {
    static let shared = GameMetadataCache()
    
    struct CachedMetadata {
        let description: String?
        let metacriticScore: Int?
        let releaseDate: String?
        let curatedGenres: [String]?
        let curatedTags: [String]?
        let curatedPlatforms: [String]?
        let curatedReleaseYear: Int?
    }
    
    private var cache: [Int: CachedMetadata] = [:]
    private let lock = NSLock()
    private let maxEntries = 500
    
    func get(gameId: Int) -> CachedMetadata? {
        lock.withLock { cache[gameId] }
    }
    
    func set(gameId: Int, description: String?, metacriticScore: Int?, releaseDate: String?, curatedGenres: [String]? = nil, curatedTags: [String]? = nil, curatedPlatforms: [String]? = nil, curatedReleaseYear: Int? = nil) {
        lock.withLock {
            if cache.count >= maxEntries, let firstKey = cache.keys.first {
                cache.removeValue(forKey: firstKey)
            }
            cache[gameId] = CachedMetadata(
                description: description,
                metacriticScore: metacriticScore,
                releaseDate: releaseDate,
                curatedGenres: curatedGenres,
                curatedTags: curatedTags,
                curatedPlatforms: curatedPlatforms,
                curatedReleaseYear: curatedReleaseYear
            )
        }
    }
}
