// AnalyticsService.swift
// PlayedIt
//
// Thin wrapper around PostHog. Swap the provider here without
// touching any call sites elsewhere in the app.

import Foundation
import PostHog

final class AnalyticsService {

    // MARK: - Singleton

    static let shared = AnalyticsService()
    private init() {}

    // MARK: - Setup

    /// Call once from PlayedItApp.init() before any tracking.
    func setup() {
        let config = PostHogConfig(
            apiKey: Config.postHogAPIKey,
            host: "https://us.i.posthog.com"
        )
        config.captureApplicationLifecycleEvents = false
        PostHogSDK.shared.setup(config)
    }

    // MARK: - Identity

    func identify(userId: String, username: String) {
        PostHogSDK.shared.identify(
            userId,
            userProperties: [
                "username": username,
                "platform": "ios",
                "app_version": appVersion
            ]
        )
    }

    func reset() {
        PostHogSDK.shared.reset()
    }

    // MARK: - Core Primitives

    func track(_ event: AnalyticsEvent, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event.rawValue, properties: properties)
    }

    func screen(_ name: ScreenName) {
        PostHogSDK.shared.screen(name.rawValue)
    }

    // MARK: - Private Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }
}

// MARK: - Event Names

enum AnalyticsEvent: String {

    // App Lifecycle
    case appOpened                      = "app_opened"
    case appBackgrounded                = "app_backgrounded"
    case sessionStarted                 = "session_started"

    // Onboarding
    case onboardingStarted              = "onboarding_started"
    case onboardingSkipped              = "onboarding_skipped"
    case onboardingPlatformsSelected    = "onboarding_platforms_selected"
    case onboardingGenresSelected       = "onboarding_genres_selected"
    case onboardingGamesSelected        = "onboarding_games_selected"
    case onboardingRankingStarted       = "onboarding_ranking_started"
    case onboardingRankingCompleted     = "onboarding_ranking_completed"
    case onboardingCompleted            = "onboarding_completed"

    // Game Search
    case gameSearchStarted              = "game_search_started"
    case gameSearchCompleted            = "game_search_completed"
    case gameSearchSelected             = "game_search_selected"

    // Ranking Flow
    case rankingFlowStarted             = "ranking_flow_started"
    case rankingComparisonCompleted     = "ranking_comparison_completed"
    case rankingFlowAbandoned           = "ranking_flow_abandoned"
    case rankingFlowCompleted           = "ranking_flow_completed"
    case rankingUndoUsed                = "ranking_undo_used"

    // Comparison
    case comparisonStarted              = "comparison_started"
    case comparisonChoiceMade           = "comparison_choice_made"
    case comparisonTimeout              = "comparison_timeout"

    // Recommendations
    case recommendationsTabOpened           = "recommendations_tab_opened"
    case recommendationsViewed              = "recommendations_viewed"
    case recommendationsGenerated           = "recommendations_generated"
    case recommendationViewed               = "recommendation_viewed"
    case recommendationRanked               = "recommendation_ranked"
    case recommendationRankItTapped         = "recommendation_rank_it_tapped"
    case recommendationWantToPlay           = "recommendation_want_to_play"
    case recommendationWantToPlayTapped     = "recommendation_want_to_play_tapped"
    case recommendationDismissed            = "recommendation_dismissed"

    // Social
    case friendRequestSent              = "friend_request_sent"
    case friendRequestAccepted          = "friend_request_accepted"
    case friendRequestDeclined          = "friend_request_declined"
    case friendProfileViewed            = "friend_profile_viewed"

    // Feed
    case feedOpened                     = "feed_opened"
    case feedPostLiked                  = "feed_post_liked"
    case feedPostUnliked                = "feed_post_unliked"
    case feedCommentAdded               = "feed_comment_added"
    case feedScrolled                   = "feed_scrolled"

    // Sharing
    case gameShared                     = "game_shared"
    case shareCardPresented             = "share_card_presented"
    case profileLinkShared              = "profile_link_shared"
    case topListSharePresented          = "top_list_share_presented"
    case topListShared                  = "top_list_shared"
    case referrerPromptShown            = "referrer_prompt_shown"
    case referrerPromptAccepted         = "referrer_prompt_accepted"
    case installFromShareLink           = "install_from_share_link"

    // Imports
    case csvImportStarted               = "csv_import_started"
    case csvImportCompleted             = "csv_import_completed"
    case csvImportAbandoned             = "csv_import_abandoned"
    case steamImportStarted             = "steam_import_started"
    case steamImportCompleted           = "steam_import_completed"
    case psnImportStarted               = "psn_import_started"
    case psnImportCompleted             = "psn_import_completed"

    // Deep Links
    case deepLinkOpened                 = "deep_link_opened"
    case deepLinkGameViewed             = "deep_link_game_viewed"
    case deepLinkGameRanked             = "deep_link_game_ranked"
    case deepLinkProfileViewed          = "deep_link_profile_viewed"
    case deepLinkFriendRequestSent      = "deep_link_friend_request_sent"

    // Want to Play
    case wantToPlayAdded                = "want_to_play_added"
    case wantToPlayRemoved              = "want_to_play_removed"

    // App Store Review
    case reviewPromptShown              = "review_prompt_shown"
}

// MARK: - Screen Names

enum ScreenName: String {
    case feed               = "Feed"
    case friends            = "Friends"
    case profile            = "Profile"
    case recommendations    = "Recommendations"
    case gameSearch         = "GameSearch"
    case settings           = "Settings"
    case gameLog            = "GameLog"
    case comparison         = "Comparison"
    case onboarding         = "Onboarding"
    case csvImport          = "CSVImport"
    case steamImport        = "SteamImport"
    case psnImport          = "PSNImport"
    case deepLinkGame       = "DeepLinkGame"
    case deepLinkProfile    = "DeepLinkProfile"
}
