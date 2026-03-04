import SwiftUI

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    
    let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("GameCovers", isDirectory: true)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
    }
    
    // MARK: - Get image (memory → disk → network)
    func image(for urlString: String) async -> UIImage? {
        let key = cacheKey(for: urlString)
        
        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        
        // 2. Disk cache
        let filePath = cacheDirectory.appendingPathComponent(key)
        if let data = try? Data(contentsOf: filePath),
           let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
            return image
        }
        
        // 3. Deduplicated network fetch
        if let existingTask = activeTasks[key] {
            return await existingTask.value
        }
        
        let task = Task<UIImage?, Never> {
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return nil }
                
                // Save to disk
                try? data.write(to: filePath, options: .atomic)
                
                // Save to memory
                memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                
                return image
            } catch {
                return nil
            }
        }
        
        activeTasks[key] = task
        let result = await task.value
        activeTasks.removeValue(forKey: key)
        return result
    }
    
    // MARK: - Prefetch a batch of URLs
    func prefetch(urls: [String]) {
        for urlString in urls {
            let key = cacheKey(for: urlString)
            if memoryCache.object(forKey: key as NSString) != nil { continue }
            let filePath = cacheDirectory.appendingPathComponent(key)
            if fileManager.fileExists(atPath: filePath.path) { continue }
            
            Task {
                _ = await image(for: urlString)
            }
        }
    }
    
    // MARK: - Clear cache
    func clearDiskCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.removeAllObjects()
    }
    
    private func cacheKey(for urlString: String) -> String {
        let hash = urlString.utf8.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return "\(hash).jpg"
    }
}
