import SwiftUI
import SwiftData
import Auth
import Supabase

@main
struct PlayedItApp: App {
    @State private var showResetPassword = false
    
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
                    .preferredColorScheme(.light)
                    .onOpenURL { url in
                        Task {
                            _ = try? await SupabaseManager.shared.client.auth.session(from: url)
                            showResetPassword = true
                        }
                    }
                    .sheet(isPresented: $showResetPassword) {
                        ResetPasswordView()
                    }
            }
            .modelContainer(sharedModelContainer)
        }
}
