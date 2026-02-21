import SwiftUI
internal import PostgREST
import Supabase

// MARK: - Onboarding Data Models

struct OnboardingGame: Identifiable, Codable {
    let id: UUID
    let rawgId: Int
    let title: String
    let coverUrl: String?
    let platforms: [String]
    let genres: [String]
    let tags: [String]
    let popularityScore: Int
    let metacritic: Int?
    let releaseDate: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case rawgId = "rawg_id"
        case title
        case coverUrl = "cover_url"
        case platforms
        case genres
        case tags
        case popularityScore = "popularity_score"
        case metacritic
        case releaseDate = "release_date"
    }
}

enum OnboardingPlatform: String, CaseIterable, Identifiable {
    case nintendo, playstation, xbox, pc, mobile
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .nintendo: return "Nintendo"
        case .playstation: return "PlayStation"
        case .xbox: return "Xbox"
        case .pc: return "PC"
        case .mobile: return "Mobile"
        }
    }
    
    var icon: String {
        switch self {
        case .nintendo: return "gamecontroller.fill"
        case .playstation: return "logo.playstation"
        case .xbox: return "logo.xbox"
        case .pc: return "desktopcomputer"
        case .mobile: return "iphone"
        }
    }
}

enum OnboardingGenre: String, CaseIterable, Identifiable {
    case action_adventure, rpgs, shooters, platformers, strategy
    case sports, horror, indie, fighting, racing
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .action_adventure: return "Action/Adventure"
        case .rpgs: return "RPGs"
        case .shooters: return "Shooters"
        case .platformers: return "Platformers"
        case .strategy: return "Strategy"
        case .sports: return "Sports"
        case .horror: return "Horror"
        case .indie: return "Indie"
        case .fighting: return "Fighting"
        case .racing: return "Racing"
        }
    }
    
    var icon: String {
        switch self {
        case .action_adventure: return "figure.run"
        case .rpgs: return "shield.fill"
        case .shooters: return "scope"
        case .platformers: return "arrow.up.right"
        case .strategy: return "brain.head.profile"
        case .sports: return "sportscourt.fill"
        case .horror: return "eye.fill"
        case .indie: return "star.fill"
        case .fighting: return "figure.boxing"
        case .racing: return "flag.checkered"
        }
    }
}

// MARK: - Onboarding Quiz View

