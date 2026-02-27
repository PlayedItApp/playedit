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
    @ObservedObject private var supabase = SupabaseManager.shared
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
                .preferredColorScheme(appearanceManager.colorScheme)
                .onAppear {
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
                .onChange(of: supabase.currentUser) { _, newUser in
                    // If user just logged in and we have a pending deep link, present it
                    if newUser != nil && pendingDeepLinkUsername != nil {
                        deepLinkUsername = pendingDeepLinkUsername
                        pendingDeepLinkUsername = nil
                    }
                    if newUser != nil && pendingDeepLinkGameId != nil {
                        deepLinkGameId = pendingDeepLinkGameId
                        pendingDeepLinkGameId = nil
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
        // Handle Universal Links (https://playedit.app/...) and custom scheme (playedit://...)
        if url.scheme == "https" && url.host == "playedit.app" {
            if url.pathComponents.count >= 3 && url.pathComponents[1] == "game",
               let gId = Int(url.pathComponents.last ?? "") {
                if supabase.currentUser != nil {
                    deepLinkGameId = gId
                } else {
                    pendingDeepLinkGameId = gId
                }
            } else if url.pathComponents.count >= 3 && url.pathComponents[1] == "profile" {
                let uname = url.pathComponents[2]
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
                    let session = try await SupabaseManager.shared.client.auth.session(from: url)
                    debugLog("✅ Auto-logged in from email confirmation: \(session.user.email ?? "unknown")")
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
