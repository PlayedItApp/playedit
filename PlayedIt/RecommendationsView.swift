import SwiftUI
internal import PostgREST
import Supabase

struct RecommendationsView: View {
    @StateObject private var manager = RecommendationManager.shared
    @State private var showDismissSheet = false
    @State private var dismissTarget: RecommendationDisplay? = nil
    @State private var gameToLog: RecommendationDisplay? = nil
    @State private var selectedDetail: RecommendationDisplay? = nil
    @State private var toast: String? = nil
    @State private var hasGenerated = false
    @Environment(\.dismiss) private var dismiss
    @State private var showHowItWorks = false
    
    var body: some View {
        NavigationStack {
            Group {
                if manager.isGenerating && manager.recommendations.isEmpty {
                    loadingState
                } else if manager.recommendations.isEmpty && hasGenerated {
                    emptyState
                } else {
                    recommendationsList
                }
            }
            .navigationTitle("For You")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await manager.generateRecommendations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.primaryBlue)
                    }
                    .disabled(manager.isGenerating)
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = toast {
                    toastView(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                withAnimation { self.toast = nil }
                            }
                        }
                }
            }
            .task {
                if !hasGenerated {
                    await manager.buildDisplayList()
                        if manager.recommendations.isEmpty {
                            await manager.generateRecommendations()
                        }
                        hasGenerated = true
                    AnalyticsService.shared.track(.recommendationsViewed, properties: [
                        "count": manager.recommendations.count
                    ])
                }
            }
            .sheet(isPresented: $showHowItWorks) {
                HowItWorksSheet()
            }
            .sheet(item: $gameToLog) { rec in
                RecommendationLogGameSheet(recommendation: rec) { rankPosition, totalGames in
                    Task {
                        let _ = await manager.markAsRanked(
                            recommendationId: rec.id,
                            rankPosition: rankPosition,
                            totalGames: totalGames
                        )
                        withAnimation { toast = "Ranked! Nice." }
                    }
                }
            }
            .confirmationDialog(
                "Not for me",
                isPresented: $showDismissSheet,
                presenting: dismissTarget
            ) { rec in
                Button("Not Interested") {
                    dismissWithReason(rec: rec, reason: "not_interested")
                }
                Button("Bad Suggestion") {
                    dismissWithReason(rec: rec, reason: "bad_suggestion")
                }
                Button("Just Dismiss") {
                    dismissWithReason(rec: rec, reason: nil)
                }
                Button("Cancel", role: .cancel) { }
            } message: { _ in
                Text("Why doesn't this work for you? (optional)")
            }
            .sheet(item: $selectedDetail) { rec in
                RecommendationDetailSheet(recommendation: rec)
            }
        }
    }
    
    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .primaryBlue))
            Text("Finding games you'll love...")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            Spacer()
        }
    }
    
    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.adaptiveSilver)
            
            Text("We're out of ideas!")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
            
            Text("Rank more games or add friends to get better recommendations.")
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                Task { await manager.generateRecommendations() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(.primaryBlue)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.primaryBlue.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Recommendations List
    private var recommendationsList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if manager.isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Refreshing...")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    .padding(.top, 4)
                }
                
                // Experimental disclaimer
                Button {
                    showHowItWorks = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flask")
                            .font(.system(size: 11))
                        Text("Recommendations are experimental, take them with a grain of salt! They'll improve as you rank more games.")
                            .font(.system(size: 12, design: .rounded))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(Color.adaptiveGray)
                    .padding(10)
                    .background(Color.cardBackground)
                    .cornerRadius(10)
                }
                .padding(.bottom, 4)
                
                ForEach(manager.recommendations) { rec in
                    RecommendationCard(
                        recommendation: rec,
                        onRankIt: {
                            AnalyticsService.shared.track(.recommendationRankItTapped, properties: [
                                "game_title": rec.gameTitle
                            ])
                            gameToLog = rec
                        },
                        onWantToPlay: {
                            AnalyticsService.shared.track(.recommendationWantToPlayTapped, properties: [
                                "game_title": rec.gameTitle
                            ])
                            Task {
                                let added = await WantToPlayManager.shared.addGame(
                                    gameId: rec.recommendation.gameId,
                                    gameTitle: rec.gameTitle,
                                    gameCoverUrl: rec.gameCoverUrl,
                                    source: "recommendation"
                                )
                                if added {
                                    let _ = await manager.markAsWantToPlay(recommendationId: rec.id)
                                    withAnimation { toast = "Added! Find it in your Want to Play list." }
                                } else {
                                    let _ = await manager.markAsWantToPlay(recommendationId: rec.id)
                                    withAnimation { toast = "Already in your Want to Play list!" }
                                }
                            }
                        },
                        onDismiss: {
                            dismissTarget = rec
                            showDismissSheet = true
                        },
                        onTapDetail: {
                            selectedDetail = rec
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBackground)
    }
    
    // MARK: - Toast
    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.bottom, 20)
    }
    
    // MARK: - Dismiss
    private func dismissWithReason(rec: RecommendationDisplay, reason: String?) {
        Task {
            let _ = await manager.dismiss(recommendationId: rec.id, reason: reason)
            withAnimation { toast = "Got it. We won't suggest this one for a while." }
        }
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let recommendation: RecommendationDisplay
    let onRankIt: () -> Void
    let onWantToPlay: () -> Void
    let onDismiss: () -> Void
    var onTapDetail: () -> Void = {}
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Game info row
            HStack(spacing: 12) {
                // Cover art
                CachedAsyncImage(url: recommendation.gameCoverUrl) {
                    GameArtworkPlaceholder(genre: nil, size: .medium)
                }
                .frame(width: 60, height: 80)
                .cornerRadius(8)
                .clipped()
                
                // Title + prediction
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.gameTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                        .lineLimit(2)
                    
                    // Genres
                    Text(recommendation.genres.prefix(3).joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                    
                    // Platforms
                    if let platforms = recommendation.platforms, !platforms.isEmpty {
                        Text(platforms.joined(separator: " · "))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.adaptiveSilver)
                            .lineLimit(1)
                    }
                    
                    // Friend attribution
                    if let friendName = recommendation.sourceFriendName,
                       let friendRank = recommendation.sourceFriendRankPosition {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text("\(friendName) ranked this #\(friendRank)")
                                .font(.system(size: 12, design: .rounded))
                        }
                        .foregroundStyle(Color.adaptiveGray)
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { onTapDetail() }
            
            // Action buttons
            HStack(spacing: 10) {
                // Rank It
                Button(action: onRankIt) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Rank It")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.accentOrange)
                    .cornerRadius(8)
                }
                
                // Want to Play
                Button(action: onWantToPlay) {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Want to Play")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.primaryBlue)
                    .cornerRadius(8)
                }
                
                // Dismiss
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Not for me")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.adaptiveGray)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.adaptiveDivider)
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
    }
    
    private var predictionColor: Color {
        switch recommendation.prediction.predictedPercentile {
        case 65...100: return Color(red: 0.25, green: 0.55, blue: 0.42)
        case 40..<65: return .adaptiveGray
        default: return Color.red
        }
    }
}

