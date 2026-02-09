import SwiftUI

// MARK: - WhatsNew Manager

struct WhatsNewManager {
    static let currentVersion = "1.1.0"
    
    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(
            icon: "bookmark.fill",
            title: "Want to Play List",
            description: "Bookmark games from friends' rankings and build your own wishlist."
        ),
        WhatsNewFeature(
            icon: "apple.logo",
            title: "Sign in with Apple",
            description: "Sign in with Apple, reset your password, and use password managers. You can also link an existing account to your Apple ID."
        ),
        WhatsNewFeature(
            icon: "newspaper",
            title: "Richer Feed",
            description: "Tap any game in the feed to see the full review, rank it yourself, and see how friends ranked it."
        ),
        WhatsNewFeature(
            icon: "person.circle",
            title: "Better Profiles",
            description: "Re-rank, remove, or add notes to games right from your profile. Plus a search button to log new games."
        ),
        WhatsNewFeature(
            icon: "person.2",
            title: "Friends List Upgrades",
            description: "Add games directly from a friend's list, one at a time or all at once. Profile pics now show everywhere."
        ),
        WhatsNewFeature(
            icon: "bubble.left.and.bubble.right",
            title: "Comments & Notifications",
            description: "Edit or delete your comments, manage comments on your posts, and tap notifications to jump straight there."
        ),
        WhatsNewFeature(
            icon: "eye.slash",
            title: "Spoiler Tags",
            description: "Wrap text in ||double pipes|| to hide spoilers in all text fields. Tap to reveal."
        )
    ]
    
    static let minorImprovements: [String] = [
        "Renamed Home page to Feed",
        "Choose which page shows when you open the app",
        "Platform selection is now optional when ranking",
        "Added custom platform option for when the API gets it wrong",
        "Add a review or notes after ranking without re-ranking",
        "Show profile pictures on comments, friends list, and feed",
        "Edit or delete your own comments",
        "Delete other users' comments on your own posts",
        "Tapping a notification brings you to that comment, friend request, etc.",
        "Fixed search for special characters (é, ü, etc.)",
        "Fixed search results for games with multiple editions/DLCs",
        "Corrected taste match percentage math"
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
                    .foregroundColor(.slate)
                
                Text("v\(WhatsNewManager.currentVersion)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.grayText)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            // Features & improvements
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(WhatsNewManager.features) { feature in
                        HStack(spacing: 16) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 22))
                                .foregroundColor(.accentOrange)
                                .frame(width: 44, height: 44)
                                .background(Color.accentOrange.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feature.title)
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundColor(.slate)
                                
                                Text(feature.description)
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundColor(.grayText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    
                    // Minor improvements section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Minor Improvements")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.slate)
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
                                        .foregroundColor(.grayText)
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
