import SwiftUI
import SwiftData
import Auth
import Supabase

@main
struct PlayedItApp: App {
    
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
            }
            .modelContainer(sharedModelContainer)
        }
}
