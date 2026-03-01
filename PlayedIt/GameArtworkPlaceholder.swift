import SwiftUI

// MARK: - Genre Artwork Placeholder
// A polished, genre-aware placeholder for games missing cover art.
// Drop-in replacement for every `placeholder:` block in AsyncImage calls.
//
// Usage:
//   GameArtworkPlaceholder(genre: game.genres.first)
//   GameArtworkPlaceholder(genre: game.genres.first, size: .large)

struct GameArtworkPlaceholder: View {
    let genre: String?
    var size: PlaceholderSize = .medium
    
    enum PlaceholderSize {
        case small   // List rows, compact cells (30-50pt)
        case medium  // Standard cards, grid items (60-150pt)
        case large   // Detail views, hero images (200pt+)
        
        var iconSize: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 24
            case .large: return 40
            }
        }
        
        var labelFont: Font {
            switch self {
            case .small: return .system(size: 7, weight: .semibold, design: .rounded)
            case .medium: return .system(size: 9, weight: .semibold, design: .rounded)
            case .large: return .system(size: 13, weight: .semibold, design: .rounded)
            }
        }
        
        var showLabel: Bool {
            switch self {
            case .small: return false
            case .medium, .large: return true
            }
        }
    }
    
    private var config: GenreConfig {
        GenreConfig.forGenre(genre)
    }
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [config.colorTop, config.colorBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle pattern overlay for depth
            config.colorTop
                .opacity(0.15)
                .blendMode(.overlay)
            
            // Icon + optional label
            VStack(spacing: size == .large ? 8 : 4) {
                Image(systemName: config.icon)
                    .font(.system(size: size.iconSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                
                if size.showLabel, let label = genre {
                    Text(label.uppercased())
                        .font(size.labelFont)
                        .foregroundStyle(.white.opacity(0.6))
                        .tracking(0.5)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Genre Configuration
private struct GenreConfig {
    let colorTop: Color
    let colorBottom: Color
    let icon: String
    
    static func forGenre(_ genre: String?) -> GenreConfig {
        guard let genre = genre?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return fallback
        }
        
        switch genre {
        // ── Combat / Action ──────────────────────────────────
        case "action":
            return GenreConfig(
                colorTop: Color(hex: "E05252"),
                colorBottom: Color(hex: "9B2C2C"),
                icon: "bolt.fill"
            )
        case "action adventure":
            return GenreConfig(
                colorTop: Color(hex: "DD6B4E"),
                colorBottom: Color(hex: "9C3D24"),
                icon: "figure.run"
            )
        case "adventure":
            return GenreConfig(
                colorTop: Color(hex: "48A89A"),
                colorBottom: Color(hex: "2C6E63"),
                icon: "map.fill"
            )
        case "shooter":
            return GenreConfig(
                colorTop: Color(hex: "64748B"),
                colorBottom: Color(hex: "334155"),
                icon: "scope"
            )
        case "fighting":
            return GenreConfig(
                colorTop: Color(hex: "DC6843"),
                colorBottom: Color(hex: "9C3A1D"),
                icon: "flame.fill"
            )
        case "battle royale":
            return GenreConfig(
                colorTop: Color(hex: "F59E0B"),
                colorBottom: Color(hex: "B45309"),
                icon: "trophy.fill"
            )
            
        // ── Exploration / Story ──────────────────────────────
        case "rpg":
            return GenreConfig(
                colorTop: Color(hex: "8B5CF6"),
                colorBottom: Color(hex: "5B21B6"),
                icon: "shield.fill"
            )
        case "mmorpg":
            return GenreConfig(
                colorTop: Color(hex: "7C3AED"),
                colorBottom: Color(hex: "4C1D95"),
                icon: "person.3.fill"
            )
        case "visual novel":
            return GenreConfig(
                colorTop: Color(hex: "EC4899"),
                colorBottom: Color(hex: "9D174D"),
                icon: "book.fill"
            )
        case "horror":
            return GenreConfig(
                colorTop: Color(hex: "4A3D5C"),
                colorBottom: Color(hex: "1E1529"),
                icon: "moon.fill"
            )
        case "survival":
            return GenreConfig(
                colorTop: Color(hex: "6B7F3A"),
                colorBottom: Color(hex: "3F4A23"),
                icon: "leaf.fill"
            )
            
        // ── Precision / Skill ────────────────────────────────
        case "platformer":
            return GenreConfig(
                colorTop: Color(hex: "3B82F6"),
                colorBottom: Color(hex: "1D4ED8"),
                icon: "arrow.up.right"
            )
        case "puzzle":
            return GenreConfig(
                colorTop: Color(hex: "06B6D4"),
                colorBottom: Color(hex: "0E7490"),
                icon: "puzzlepiece.fill"
            )
        case "rhythm":
            return GenreConfig(
                colorTop: Color(hex: "D946EF"),
                colorBottom: Color(hex: "86198F"),
                icon: "music.note"
            )
        case "racing":
            return GenreConfig(
                colorTop: Color(hex: "EF4444"),
                colorBottom: Color(hex: "991B1B"),
                icon: "car.fill"
            )
            
        // ── Strategy / Building ──────────────────────────────
        case "strategy":
            return GenreConfig(
                colorTop: Color(hex: "2563EB"),
                colorBottom: Color(hex: "1E3A5F"),
                icon: "chess.fill" // NOTE: if < iOS 17, use "square.grid.3x3.fill"
            )
        case "simulation":
            return GenreConfig(
                colorTop: Color(hex: "10B981"),
                colorBottom: Color(hex: "047857"),
                icon: "gearshape.fill"
            )
        case "sandbox":
            return GenreConfig(
                colorTop: Color(hex: "F59E0B"),
                colorBottom: Color(hex: "92400E"),
                icon: "cube.fill"
            )
        case "card game":
            return GenreConfig(
                colorTop: Color(hex: "6366F1"),
                colorBottom: Color(hex: "3730A3"),
                icon: "suit.spade.fill"
            )
            
        // ── Other ────────────────────────────────────────────
        case "sports":
            return GenreConfig(
                colorTop: Color(hex: "22C55E"),
                colorBottom: Color(hex: "15803D"),
                icon: "sportscourt.fill"
            )
        case "roguelike":
            return GenreConfig(
                colorTop: Color(hex: "A855F7"),
                colorBottom: Color(hex: "6B21A8"),
                icon: "dice.fill"
            )
        case "indie":
            return GenreConfig(
                colorTop: Color(hex: "F472B6"),
                colorBottom: Color(hex: "BE185D"),
                icon: "sparkles"
            )
            
        default:
            return fallback
        }
    }
    
    // Fallback: PlayedIt brand blue gradient
    static let fallback = GenreConfig(
        colorTop: Color(hex: "4A7FB5"),
        colorBottom: Color(hex: "3D5A73"),
        icon: "gamecontroller.fill"
    )
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Large - detail view
            GameArtworkPlaceholder(genre: "RPG", size: .large)
                .frame(width: 150, height: 200)
                .cornerRadius(12)
            
            // Medium - grid/card
            HStack(spacing: 12) {
                GameArtworkPlaceholder(genre: "Action", size: .medium)
                    .frame(width: 100, height: 130)
                    .cornerRadius(8)
                GameArtworkPlaceholder(genre: "Horror", size: .medium)
                    .frame(width: 100, height: 130)
                    .cornerRadius(8)
                GameArtworkPlaceholder(genre: "Puzzle", size: .medium)
                    .frame(width: 100, height: 130)
                    .cornerRadius(8)
            }
            
            // Small - list rows
            HStack(spacing: 8) {
                GameArtworkPlaceholder(genre: "Shooter", size: .small)
                    .frame(width: 30, height: 40)
                    .cornerRadius(4)
                GameArtworkPlaceholder(genre: nil, size: .small)
                    .frame(width: 30, height: 40)
                    .cornerRadius(4)
            }
            
            // All genres showcase
            Text("All Genres").font(.headline).padding(.top)
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80))
            ], spacing: 10) {
                ForEach([
                    "Action", "Action Adventure", "Adventure", "RPG",
                    "Shooter", "Platformer", "Strategy", "Simulation",
                    "Puzzle", "Racing", "Fighting", "Sports",
                    "Horror", "Survival", "Sandbox", "Roguelike",
                    "Rhythm", "Visual Novel", "Card Game", "MMORPG",
                    "Battle Royale", "Indie"
                ], id: \.self) { genre in
                    VStack(spacing: 4) {
                        GameArtworkPlaceholder(genre: genre, size: .medium)
                            .frame(width: 80, height: 105)
                            .cornerRadius(8)
                        Text(genre)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
