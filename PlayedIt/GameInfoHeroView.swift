import SwiftUI

struct GameInfoHeroView: View {
    let title: String
    let coverURL: String?
    let releaseDate: String?
    
    var metacriticScore: Int? = nil
    var gameDescription: String? = nil
    var isLoadingDescription: Bool = false
    var curatedGenres: [String]? = nil
    var curatedTags: [String]? = nil
    var curatedPlatforms: [String]? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Cover art
            CachedAsyncImage(url: coverURL) {
                GameArtworkPlaceholder(genre: nil, size: .large)
            }
            .frame(width: 160, height: 213)
            .cornerRadius(12)
            .clipped()
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            // Title
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Curated genres & tags
            if let genres = curatedGenres, !genres.isEmpty {
                genreTagChips(genres: genres, tags: curatedTags ?? [])
            } else if let tags = curatedTags, !tags.isEmpty {
                genreTagChips(genres: [], tags: tags)
            }
            
            // Release year + Metacritic
            if hasMetadata {
                HStack(spacing: 16) {
                    if let year = releaseDate?.prefix(4) {
                        Label(String(year) == "9999" ? "TBA" : String(year), systemImage: "calendar")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    if let score = metacriticScore, score > 0 {
                        HStack(spacing: 4) {
                            Text("Metacritic")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                            
                            Text("\(score)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(metacriticColor(score))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(metacriticColor(score).opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            // Platforms
            if let platforms = curatedPlatforms, !platforms.isEmpty {
                Text(platforms.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            
            // Description
            if isLoadingDescription {
                ProgressView()
                    .padding(.top, 4)
            } else if let desc = gameDescription, !desc.isEmpty {
                GameDescriptionView(text: desc)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private var hasMetadata: Bool {
        (releaseDate?.prefix(4)) != nil || (metacriticScore ?? 0) > 0
    }
    
    private func genreTagChips(genres: [String], tags: [String]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(genres, id: \.self) { genre in
                Text(genre)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primaryBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primaryBlue.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.primaryBlue.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(20)
            }
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.adaptiveSlate)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.adaptiveSilver.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.adaptiveSilver.opacity(0.35), lineWidth: 1)
                    )
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func metacriticColor(_ score: Int) -> Color {
        switch score {
        case 75...100: return .success
        case 50...74: return .accentOrange
        default: return .error
        }
    }
}
