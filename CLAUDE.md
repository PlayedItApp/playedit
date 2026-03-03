# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PlayedIt is a native iOS social game ranking app built with SwiftUI. Users rank games they've played, see friends' rankings, and get AI-driven recommendations. Backend is Supabase (PostgreSQL + Auth + Edge Functions). Game metadata comes from the RAWG API, with Steam library import support.

## Build & Run

```bash
# Build
xcodebuild build -scheme PlayedIt -configuration Debug

# Run tests
xcodebuild test -scheme PlayedIt -destination 'platform=iOS Simulator,name=iPhone 16'

# Open in Xcode
open PlayedIt.xcodeproj
```

Dependencies are managed via Swift Package Manager (Supabase Swift SDK v2.5.1+). No CocoaPods or Carthage.

## Supabase Edge Functions

Located in `supabase/functions/*/index.ts` (TypeScript/Deno). Key functions: `get-suggested-friends`, `link-apple-identity`, `moderate-text`, `send-push`, `steam-auth`, `steam-games`.

```bash
# Local Supabase development
cd supabase && supabase start   # API on :54321, DB on :54322
supabase stop
```

## Architecture

**All Swift source lives flat in `PlayedIt/PlayedIt/`** — no subdirectories by feature.

### Singleton Service Managers
Core logic lives in manager singletons accessed via `.shared`:
- **`SupabaseManager`** — Auth, user session, all Supabase DB queries (profiles, rankings, friends, feed). This is the largest file and the central data layer.
- **`RAWGService`** — Game search, discovery, and metadata fetching from RAWG API.
- **`RecommendationManager`** — Generates game recommendations using prediction scores and friend signals.
- **`WantToPlayManager`** — CRUD for the user's "want to play" list.
- **`PushNotificationManager`** — APNs registration and token management.
- **`AppearanceManager`** — Theme/dark mode preference persistence.
- **`SteamService`** — Steam OAuth and library import.
- **`ContentModerator` / `ModerationService` / `PhotoModerator`** — Text and image content moderation.

### Key Models
- **`Game`** — Canonical game model used throughout the app (converted from RAWG responses).
- **`UserGame`** — A ranked game entry with position, notes, platforms, timestamps.
- **`WantToPlayGame`** — Wishlist entry.
- **`Recommendation` / `GamePrediction`** — Prediction engine outputs with confidence scores and friend signals.

### Prediction Engine
`Predictionengine.swift` estimates where a user would rank an unplayed game based on genre/tag affinity and friend taste matching. Outputs a `GamePrediction` with predicted rank, confidence (1-5), percentile, and contributing friend signals.

### View Hierarchy
```
PlayedItApp → ContentView
  ├── SplashView (auth check)
  ├── OnboardingQuizView (first-time)
  └── MainTabView (authenticated)
      ├── FeedView — Social feed of friends' rankings
      ├── RecommendationsView — AI recommendations
      ├── WantToPlayListView — Wishlist
      ├── FriendsView — Friend management
      └── ProfileView — User profile & rankings
```

### Ranking Flow
`GameSearchView` → `BatchRankSelectionView` → `BatchRankFlowView` → `ComparisonView` (binary comparisons to insert game at correct rank position).

### Deep Linking
Supports both custom scheme (`playedit://`) and universal links (`https://playedit.app/`). Routes: `/profile/{username}`, `/game/{id}`, `/login-callback` (email confirmation).

## Conventions

- Models use `Codable` with `CodingKeys` for snake_case ↔ camelCase conversion.
- State management via `@StateObject`, `@ObservedObject`, `@Published`.
- Debug logging uses `debugLog()` from `LogCollector.swift` (not `print()`).
- Config values (API keys, URLs) are in `config.swift`.
- `Theme.swift` defines shared colors and styling constants.
