import SwiftUI

// MARK: - WhatsNew Manager

struct WhatsNewManager {
    static let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()
    
    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(
            icon: "arrow.down.doc.fill",
            title: "CSV Import",
            description: "Got a backlog spreadsheet? Import games directly from a CSV and rank them without starting from scratch. Template at playedit.app/template."
        ),
        WhatsNewFeature(
            icon: "wand.and.stars",
            title: "Curated Game Data",
            description: "Descriptions, genres, tags, platforms, and release years have all been rewritten from scratch. No longer are we at the whim of RAWGG's API. Just accurate, useful info. Sometimes... this is an ongoing project."
        ),
        WhatsNewFeature(
            icon: "sparkles",
            title: "Smarter Recommendations",
            description: "Recommendations now only suggest games on platforms you've actually used. Refresh without seeing the same games twice, and the background actually matches the rest of the app now."
        ),
        WhatsNewFeature(
            icon: "bookmark.fill",
            title: "Want to Play Upgrades",
            description: "Cards now show release year and platforms. Prioritize reorders your backlog. Rank moves a game into your rankings. They're separate now so it's actually clear what you're doing."
        )
    ]
    
    static let minorImprovements: [String] = [
        "Made it so the Rank button in Want to Play actually ranks games and add the Prioritize button to prioritize within the Want to Play list",
        "Feed refreshes automatically after CSV and Steam imports",
        "Genres and tags now appear on game detail views for curated games",
        "Platforms shown on friend profiles and Want to Play lists, ordered by what you've played first",
        "All game detail views now pull from cache instead of hitting the backend every time",
        "Added a button to report bad descriptions, genres, tags, platforms, or release year on any game. Call me out if they're wrong. I'll take care of it",
        "Game log view redesigned so that searching a game looks the same as tapping one in the feed",
        "Adding a game from search now shows the new post in the feed when you close the view",
        "Games without artwork are moved to the bottom of grouped Want to Play posts so the preview always looks clean",
        "Only show platforms a game was actually released on in the ranking picker",
        "Game detail views now show release year, platforms, genres, and tags sourced from our curated data layer",
        "Optimized queries on friends, game detail, recommendations, and feed pages",
        "Added a way to permanently discard an in-progress ranking instead of being forced to finish it"
    ]
    
    static let bugFixes: [String] = [
        "Fixed Steam import so selecting multiple games actually ranks all of them, not just one",
        "Tapping a row in Steam import now toggles the game instead of requiring a precise tap on the checkbox",
        "In-progress import count is now scoped to the current import, not all-time",
        "In-progress count persists when you navigate away from your profile mid-import",
        "Fixed coloring on the Steam import rankings view",
        "Sign out failures no longer leave you stuck in a signed-in limbo with no way out",
        "Fixed a race condition in the game metadata cache. No more thread safety issues",
        "Clicking add/remove Want to Play too quickly no longer breaks the button",
        "Want to Play detail sheets now match the dark styling of ranking feed posts",
        "Adding from a batched Want to Play post now correctly highlights the bookmark",
        "Feed batching now correctly groups posts of the same type within a 2-hour window",
        "Bookmarks stay highlighted when you add a game to Want to Play via search",
        "Ranking a game from recommendations now removes it from your recommendations list"
    ]
    
    // MARK: - Previous Version (1.3.0)

    static let previousFeatures_1_3_0: [WhatsNewFeature] = [
        WhatsNewFeature(
            icon: "square.and.arrow.up.fill",
            title: "Share Games",
            description: "Found your new #1? Share any game with a slick card that shows your ranking and cover art. Send it to friends, post it wherever. Let the world know."
        ),
        WhatsNewFeature(
            icon: "bell.badge.fill",
            title: "Push Notifications",
            description: "Get notified when someone comments on your ranking or sends a friend request, even when the app is closed. Your phone will let you know."
        ),
        WhatsNewFeature(
            icon: "person.2.fill",
            title: "Suggested Friends",
            description: "PlayedIt now suggests people you might know based on mutual friends. Growing your circle just got easier."
        ),
        WhatsNewFeature(
            icon: "sparkle.magnifyingglass",
            title: "Prediction Comparison",
            description: "Rank a game that had a prediction? We'll show you how close we were. See your predicted rank side by side with where it actually landed."
        ),
        WhatsNewFeature(
            icon: "bookmark.fill",
            title: "Want to Play in the Feed",
            description: "When you add a game to your Want to Play list, your friends will see it in the feed. They can also add games to Want to Play directly from batched posts."
        ),
        WhatsNewFeature(
            icon: "person.crop.circle.badge.plus",
            title: "New User Onboarding",
            description: "New users are now prompted to set a profile picture and update their username right after signing up. First impressions matter."
        ),
        WhatsNewFeature(
            icon: "gamecontroller.fill",
            title: "Consoles in Rankings",
            description: "Your ranked list now shows which platform you played each game on. Plus, more console options and alphabetized platforms under Played On."
        ),
        WhatsNewFeature(
            icon: "bolt.fill",
            title: "Speed Improvements",
            description: "Game art loads way faster across onboarding, profiles, and the feed. Predictions and game details are snappier too. Less waiting, more ranking."
        )
    ]

    static let previousMinorImprovements_1_3_0: [String] = [
        "Bookmark games directly from the game detail view",
        "The feed now loads older posts, no more hitting a wall",
        "Ranking a game from Want to Play now closes the sheet, refreshes your profile, and removes it from the list automatically",
        "Comment notifications now include the game name: \"commented on your ranking of Halo 3\"",
        "\"How Friends Ranked This\" is now sorted on the game detail sheet",
        "Friends' rankings and the ability to rank a game are now available in the Want to Play detail view",
        "Artwork in batched feed posts is now tappable",
        "Tapping a name in a feed post now goes to that person's profile",
        "Clear all notifications with one tap",
        "Reorganized profile menu for easier navigation",
        "Feed grouping logic updated, no more arbitrary time constraints on batched posts",
        "Games with missing artwork are no longer highlighted in batched posts",
        "Profile refreshes immediately after any changes to Want to Play or rankings",
        "Optionally hide notifications entirely, including the red badge on the feed icon (you're welcome, Alex)",
        "App icon badge for unread comments and friend requests",
        "Removed the toast when adding to Want to Play from search",
        "Send error logs directly from your profile to help us squash bugs faster"
    ]

    static let previousBugFixes_1_3_0: [String] = [
        "Fixed close button placement on Want to Play view and game view from recommendations. Now consistently on the left",
        "Fixed spacing between the bottom of the ranked list and the navigation bar on profiles",
        "Fixed comment text readability in dark mode",
        "Fixed excessive vertical spacing between activity items and comments when opening from a notification",
        "Fixed icon and text alignment on game detail views",
        "Fixed inconsistent spacing between elements in recommendations and notifications",
        "Fixed insufficient separation between cards in light mode",
        "Game descriptions no longer return results for the wrong game. Backfilled the database to correct existing entries",
        "Game descriptions now load properly for games only in Want to Play",
        "Fixed silent ranking failures when logging too many games within 12 hours",
        "Fixed onboarding rankings not numbering correctly causing games to skip positions or not start at #1",
        "Games with null or empty release dates can now be ranked",
        "Descriptions now show for all games in search, even if no one has ranked them yet",
        "Fixed \"ranked at #0\" displaying when opening a game from notifications",
        "You can now rank games directly from recommendations",
        "Rotating your phone during the ranking process no longer cancels it",
        "Game detail view now shows the same information everywhere: predictions, friends' rankings, and descriptions are consistent no matter where you open it",
        "Fixed inability to add games to Want to Play from batched feed posts",
        "Fixed broken \"user commented\" notification navigation"
    ]

    // MARK: - Previous Version (1.2.5)
    
    static let previousFeatures_1_2_5: [WhatsNewFeature] = [
        WhatsNewFeature(
            icon: "moon.stars.fill",
            title: "Dark Mode",
            description: "Your rankings look even better in the dark. Full dark mode support with true black backgrounds for OLED displays. Your eyes (and your battery) will thank you."
        ),
        WhatsNewFeature(
            icon: "sparkles",
            title: "Game Recommendations",
            description: "PlayedIt now predicts how much you'll like games you haven't played yet. We blend your friends' taste, your genre preferences, and review data to surface your next favorite game."
        ),
        WhatsNewFeature(
            icon: "arrow.down.doc.fill",
            title: "Steam Library Import",
            description: "Bring your Steam library along for the ride. Import your games and start ranking without logging everything manually."
        ),
        WhatsNewFeature(
            icon: "eye.fill",
            title: "Want to Play, Now Social",
            description: "Your Want to Play list is now visible to friends. Let them see your backlog, and silently judge your taste."
        ),
        WhatsNewFeature(
            icon: "text.book.closed.fill",
            title: "Game Descriptions",
            description: "Game detail views now include full descriptions so you can finally remember what that indie game was actually about."
        ),
        WhatsNewFeature(
            icon: "flag.fill",
            title: "Report Content",
            description: "See something that shouldn't be there? Report posts, comments, and profiles right from the app. Keeping things clean for everyone."
        ),
        WhatsNewFeature(
            icon: "bubble.left.and.bubble.right.fill",
            title: "Threaded Comments",
            description: "Reply directly to comments and start conversations. Like comments to show some love, and mute threads when you need a break from the notifications."
        )
    ]
    
    static let previousMinorImprovements_1_2_5: [String] = [
        "Feed posts are now condensed when someone logs a bunch of games at once. No more scrolling past 47 Steam imports",
        "Tap any game in your Want to Play list to open its detail view",
        "Rank games directly from a friend's profile, no more dead-end taps",
        "Games in the feed are clickable just like on profiles",
        "Tapping a profile image on re-ranked posts now actually goes to that person's profile",
        "The plus button is now on the same side across all pages (consistency, what a concept)",
        "Sort your Want to Play list however you want",
        "Cancel pending friend requests if you change your mind",
        "Menu button and close button swapped to the correct sides on feed game details",
        "Larger touch targets on menu buttons. Easier to tap, harder to miss",
        "RAWG attribution added to the search page",
        "Friend request confirmation text no longer sticks around after you go back to send another"
    ]
    
    static let previousBugFixes_1_2_5: [String] = [
        "Fixed icon alignment on the changelog across different device sizes",
        "Clicking a profile image on re-ranked posts now navigates correctly",
        "Friend request confirmation no longer persists when sending multiple requests"
    ]
    
    // MARK: - Previous Version (1.2.3)
    
    static let previousFeatures_1_2_3: [WhatsNewFeature] = [
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
    
    static let previousMinorImprovements_1_2_3: [String] = [
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
    
    static let previousBugFixes_1_2_3: [String] = [
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
            
            ScrollView {
                VStack(spacing: 20) {
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
