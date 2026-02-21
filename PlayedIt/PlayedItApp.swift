import SwiftUI
import SwiftData
import Auth
import Supabase

@main
struct PlayedItApp: App {
    @State private var deepLinkUsername: String?
    @State private var pendingDeepLinkUsername: String?
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
        }
        .modelContainer(sharedModelContainer)
    }
    
    private func handleDeepLink(_ url: URL) {
        print("🔗 Deep link received: \(url)")
        guard url.scheme == "playedit" else { return }
        
        // Handle auth callback (email confirmation auto-login)
        if url.host == "login-callback" {
            Task {
                do {
                    let session = try await SupabaseManager.shared.client.auth.session(from: url)
                    print("✅ Auto-logged in from email confirmation: \(session.user.email ?? "unknown")")
                } catch {
                    print("❌ Auto-login from confirmation failed: \(error)")
                }
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
