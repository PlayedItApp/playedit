import Foundation
import UIKit

final class LogCollector {
    static let shared = LogCollector()
    
    private var entries: [(Date, String)] = []
    private let queue = DispatchQueue(label: "com.playedit.logcollector")
    private let maxEntries = 500
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    private init() {}
    
    func log(_ message: String) {
        let timestamp = Date()
        queue.async {
            self.entries.append((timestamp, message))
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
        #if DEBUG
        print(message)
        #endif
    }
    
    func export() -> String {
        queue.sync {
            entries.map { "\(formatter.string(from: $0.0)) \($0.1)" }
                .joined(separator: "\n")
        }
    }
    
    func clear() {
        queue.async { self.entries.removeAll() }
    }
    
    func entryCount() -> Int {
        queue.sync { entries.count }
    }
}
