import SwiftUI

// MARK: - PlayedIt Brand Colors
extension Color {
    // Primary
    static let primaryBlue = Color(hex: "4A7FB5")
    static let slate = Color(hex: "3D5A73")
    
    // Accent
    static let accentOrange = Color(hex: "E07B4C")
    static let teal = Color(hex: "6BC5B8")
    
    // Neutrals
    static let lightGray = Color(hex: "F5F6F7")
    static let silver = Color(hex: "C4CDD4")
    static let grayText = Color(hex: "6B7280")
    
    // Semantic
    static let success = Color(hex: "10B981")
    static let error = Color(hex: "EF4444")
    static let warning = Color(hex: "F59E0B")
    
    // Helper initializer for hex colors
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
extension Font {
    // Using SF Pro Rounded as primary (system font, always available)
    // Nunito can be added later for exact brand match
    
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let title2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let title3 = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    static let callout = Font.system(size: 16, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 12, weight: .regular, design: .rounded)
    static let rankNumber = Font.system(size: 24, weight: .bold, design: .rounded)
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentOrange)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primaryBlue)
                    .opacity(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundColor(.slate)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Text Field Modifier
struct PlayedItTextFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .regular, design: .rounded))
            .foregroundColor(.slate)
            .tint(.slate)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.lightGray)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.silver, lineWidth: 1)
            )
    }
}

extension View {
    func playedItTextField() -> some View {
        modifier(PlayedItTextFieldModifier())
    }
}

// MARK: - Card Style
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
