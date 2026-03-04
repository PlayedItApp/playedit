import Foundation

// MARK: - Parsed CSV Game
struct CSVGameEntry: Identifiable {
    let id = UUID()
    let title: String
    let platform: String?
    let notes: String?
}

// MARK: - Matched CSV Game
struct MatchedCSVGame: Identifiable {
    let id = UUID()
    let csvTitle: String
    let csvPlatform: String?
    let csvNotes: String?
    let rawgId: Int?
    let rawgTitle: String?
    let rawgCoverUrl: String?
    let rawgGenres: [String]
    let rawgPlatforms: [String]
    let rawgReleaseDate: String?
    let rawgMetacriticScore: Int?
    
    var displayTitle: String { rawgTitle ?? csvTitle }
    var displayCoverUrl: String? { rawgCoverUrl }
    var isMatched: Bool { rawgId != nil }
    
    func toGame() -> Game {
        Game(
            from: RAWGGame(
                id: rawgId ?? 0,
                name: rawgTitle ?? csvTitle,
                backgroundImage: rawgCoverUrl,
                released: rawgReleaseDate,
                metacritic: rawgMetacriticScore,
                genres: rawgGenres.map { RAWGGenre(id: 0, name: $0) },
                platforms: rawgPlatforms.map { RAWGPlatformWrapper(platform: RAWGPlatform(id: 0, name: $0)) },
                added: nil,
                rating: nil,
                descriptionRaw: nil,
                descriptionHtml: nil,
                tags: nil
            )
        )
    }
}

// MARK: - CSV Import Service
class CSVImportService {
    static let shared = CSVImportService()
    
    private init() {}
    
    // MARK: - Accepted Platforms
    private static let canonicalPlatforms: [String] = [
        "Android", "Apple TV", "Apple Vision Pro",
        "Atari",
        "Sega Dreamcast",
        "Game Boy", "Game Boy Advance", "Game Boy Advance SP",
        "Game Boy Color", "Game Gear", "GameCube",
        "iOS",
        "Linux",
        "macOS", "Meta Quest 3", "Meta Quest 3S",
        "Neo Geo", "NES", "Nintendo 3DS", "Nintendo 64", "Nintendo DS",
        "Nintendo Switch", "Nintendo Switch 2",
        "Oculus Quest", "Oculus Quest 2", "Oculus Rift",
        "PC",
        "PlayStation", "PlayStation 2", "PlayStation 3",
        "PlayStation 4", "PlayStation 5",
        "PlayStation Portable (PSP)", "PlayStation Vita",
        "PlayStation VR", "PlayStation VR2",
        "SNES", "Steam Deck",
        "Wii", "Wii U",
        "Xbox", "Xbox 360", "Xbox One",
        "Xbox Series X/S"
    ]
    
    // Common abbreviations → canonical platform
    private static let platformAliases: [String: String] = {
        var aliases: [String: String] = [:]
        
        // Build case-insensitive exact matches
        for platform in canonicalPlatforms {
            aliases[platform.lowercased()] = platform
        }
        
        // Common abbreviations
        aliases["ps1"] = "PlayStation"
        aliases["ps2"] = "PlayStation 2"
        aliases["ps3"] = "PlayStation 3"
        aliases["ps4"] = "PlayStation 4"
        aliases["ps5"] = "PlayStation 5"
        aliases["playstation 1"] = "PlayStation"
        aliases["playstation1"] = "PlayStation"
        aliases["playstation2"] = "PlayStation 2"
        aliases["playstation3"] = "PlayStation 3"
        aliases["playstation4"] = "PlayStation 4"
        aliases["playstation5"] = "PlayStation 5"
        aliases["psx"] = "PlayStation"
        aliases["psp"] = "PlayStation Portable (PSP)"
        aliases["ps vita"] = "PlayStation Vita"
        aliases["vita"] = "PlayStation Vita"
        aliases["psvr"] = "PlayStation VR"
        aliases["psvr2"] = "PlayStation VR2"
        aliases["switch"] = "Nintendo Switch"
        aliases["switch 2"] = "Nintendo Switch 2"
        aliases["n64"] = "Nintendo 64"
        aliases["3ds"] = "Nintendo 3DS"
        aliases["ds"] = "Nintendo DS"
        aliases["gba"] = "Game Boy Advance"
        aliases["gba sp"] = "Game Boy Advance SP"
        aliases["gbc"] = "Game Boy Color"
        aliases["gc"] = "GameCube"
        aliases["gamecube"] = "GameCube"
        aliases["super nintendo"] = "SNES"
        aliases["super nes"] = "SNES"
        aliases["nes"] = "NES"
        aliases["snes"] = "SNES"
        aliases["wii u"] = "Wii U"
        aliases["wiiu"] = "Wii U"
        aliases["dreamcast"] = "Sega Dreamcast"
        aliases["neo geo"] = "Neo Geo"
        aliases["neogeo"] = "Neo Geo"
        aliases["xbox series x"] = "Xbox Series X/S"
        aliases["xbox series s"] = "Xbox Series X/S"
        aliases["xbox series x/s"] = "Xbox Series X/S"
        aliases["xbox series xs"] = "Xbox Series X/S"
        aliases["xsx"] = "Xbox Series X/S"
        aliases["xss"] = "Xbox Series X/S"
        aliases["xbone"] = "Xbox One"
        aliases["xbox 360"] = "Xbox 360"
        aliases["xbox 1"] = "Xbox One"
        aliases["xbox one"] = "Xbox One"
        aliases["original xbox"] = "Xbox"
        aliases["pc"] = "PC"
        aliases["windows"] = "PC"
        aliases["mac"] = "macOS"
        aliases["macos"] = "macOS"
        aliases["steam deck"] = "Steam Deck"
        aliases["steamdeck"] = "Steam Deck"
        aliases["quest 3"] = "Meta Quest 3"
        aliases["quest 3s"] = "Meta Quest 3S"
        aliases["quest"] = "Oculus Quest"
        aliases["quest 2"] = "Oculus Quest 2"
        aliases["oculus"] = "Oculus Rift"
        aliases["apple tv"] = "Apple TV"
        aliases["vision pro"] = "Apple Vision Pro"
        aliases["iphone"] = "iOS"
        aliases["ipad"] = "iOS"
        aliases["mobile"] = "iOS"
        
        return aliases
    }()
    
