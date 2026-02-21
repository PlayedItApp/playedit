import SwiftUI

// MARK: - WhatsNew Manager

struct WhatsNewManager {
    static let currentVersion = "1.2.3"
    
    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(
            icon: "apple.logo",
            title: "Sign in with Apple",
            description: "Fast, no-password login. Already have an email account? Link your Apple ID and use either one."
        ),
        WhatsNewFeature(
            icon: "bookmark.fill",
            title: "To Be Played List",
            description: "Finally, a place for your backlog. Save games you want to play and stop forgetting that recommendation your friend gave you three months ago."
        ),
        WhatsNewFeature(
            icon: "bell.badge",
            title: "Revamped Notifications",
            description: "Notifications actually do things now. Tap one and it takes you right to the comment or post that triggered it."
        ),
        WhatsNewFeature(
            icon: "magnifyingglass",
            title: "Smarter Search & Fixed Taste Matching",
            description: "Search now handles DLC, special editions, characters like é, and hyphens. Plus, taste match percentages and game comparisons are actually accurate now. 🔥"
        ),
        WhatsNewFeature(
            icon: "newspaper",
            title: "Game Detail View",
            description: "Tap any game in the feed or on someone's profile to see the full picture: rank, notes, platforms, the works."
        )
    ]
    
    static let minorImprovements: [String] = [
        "Reset your password with the new forgot password flow",
        "Edit platforms and notes after ranking without re-ranking",
        "Platform selection is now optional when ranking",
        "Remove games from your list (rankings adjust automatically)",
        "Add all games from a friend's list at once",
        "Remove friends (please don't unfriend us, we'll be sad)",
        "Edit or delete your comments",
        "Delete other users' comments on your own posts",
        "Profile pics now show up in the feed, comments, and friends list",
        "Search for new games right from your profile page",
        "Choose which page shows when you open the app",
        "Add a custom platform when yours isn't listed",
        "Spoiler tags: wrap text in ||double pipes|| to hide spoilers. Tap to reveal",
        "Renamed Home to Feed. Tap your profile icon in the feed to jump to your profile",
        "New version toast so you know what's changed"
    ]
    
    static let bugFixes: [String] = [
        "Wrong password error no longer haunts the forgot password screen",
        "Tapping whitespace on a profile no longer opens random game details",
        "Game art taps in rankings work consistently now",
        "Game sheet no longer dismisses itself on your profile after editing",
        "Removing a friend actually removes them from the list without needing a refresh",
        "Notifications now poll every 30 seconds instead of waiting for you to leave the feed"
    ]
    
    private static let key = "lastSeenWhatsNewVersion"
    
    static var shouldShow: Bool {
        let lastSeen = UserDefaults.standard.string(forKey: key)
        return lastSeen != currentVersion
    }
    
    static func markAsSeen() {
        UserDefaults.standard.set(currentVersion, forKey: key)
    }
}

struct WhatsNewFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// MARK: - WhatsNew View

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("What's New 🎮")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("v\(WhatsNewManager.currentVersion)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            // Features & improvements
            ScrollView {
                VStack(spacing: 20) {
                    // Major features
                        ForEach(WhatsNewManager.features) { feature in
                            HStack(alignment: .top, spacing: 0) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.accentOrange.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                    
                                    Image(systemName: feature.icon)
                                        .font(.system(size: 20))
                                        .foregroundColor(.accentOrange)
                                }
                                .frame(width: 60, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(feature.title)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                    
                                    Text(feature.description)
                                        .font(.system(size: 15, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 24)
                        }
                    
                    // Minor improvements section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Minor Improvements")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WhatsNewManager.minorImprovements, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.accentOrange)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(item)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Bug fixes section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Bug Fixes 🛠️")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(WhatsNewManager.bugFixes, id: \.self) { item in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(.accentOrange)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(item)
                                        .font(.system(size: 14, design: .rounded))
                                        .foregroundStyle(Color.adaptiveGray)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 16)
            }
            
            // Dismiss button
            Button {
                WhatsNewManager.markAsSeen()
                dismiss()
            } label: {
                Text("Let's go!")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }
}