// MARK: - Log Game Sheet (simplified for ranking from recommendation)

struct RecommendationLogGameSheet: View {
    let recommendation: RecommendationDisplay
    let onRanked: (Int, Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    private var game: Game {
        Game(
            id: recommendation.gameRawgId,
            rawgId: recommendation.gameRawgId,
            title: recommendation.gameTitle,
            coverURL: recommendation.gameCoverUrl,
            genres: recommendation.genres,
            platforms: recommendation.platforms ?? [],
            releaseDate: nil,
            metacriticScore: nil,
            added: nil,
            rating: nil,
            gameDescription: nil,
            tags: []
        )
    }
    
    var body: some View {
        GameLogView(game: game, source: "recommendation")
            .presentationBackground(Color.appBackground)
    }
}

// MARK: - Recommendation Detail Sheet

struct RecommendationDetailSheet: View {
    let recommendation: RecommendationDisplay
    
    @Environment(\.dismiss) private var dismiss
    @State private var gameDescription: String? = nil
    @State private var isLoadingDescription = true
    @State private var metacriticScore: Int? = nil
    @State private var curatedGenres: [String]? = nil
    @State private var curatedTags: [String]? = nil
    @State private var curatedPlatforms: [String]? = nil
    @State private var curatedReleaseYear: Int? = nil
    @State private var showGameDataReport = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    GameInfoHeroView(
                        title: recommendation.gameTitle,
                        coverURL: recommendation.gameCoverUrl,
                        releaseDate: curatedReleaseYear.map { String($0) },
                        metacriticScore: metacriticScore,
                        gameDescription: gameDescription,
                        isLoadingDescription: isLoadingDescription,
                        curatedGenres: curatedGenres,
                        curatedTags: curatedTags,
curatedPlatforms: curatedPlatforms
                    )
                    .padding(.top, 12)
                    