    // MARK: - Parse CSV
    func parseCSV(from url: URL) throws -> [CSVGameEntry] {
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.fileAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSVRows(content)
        
        guard rows.count > 1 else {
            throw CSVImportError.emptyFile
        }
        
        let header = rows[0].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        guard let titleIndex = header.firstIndex(of: "game title") else {
            throw CSVImportError.missingHeader
        }
        
        let platformIndex = header.firstIndex(of: "platform")
        let notesIndex = header.firstIndex(of: "notes")
        
        var entries: [CSVGameEntry] = []
        var seenTitles: Set<String> = []
        
        for row in rows.dropFirst() {
            guard titleIndex < row.count else { continue }
            
            let title = row[titleIndex].trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            
            // Deduplicate within the CSV
            let titleKey = title.lowercased()
            guard !seenTitles.contains(titleKey) else { continue }
            seenTitles.insert(titleKey)
            
            let platform: String? = {
                guard let idx = platformIndex, idx < row.count else { return nil }
                let raw = row[idx].trimmingCharacters(in: .whitespaces)
                guard !raw.isEmpty else { return nil }
                return Self.normalizePlatform(raw)
            }()
            
            let notes: String? = {
                guard let idx = notesIndex, idx < row.count else { return nil }
                let raw = row[idx].trimmingCharacters(in: .whitespaces)
                return raw.isEmpty ? nil : raw
            }()
            
            entries.append(CSVGameEntry(title: title, platform: platform, notes: notes))
        }
        
        guard !entries.isEmpty else {
            throw CSVImportError.noGames
        }
        
        return entries
    }
    
    // MARK: - Platform Normalization
    static func normalizePlatform(_ input: String) -> String? {
        let key = input.lowercased().trimmingCharacters(in: .whitespaces)
        return platformAliases[key]
    }
    
    // MARK: - Match Games Against RAWG
    func matchGames(
        entries: [CSVGameEntry],
        progressCallback: @escaping (Int, Int) -> Void
    ) async throws -> [MatchedCSVGame] {
        var matched: [MatchedCSVGame] = []
        
        for (index, entry) in entries.enumerated() {
            await MainActor.run {
                progressCallback(index + 1, entries.count)
            }
            
            do {
                let results = try await RAWGService.shared.searchGames(query: entry.title)
                
                if let best = results.first {
                    matched.append(MatchedCSVGame(
                        csvTitle: entry.title,
                        csvPlatform: entry.platform,
                        csvNotes: entry.notes,
                        rawgId: best.rawgId,
                        rawgTitle: best.title,
                        rawgCoverUrl: best.coverURL,
                        rawgGenres: best.genres,
                        rawgPlatforms: best.platforms,
                        rawgReleaseDate: best.releaseDate,
                        rawgMetacriticScore: best.metacriticScore
                    ))
                } else {
                    matched.append(MatchedCSVGame(
                        csvTitle: entry.title,
                        csvPlatform: entry.platform,
                        csvNotes: entry.notes,
                        rawgId: nil,
                        rawgTitle: nil,
                        rawgCoverUrl: nil,
                        rawgGenres: [],
                        rawgPlatforms: [],
                        rawgReleaseDate: nil,
                        rawgMetacriticScore: nil
                    ))
                }
            } catch {
                debugLog("⚠️ RAWG search failed for '\(entry.title)': \(error)")
                matched.append(MatchedCSVGame(
                    csvTitle: entry.title,
                    csvPlatform: entry.platform,
                    csvNotes: entry.notes,
                    rawgId: nil,
                    rawgTitle: nil,
                    rawgCoverUrl: nil,
                    rawgGenres: [],
                    rawgPlatforms: [],
                    rawgReleaseDate: nil,
                    rawgMetacriticScore: nil
                ))
            }
            
            // Small delay to be respectful of RAWG rate limits
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        
        return matched
    }
    
    // MARK: - CSV Row Parser (handles quoted fields)
    private func parseCSVRows(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in content {
            if inQuotes {
                if char == "\"" {
                    // Check for escaped quote
                    inQuotes = false
                } else {
                    currentField.append(char)
                }
            } else {
                switch char {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\n", "\r\n":
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                case "\r":
                    // Skip standalone \r, will be handled by \n
                    break
                default:
                    currentField.append(char)
                }
            }
        }
        
        // Final row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            if !currentRow.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                rows.append(currentRow)
            }
        }
        
        return rows
    }
}

// MARK: - Errors
enum CSVImportError: Error, LocalizedError {
    case fileAccessDenied
    case emptyFile
    case missingHeader
    case noGames
    
    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Couldn't access that file. Try again?"
        case .emptyFile:
            return "That file looks empty. Make sure your CSV has games listed below the header row."
        case .missingHeader:
            return "Couldn't read this file. Make sure you're using the PlayedIt template."
        case .noGames:
            return "No games found in this file. Make sure your CSV has games listed below the header row."
        }
    }
}
