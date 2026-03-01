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
    }
    
    private var cache: [Int: CachedMetadata] = [:] // keyed by gameId
    
    func get(gameId: Int) -> CachedMetadata? {
        cache[gameId]
    }
    
    func set(gameId: Int, description: String?, metacriticScore: Int?, releaseDate: String?, curatedGenres: [String]? = nil, curatedTags: [String]? = nil) {
        cache[gameId] = CachedMetadata(
            description: description,
            metacriticScore: metacriticScore,
            releaseDate: releaseDate,
            curatedGenres: curatedGenres,
            curatedTags: curatedTags
        )
    }
}