                    // Prediction badge
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12))
                        Text(recommendation.prediction.summaryText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(predictionColor)
                    
                    // Friend attribution
                    if let friendName = recommendation.sourceFriendName,
                       let friendRank = recommendation.sourceFriendRankPosition {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 12))
                            Text("\(friendName) ranked this #\(friendRank)")
                                .font(.system(size: 14, design: .rounded))
                        }
                        .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    // Report bad game data
                    Button {
                        showGameDataReport = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 13))
                            Text("Report incorrect game info")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(Color.adaptiveGray)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await GameShareService.shared.shareGame(
                                gameTitle: recommendation.gameTitle,
                                coverURL: recommendation.gameCoverUrl,
                                gameId: recommendation.gameRawgId
                            )
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16))
                            .foregroundColor(.primaryBlue)
                    }
                }
            }
            .sheet(isPresented: $showGameDataReport) {
                ReportGameDataView(
                    gameId: recommendation.gameRawgId,
                    rawgId: recommendation.gameRawgId,
                    gameTitle: recommendation.gameTitle
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
            .task {
                await loadDescription()
            }
        }
    }
    
    private var predictionColor: Color {
        switch recommendation.prediction.predictedPercentile {
        case 65...100: return Color(red: 0.25, green: 0.55, blue: 0.42)
        case 40..<65: return .adaptiveGray
        default: return Color.red
        }
    }
    
    private func loadDescription() async {
        if let cached = GameMetadataCache.shared.get(gameId: recommendation.gameRawgId) {
            metacriticScore = cached.metacriticScore
            gameDescription = cached.description
            curatedGenres = cached.curatedGenres
            curatedTags = cached.curatedTags
            curatedPlatforms = cached.curatedPlatforms
            curatedReleaseYear = cached.curatedReleaseYear
            if gameDescription != nil {
                isLoadingDescription = false
                return
            }
        }
        
        // First try the games table
        do {
            struct GameDesc: Decodable {
                let description: String?
                let curated_description: String?
                let metacritic_score: Int?
                let release_date: String?
                let curated_genres: [String]?
                let curated_tags: [String]?
                let curated_platforms: [String]?
                let curated_release_year: Int?
            }
            
            let infos: [GameDesc] = try await SupabaseManager.shared.client
                .from("games")
                .select("description, curated_description, metacritic_score, release_date, curated_genres, curated_tags, curated_platforms, curated_release_year")
                .eq("rawg_id", value: recommendation.gameRawgId)
                .limit(1)
                .execute()
                .value
            
            if let score = infos.first?.metacritic_score {
                metacriticScore = score
            }
            curatedGenres = infos.first?.curated_genres
            curatedTags = infos.first?.curated_tags
            curatedPlatforms = infos.first?.curated_platforms
            curatedReleaseYear = infos.first?.curated_release_year
            if let desc = infos.first?.curated_description ?? infos.first?.description, !desc.isEmpty {
                let cleaned = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                gameDescription = cleaned
                GameMetadataCache.shared.set(gameId: recommendation.gameRawgId, description: cleaned, metacriticScore: metacriticScore, releaseDate: infos.first?.release_date, curatedGenres: curatedGenres, curatedTags: curatedTags,curatedPlatforms: curatedPlatforms, curatedReleaseYear: curatedReleaseYear)
                isLoadingDescription = false
                return
            }
        } catch {
            print("⚠️ Error loading description from DB: \(error)")
        }
        
        // Fallback to RAWG API
        do {
            let details = try await RAWGService.shared.getGameDetails(id: recommendation.gameRawgId)
            let desc = details.gameDescription ?? details.gameDescriptionHtml ?? ""
            let cleaned = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            gameDescription = cleaned.isEmpty ? nil : cleaned
            
            // Cache for next time
            if !cleaned.isEmpty {
                GameMetadataCache.shared.set(gameId: recommendation.gameRawgId, description: cleaned, metacriticScore: metacriticScore, releaseDate: curatedReleaseYear.map { String($0) }, curatedGenres: curatedGenres, curatedTags: curatedTags, curatedPlatforms: curatedPlatforms, curatedReleaseYear: curatedReleaseYear)
                    _ = try? await SupabaseManager.shared.client
                    .from("games")
                    .update(["description": desc])
                    .eq("rawg_id", value: recommendation.gameRawgId)
                    .execute()
            }
        } catch {
            print("⚠️ Error loading description from RAWG: \(error)")
            gameDescription = nil
        }
        
        isLoadingDescription = false
    }
}

    // MARK: - How It Works Sheet

    struct HowItWorksSheet: View {
        @Environment(\.dismiss) var dismiss
        
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // Overview
                        sectionHeader("Overview")
                        Text("Each candidate game is scored on a 0–100 percentile scale by blending two independent signals: friend rankings and genre/tag affinity. Only games scoring 65%+ and available on platforms you own are shown.")
                            .bodyStyle()
                        
                        // Tier 1
                        sectionHeader("Tier 1: Friend Signal")
                        Text("For each friend who ranked the game, we compute:")
                            .bodyStyle()
                        mathBlock("friendPercentile = (1 - (rank - 1) / (totalGames - 1)) × 100")
                        Text("Friends are weighted by taste match (Spearman ρ). The friend signal is the weighted average:")
                            .bodyStyle()
                        mathBlock("friendScore = Σ(percentileᵢ × tasteMatchᵢ) / Σ(tasteMatchᵢ)")
                        Text("Only friends with ≥30% taste match contribute. Friends with ≥70% match qualify as recommendation sources.")
                            .bodyStyle()
                        
                        // Taste Match
                        sectionHeader("Taste Match (Spearman ρ)")
                        Text("Compares rank orderings of shared games between two users:")
                            .bodyStyle()
                        mathBlock("ρ = 1 - (6 × Σdᵢ²) / (n × (n² - 1))")
                        Text("Where dᵢ is the rank difference for each shared game and n is the number of shared games. Normalized to 0–100%.")
                            .bodyStyle()
                        
                        // Tier 2
                        sectionHeader("Tier 2: Genre & Tag Affinity")
                        Text("For each genre/tag the candidate has, we compute a rank-weighted average percentile across your games that share that genre/tag. Games you rank higher contribute more to the signal.")
                            .bodyStyle()
                        mathBlock("affinity = Σ(percentileᵢ × weightᵢ) / Σ(weightᵢ)")
                        Text("Tags require ≥2 matching games. Tags are weighted 70%, genres 30% — tags are more specific signals. Positive affinities get a boost to create separation:")
                            .bodyStyle()
                        mathBlock("boost = (affinity - 50) × 0.5 × countFactor")
                        
                        // Era Modifier
                        sectionHeader("Era Modifier")
                        Text("Games are bucketed into eras (pre-1995, 1995–2004, 2005–2012, 2013–2019, 2020+). If you tend to rank games from a particular era highly, candidates from that era get a boost of up to ±10 points.")
                            .bodyStyle()
                        
                        // Blending
                        sectionHeader("Blending Weights")
                        VStack(alignment: .leading, spacing: 8) {
                            weightRow("2+ friends ranked it:", "30% friend, 70% genre/tag")
                            weightRow("1 friend ranked it:", "25% friend, 75% genre/tag")
                            weightRow("No friend signal:", "100% genre/tag")
                        }
                        
                        // Genre Drag
                        sectionHeader("Genre Drag")
                        Text("If a friend loves a game but your genre/tag affinity is low, the score is penalized:")
                            .bodyStyle()
                        mathBlock("if genreTag < 50: penalty = (50 - genreTag) / 50 × 20")
                        mathBlock("if genreTag < 70 & friend > 80th: reduction = (70 - genreTag) / 20 × 0.4 × friendContribution")
                        Text("This prevents recommendations in genres you don't enjoy, even when friends rank them highly.")
                            .bodyStyle()
                        
                        // Platform Filtering
                        sectionHeader("Platform Filtering")
                        Text("Only games available on platforms you own are recommended. A platform is considered \"owned\" if you've ranked 2+ games on it. Only games with curated platform data are eligible.")
                            .bodyStyle()
                        
                        // Threshold
                        sectionHeader("Threshold")
                        Text("Only games with a final blended score ≥ 65% are shown. This corresponds to the \"You'll love this\" tier: games predicted to land in your top third.")
                            .bodyStyle()
                        
                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .navigationTitle("How It Works")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        
        private func sectionHeader(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color.adaptiveSlate)
        }
        
        private func mathBlock(_ formula: String) -> some View {
            Text(formula)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.primaryBlue)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardBackground) 
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primaryBlue.opacity(0.2), lineWidth: 1)
                )
        }
        
        private func weightRow(_ label: String, _ value: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                Text(value)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color.adaptiveGray)
            }
        }
    }

extension View {
    func bodyStyle() -> some View {
        self
            .font(.system(size: 14, design: .rounded))
            .foregroundStyle(Color.adaptiveGray)
    }
}
