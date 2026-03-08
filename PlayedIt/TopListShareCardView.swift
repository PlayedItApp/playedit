import SwiftUI

struct TopListShareCardView: View {
    let username: String
    let games: [UserGame]
    var cornerRadius: CGFloat = 24 // top 5, already sorted by rank
    
    private func cacheKey(for urlString: String) -> String {
        let key = urlString.utf8.reduce(into: UInt64(5381)) { result, byte in
            result = result &* 33 &+ UInt64(byte)
        }
        return "\(key).jpg"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Branding header
            HStack {
                HStack(spacing: 6) {
                    PlayedItShareLogo(size: 20)
                    PlayedItShareWordmark(size: 15)
                }
                Spacer()
                Text("playedit.app")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Title
            HStack {
                Text("\(username)'s Top \(games.count)")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            // Game list
            VStack(spacing: 10) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    HStack(spacing: 12) {
                        Text("#\(index + 1)")
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundColor(rankColor(for: index + 1))
                            .frame(width: 32, alignment: .leading)
                        
                        Group {
                            if let url = game.gameCoverURL,
                               let image = ImageCache.shared.memoryCache.object(forKey: cacheKey(for: url) as NSString) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.15))
                                    .overlay(Text("🎮").font(.system(size: 12)))
                            }
                        }
                        .frame(width: 36, height: 48)
                        .cornerRadius(6)
                        .clipped()
                        
                        Text(game.gameTitle)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    
                    if index < games.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.1))
                            .padding(.horizontal, 24)
                    }
                }
            }
            .padding(.bottom, 16)
            
            // CTA
            HStack {
                Spacer()
                Text("What's your top \(games.count)? → playedit.app/profile/\(username)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "E07B4C"))
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .frame(width: 390, alignment: .top)
        .background(
            LinearGradient(
                colors: [Color(hex: "2C4A63"), Color(hex: "1A3347")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(cornerRadius)
    }
    
    private func rankColor(for position: Int) -> Color {
        switch position {
        case 1: return .accentOrange
        case 2...3: return Color(hex: "4A7FB5")
        default: return .white.opacity(0.6)
        }
    }
}