struct OnboardingQuizView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Binding var isOnboardingComplete: Bool
    var onSkip: (() -> Void)? = nil
    
    @State private var step: OnboardingStep = .welcome
    @State private var skippedOnboarding = false
    @State private var selectedPlatforms: Set<OnboardingPlatform> = []
    @State private var selectedGenres: Set<OnboardingGenre> = []
    
    // Game grid
    @State private var filteredGames: [OnboardingGame] = []
    @State private var selectedGameIds: Set<UUID> = []
    @State private var isLoadingGames = false
    
    // Ranking flow
    @State private var showRankingFlow = false
    @State private var gamesToRank: [OnboardingGame] = []
    @State private var rankedCount = 0
    @State private var showKeepGoingPrompt = false
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0, platforms, genres, gameGrid
        
        var totalSteps: Int { 4 }
        var progress: CGFloat { CGFloat(rawValue) / CGFloat(totalSteps - 1) }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                if step != .welcome {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondaryBackground)
                                .frame(height: 6)
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primaryBlue)
                                .frame(width: geometry.size.width * step.progress, height: 6)
                                .animation(.easeInOut(duration: 0.3), value: step)
                        }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }
                
                ZStack {
                    Color.white.ignoresSafeArea()
                    
                    switch step {
                    case .welcome:
                        welcomeView
                    case .platforms:
                        platformsView
                    case .genres:
                        genresView
                    case .gameGrid:
                        gameGridView
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: step)
            .fullScreenCover(isPresented: $showRankingFlow) {
                OnboardingRankingFlowView(
                    games: filteredGames.filter { selectedGameIds.contains($0.id) },
                    onComplete: {
                        isOnboardingComplete = true
                    }
                )
            }
        }
    }
    
    // MARK: - Welcome
        
    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            
            VStack(spacing: 12) {
                Text("Welcome to PlayedIt!")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .multilineTextAlignment(.center)
                
                Text("We'll ask a couple quick questions to find games you've played, then you'll rank them head-to-head. No scores, no stars, just \"which did you like more?\"")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button("Let's go!") {
                    step = .platforms
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button("Skip. Just take me to the app!") {
                    if let onSkip = onSkip {
                        onSkip()
                    } else {
                        isOnboardingComplete = true
                    }
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Q1: Platforms
    
    private var platformsView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            
            // Welcome + question combined
            VStack(spacing: 8) {
                Text("Let's build your gaming history!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .multilineTextAlignment(.center)
                
                Text("First up: what do you play on?")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                
                Text("Select all that apply")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.horizontal, 24)
            
            // Platform buttons
            VStack(spacing: 12) {
                ForEach(OnboardingPlatform.allCases) { platform in
                    Button {
                        togglePlatform(platform)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: platform.icon)
                                .font(.system(size: 22))
                                .frame(width: 28)
                            
                            Text(platform.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            
                            Spacer()
                            
                            if selectedPlatforms.contains(platform) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.primaryBlue)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedPlatforms.contains(platform) ? Color.primaryBlue.opacity(0.08) : Color.secondaryBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedPlatforms.contains(platform) ? Color.primaryBlue : Color.clear, lineWidth: 2)
                        )
                        .foregroundStyle(Color.adaptiveSlate)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Next button
            Button("Next") {
                step = .genres
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedPlatforms.isEmpty)
            .opacity(selectedPlatforms.isEmpty ? 0.5 : 1.0)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Q2: Genres
    
    private var genresView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 20)
            
            VStack(spacing: 8) {
                Text("What's your thing?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .multilineTextAlignment(.center)
                
                Text("Pick up to 3 genres")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.horizontal, 24)
            
            // Genre grid - 2 columns
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(OnboardingGenre.allCases) { genre in
                    let isSelected = selectedGenres.contains(genre)
                    let isDisabled = !isSelected && selectedGenres.count >= 3
                    
                    Button {
                        toggleGenre(genre)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: genre.icon)
                                .font(.system(size: 24))
                            
                            Text(genre.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color.primaryBlue.opacity(0.08) : Color.secondaryBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.primaryBlue : Color.clear, lineWidth: 2)
                        )
                        .foregroundColor(isDisabled ? .silver : (isSelected ? .primaryBlue : .slate))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isDisabled)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Back + Next
            HStack(spacing: 12) {
                Button("Back") {
                    step = .platforms
                }
                .buttonStyle(TertiaryButtonStyle())
                
                Button("Next") {
                    Task { await loadFilteredGames() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedGenres.isEmpty)
                .opacity(selectedGenres.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Game Grid
    
    private var gameGridView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("What have you played?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Text("Tap the games you've finished")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            if isLoadingGames {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                Spacer()
            } else {
                // Game grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 16) {
                        ForEach(filteredGames) { game in
                            gameGridItem(game: game)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    
                    // Search fallback
                    Button {
                        // TODO: Open game search
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                            Text("Don't see your game? Search for more")
                        }
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primaryBlue)
                    }
                    .padding(.bottom, 8)

                    Link(destination: URL(string: "https://rawg.io")!) {
                        Text("Game data powered by RAWG")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    .padding(.bottom, 24)
                }
            }
            
            // Bottom bar
            VStack(spacing: 8) {
                Divider()
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        if selectedGameIds.count < 10 {
                            Text("Keep going! The more you pick, the better your rankings")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                        } else {
                            Text("Nice! Ready to start ranking?")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                        }
                        
                        Text("\(selectedGameIds.count) selected")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                    
                    Spacer()
                    
                    Button("Let's rank 'em!") {
                        startRanking()
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedGameIds.isEmpty ? Color.adaptiveSilver : Color.accentOrange)
                    )
                    .disabled(selectedGameIds.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .background(Color.cardBackground) 
        }
    }
    
    private func gameGridItem(game: OnboardingGame) -> some View {
        let isSelected = selectedGameIds.contains(game.id)
        
        return Button {
            if isSelected {
                selectedGameIds.remove(game.id)
            } else {
                selectedGameIds.insert(game.id)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    AsyncImage(url: URL(string: game.coverUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Rectangle()
                                    .fill(Color.secondaryBackground)
                            .overlay(
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.adaptiveSilver)
                            )
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 120, maxHeight: 120)
                    .contentShape(Rectangle())
                    .clipped()
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.primaryBlue : Color.clear, lineWidth: 3)
                    )
                    .overlay(
                        isSelected ?
                            ZStack {
                                Color.black.opacity(0.35)
                                    .cornerRadius(10)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.white)
                            }
                        : nil
                    )
                }
                
                Text(game.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Logic
    
    private func togglePlatform(_ platform: OnboardingPlatform) {
        if selectedPlatforms.contains(platform) {
            selectedPlatforms.remove(platform)
        } else {
            selectedPlatforms.insert(platform)
        }
    }
    
    private func toggleGenre(_ genre: OnboardingGenre) {
        if selectedGenres.contains(genre) {
            selectedGenres.remove(genre)
        } else if selectedGenres.count < 3 {
            selectedGenres.insert(genre)
        }
    }
    
    private func loadFilteredGames() async {
        isLoadingGames = true
        
        let platformFilters = selectedPlatforms.map { $0.rawValue }
        let genreFilters = selectedGenres.map { $0.rawValue }
        
        do {
            let games: [OnboardingGame] = try await supabase.client
                .from("onboarding_games")
                .select()
                .order("popularity_score", ascending: false)
                .limit(1000)
                .execute()
                .value
            
            // Client-side filtering: match platform + genre, exclude DLC/editions
            let dlcTerms = ["dlc", "pack", "bundle", "edition", "definitive", "ultimate", "complete", "goty", "game of the year", "anniversary", "enhanced", "hd", "remaster", "remake", "collection", "season pass", "expansion"]
            
            let matched = games.filter { game in
                let hasMatchingPlatform = game.platforms.contains { platformFilters.contains($0) }
                let hasMatchingGenre = game.genres.contains { genreFilters.contains($0) }
                let titleLower = game.title.lowercased()
                let isDLC = dlcTerms.contains { titleLower.contains($0) }
                return hasMatchingPlatform && hasMatchingGenre && !isDLC
            }
            
            filteredGames = Array(matched.prefix(60))
            isLoadingGames = false
            step = .gameGrid
            
        } catch {
            print("Error fetching onboarding games: \(error)")
            isLoadingGames = false
            step = .gameGrid
        }
    }
    
    private func startRanking() {
        gamesToRank = filteredGames.filter { selectedGameIds.contains($0.id) }
        print("🎮 Starting ranking with \(gamesToRank.count) games")
        showRankingFlow = true
    }
}

// MARK: - Convert OnboardingGame to Game
extension OnboardingGame {
    func toGame() -> Game {
        Game(from: RAWGGame(
            id: self.rawgId,
            name: self.title,
            backgroundImage: self.coverUrl,
            released: self.releaseDate,
            metacritic: self.metacritic,
            genres: self.genres.map { RAWGGenre(id: 0, name: $0) },
            platforms: self.platforms.map { RAWGPlatformWrapper(platform: RAWGPlatform(id: 0, name: $0)) },
            added: self.popularityScore,
            rating: nil,
            descriptionRaw: nil,
            descriptionHtml: nil,
            tags: nil
        ))
    }
}

#Preview {
    OnboardingQuizView(isOnboardingComplete: .constant(false))
}
