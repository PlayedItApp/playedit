import SwiftUI

// MARK: - Share Card (rendered to image via ImageRenderer)
struct GameShareCardView: View {
    let gameTitle: String
    let coverURL: String?
    let rankPosition: Int?
    let username: String
    let platforms: [String]
    let totalGames: Int
    let coverImage: UIImage?
    
    private var rankColor: Color {
        switch rankPosition ?? 0 {
        case 1: return .accentOrange
        case 2...3: return .primaryBlue
        default: return .slate
        }
    }
    
    private var titleSize: CGFloat {
        if gameTitle.count > 35 { return 22 }
        if gameTitle.count > 25 { return 26 }
        return 30
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar — branding
            HStack {
                HStack(spacing: 6) {
                    PlayedItShareLogo(size: 20)
                    PlayedItShareWordmark(size: 15)
                }
                Spacer()
                Text("playedit.app")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "C4CDD4"))
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 24)
            
            // Rank — big and bold (only if ranked)
            if let rank = rankPosition {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("#\(rank)")
                        .font(.system(size: 60, weight: .heavy, design: .rounded))
                        .foregroundColor(rankColor)
                    
                    if totalGames > 0 {
                        Text("of \(totalGames)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "6B7280"))
                            .padding(.leading, 4)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            
            // Game info row
            HStack(alignment: .top, spacing: 14) {
                // Cover art — small accent
                Group {
                    if let img = coverImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color(hex: "F5F6F7"))
                            .overlay(
                                Text("🎮")
                                    .font(.system(size: 24))
                            )
                    }
                }
                .frame(width: 72, height: 96)
                .cornerRadius(10)
                .clipped()
                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(gameTitle)
                        .font(.system(size: titleSize, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "3D5A73"))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !platforms.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(platforms.prefix(3), id: \.self) { platform in
                                Text(platform)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(Color(hex: "6B7280"))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: "F5F6F7"))
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            
            Spacer()
            
            // User attribution
            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "4A7FB5"), Color(hex: "6BC5B8")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(username.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                
                HStack(spacing: 0) {
                    Text(username)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "3D5A73"))
                    Text(rankPosition != nil ? " ranked this" : " shared this")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "6B7280"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: "F5F6F7"))
            .cornerRadius(14)
            .padding(.horizontal, 28)
            
            // CTA
            HStack {
                Spacer()
                Text("See the full list & rank it yourself →")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "4A7FB5"))
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .frame(width: 390, height: 520)
        .background(Color.white)
        .cornerRadius(24)
    }
}

// MARK: - Blocky Checkmark Logo
struct PlayedItShareLogo: View {
    let size: CGFloat
    
    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 24
            
            let blocks: [(CGFloat, CGFloat, Color)] = [
                (2, 14, Color(hex: "4A7FB5")),
                (8, 11, Color(hex: "4A7FB5")),
                (14, 8, Color(hex: "E07B4C")),
                (8, 17, Color(hex: "4A7FB5").opacity(0.4)),
            ]
            
            for (x, y, color) in blocks {
                let rect = CGRect(x: x * unit, y: y * unit, width: 5 * unit, height: 5 * unit)
                let path = Path(roundedRect: rect, cornerRadius: unit)
                context.fill(path, with: .color(color))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Wordmark
struct PlayedItShareWordmark: View {
    let size: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            Text("played")
                .font(.custom("Nunito-Bold", size: size))
                .foregroundColor(Color(hex: "3D5A73"))
            Text("it")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "E07B4C"))
        }
    }
}
