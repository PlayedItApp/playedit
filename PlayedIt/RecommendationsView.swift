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
                        Task {
                            await manager.generateRecommendations()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.primaryBlue)
                    }
                    .disabled(manager.isGenerating)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.adaptiveGray)
                    }
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
                    await manager.generateRecommendations()
                    hasGenerated = true
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
                            gameToLog = rec
                        },
                        onWantToPlay: {
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
        }
        .background(Color.secondaryBackground)
    }
    
    // MARK: - Toast
    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.secondaryBackground)
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
                AsyncImage(url: URL(string: recommendation.gameCoverUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.secondaryBackground)
                        .overlay(
                            Image(systemName: "gamecontroller")
                                .foregroundStyle(Color.adaptiveSilver)
                        )
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
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
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
        GameLogView(game: game)
    }
}

// MARK: - Recommendation Detail Sheet

struct RecommendationDetailSheet: View {
    let recommendation: RecommendationDisplay
    
    @Environment(\.dismiss) private var dismiss
    @State private var gameDescription: String? = nil
    @State private var isLoadingDescription = true
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Cover art
                    AsyncImage(url: URL(string: recommendation.gameCoverUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.secondaryBackground)
                            .overlay(
                                Image(systemName: "gamecontroller")
                                    .foregroundStyle(Color.adaptiveSilver)
                                    .font(.system(size: 30))
                            )
                    }
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .clipped()
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Genres
                    if !recommendation.genres.isEmpty {
                        Text(recommendation.genres.prefix(4).joined(separator: " · "))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
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
                    
                    // Description
                    if isLoadingDescription {
                        ProgressView()
                            .padding(.top, 10)
                    } else if let desc = gameDescription, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            Text(desc)
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                                .lineSpacing(4)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        Text("No description available")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Color.adaptiveSilver)
                    }
                    
                    Spacer(minLength: 40)
                }
            }
            .navigationTitle(recommendation.gameTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
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
        // First try the games table
        do {
            struct GameDesc: Decodable {
                let description: String?
            }
            
            let infos: [GameDesc] = try await SupabaseManager.shared.client
                .from("games")
                .select("description")
                .eq("rawg_id", value: recommendation.gameRawgId)
                .limit(1)
                .execute()
                .value
            
            if let desc = infos.first?.description, !desc.isEmpty {
                let cleaned = desc.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                gameDescription = cleaned
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
                        Text("Each candidate game is scored on a 0–100 percentile scale by blending three independent signals. Only games scoring 65%+ are shown.")
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
                        Text("For each genre/tag the candidate has, we find your average rank percentile across all your games with that genre/tag:")
                            .bodyStyle()
                        mathBlock("genreAffinity = avg(percentile) for your games in that genre")
                        Text("Tags require ≥2 matching games. Genre and tag scores are blended 50/50. For libraries under 30 games, positive affinities get a small boost to create separation:")
                            .bodyStyle()
                        mathBlock("boost = (affinity - 50) × 0.3 × countFactor")
                        
                        // Tier 3
                        sectionHeader("Tier 3: Metacritic Correlation")
                        Text("Linear regression between your rank percentiles and Metacritic scores across your library:")
                            .bodyStyle()
                        mathBlock("predicted = a + b × metacriticScore")
                        Text("Requires ≥5 games with Metacritic scores. Measures how much you agree with critics.")
                            .bodyStyle()
                        
                        // Blending
                        sectionHeader("Blending Weights")
                        VStack(alignment: .leading, spacing: 8) {
                            weightRow("2+ friends ranked it:", "60% friend, 30% genre/tag, 10% metacritic")
                            weightRow("1 friend ranked it:", "55% friend, 30% genre/tag, 15% metacritic")
                            weightRow("No friend signal:", "70% genre/tag, 30% metacritic")
                        }
                        
                        // Genre Drag
                        sectionHeader("Genre Drag")
                        Text("If a friend loves a game but your genre/tag affinity is low, the score is penalized:")
                            .bodyStyle()
                        mathBlock("if genreTag < 50: penalty = (50 - genreTag) / 50 × 20")
                        mathBlock("if genreTag < 70 & friend > 80th: reduction = (70 - genreTag) / 20 × 0.4 × friendContribution")
                        Text("This prevents recommendations in genres you don't enjoy, even when friends rank them highly.")
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
                .background(Color.secondaryBackground)
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
