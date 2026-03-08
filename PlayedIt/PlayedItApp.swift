import SwiftUI
import SwiftData
import Auth
import Supabase

@main
struct PlayedItApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var deepLinkUsername: String?
    @State private var pendingDeepLinkUsername: String?
    @State private var deepLinkGameId: Int?
    @State private var pendingDeepLinkGameId: Int?
    @State private var pendingReferrerUsername: String?
    @State private var showReferrerPrompt = false
    @StateObject private var supabase = SupabaseManager.shared
    @StateObject private var appearanceManager = AppearanceManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(SupabaseManager.shared)
                .preferredColorScheme(appearanceManager.colorScheme)
                .onAppear {
                    AnalyticsService.shared.track(.appOpened)
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                    let iosVersion = UIDevice.current.systemVersion
                    let deviceModel = UIDevice.current.model
                    debugLog("🚀 App launched: v\(appVersion) (\(buildNumber)), iOS \(iosVersion), \(deviceModel)")
                    AnalyticsService.shared.track(.sessionStarted)
                    let resolved: ColorScheme
                    if let manual = appearanceManager.colorScheme {
                        resolved = manual
                    } else {
                        resolved = UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
                    }
                    Task { await appearanceManager.syncResolvedAppearance(colorScheme: resolved) }
                }
                .environmentObject(appearanceManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: supabase.currentUser) { oldUser, newUser in
                    // User just signed up/in
                    if oldUser == nil && newUser != nil {
                        if pendingReferrerUsername != nil {
                            // Small delay so the main UI settles first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                showReferrerPrompt = true
                            }
                        }
                    }
                    if newUser != nil && pendingDeepLinkUsername != nil {
                        deepLinkUsername = pendingDeepLinkUsername
                        pendingDeepLinkUsername = nil
                    }
                    if newUser != nil && pendingDeepLinkGameId != nil {
                        deepLinkGameId = pendingDeepLinkGameId
                        pendingDeepLinkGameId = nil
                    }
                }
                .sheet(isPresented: $showReferrerPrompt) {
                    if let referrer = pendingReferrerUsername {
                        ReferrerPromptView(referrerUsername: referrer) {
                            pendingReferrerUsername = nil
                            showReferrerPrompt = false
                        }
                        .environmentObject(SupabaseManager.shared)
                        .presentationDetents([.height(320)])
                    }
                }
                .sheet(item: $deepLinkUsername) { username in
                    NavigationStack {
                        DeepLinkProfileView(username: username)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") {
                                        deepLinkUsername = nil
                                    }
                                }
                            }
                    }
                }
                .sheet(item: $deepLinkGameId) { gameId in
                    NavigationStack {
                        DeepLinkGameView(gameId: gameId)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Close") {
                                        deepLinkGameId = nil
                                    }
                                }
                            }
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        debugLog("🔗 Deep link received: \(url)")
        
        let linkType = url.pathComponents.contains("game") ? "game" : "profile"
        let linkSource = url.scheme == "https" ? "universal" : "custom_scheme"
        AnalyticsService.shared.track(.deepLinkOpened, properties: [
            "type": linkType,
            "source": linkSource
        ])
        
        // Handle Universal Links (https://playedit.app/...) and custom scheme (playedit://...)
        if url.scheme == "https" && url.host == "playedit.app" {
            if url.pathComponents.count >= 3 && url.pathComponents[1] == "game",
               let gId = Int(url.pathComponents.last ?? "") {
                // Capture referrer from ?user= param for new signups
                if supabase.currentUser == nil,
                   let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                   let referrer = components.queryItems?.first(where: { $0.name == "user" })?.value {
                    pendingReferrerUsername = referrer
                }
                AnalyticsService.shared.track(.deepLinkGameViewed, properties: [
                    "game_id": gId,
                    "has_referrer": pendingReferrerUsername != nil
                ])
                if supabase.currentUser == nil && pendingReferrerUsername != nil {
                    AnalyticsService.shared.track(.installFromShareLink, properties: [
                        "referrer": pendingReferrerUsername ?? ""
                    ])
                }
                if supabase.currentUser != nil {
                    deepLinkGameId = gId
                } else {
                    pendingDeepLinkGameId = gId
                }
            } else if url.pathComponents.count >= 3 && url.pathComponents[1] == "profile" {
                let uname = url.pathComponents[2]
                AnalyticsService.shared.track(.deepLinkProfileViewed, properties: [
                    "username": uname
                ])
                if supabase.currentUser != nil {
                    deepLinkUsername = uname
                } else {
                    pendingDeepLinkUsername = uname
                }
            }
            return
        }
        
        guard url.scheme == "playedit" else { return }
        
        // Handle auth callback (email confirmation auto-login)
        if url.host == "login-callback" {
            Task {
                do {
                    _ = try await SupabaseManager.shared.client.auth.session(from: url)
                    debugLog("✅ Auto-logged in from email confirmation")
                } catch {
                    debugLog("❌ Auto-login from confirmation failed: \(error)")
                }
            }
            return
        }
        
        if url.host == "game",
           let gameIdString = url.pathComponents.dropFirst().first,
           let gameId = Int(gameIdString) {
            if supabase.currentUser != nil {
                deepLinkGameId = gameId
            } else {
                pendingDeepLinkGameId = gameId
            }
            return
        }
        
        if url.host == "profile",
           let username = url.pathComponents.dropFirst().first {
            if supabase.currentUser != nil {
                deepLinkUsername = username
            } else {
                // Save for after login
                pendingDeepLinkUsername = username
            }
        }
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}
