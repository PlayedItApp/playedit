import SwiftUI

final class ImageCache {
    static let shared = ImageCache()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var activeTasks: [String: Task<UIImage?, Never>] = [:]
    
    private init() {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("GameCovers", isDirectory: true)
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 200
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100MB
        trimDiskCacheIfNeeded()
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
        let diskImage = await Task.detached(priority: .background, operation: { () -> UIImage? in
            guard let data = try? Data(contentsOf: filePath),
                  let image = UIImage(data: data) else { return nil }
            return image
        }).value
        if let image = diskImage {
            memoryCache.setObject(image, forKey: key as NSString, cost: 0)
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
                let dataToWrite = data
                Task.detached(priority: .background) {
                    try? dataToWrite.write(to: filePath, options: .atomic)
                }
                
                // Save to memory
                memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
                trimDiskCacheIfNeeded()
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
            
            Task { [weak self] in
                _ = await self?.image(for: urlString)
            }
        }
    }
    
    // MARK: - Trim disk cache (keep newest files under limit)
    private func trimDiskCacheIfNeeded(maxBytes: Int = 150 * 1024 * 1024, maxAgeDays: Int = 30) {
        Task.detached(priority: .background) { [cacheDirectory, fileManager] in
            guard let files = try? fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 86400)

            // Sort oldest-access first so we evict those first
            let sorted = files.compactMap { url -> (url: URL, size: Int, accessed: Date)? in
                let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey])
                guard let size = vals?.fileSize, let accessed = vals?.contentAccessDate else { return nil }
                return (url, size, accessed)
            }.sorted { $0.accessed < $1.accessed }

            // Pass 1: remove anything older than maxAgeDays
            var remaining = sorted.filter { entry in
                if entry.accessed < cutoff {
                    try? fileManager.removeItem(at: entry.url)
                    return false
                }
                return true
            }

            // Pass 2: evict oldest until under byte limit
            var totalBytes = remaining.reduce(0) { $0 + $1.size }
            while totalBytes > maxBytes, let oldest = remaining.first {
                try? fileManager.removeItem(at: oldest.url)
                totalBytes -= oldest.size
                remaining.removeFirst()
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
