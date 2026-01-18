import SwiftUI

struct ContentView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    
    var body: some View {
        Group {
            if supabase.isAuthenticated {
                // Main app (we'll build this later)
                HomeView()
            } else {
                // Auth flow
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
    }
}

// MARK: - Temporary Home View (placeholder)
struct HomeView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var showGameSearch = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 22))
            
            HStack(spacing: 0) {
                Text("played")
                    .font(.largeTitle)
                    .foregroundColor(.slate)
                Text("it")
                    .font(.largeTitle)
                    .foregroundColor(.accentOrange)
            }
            
            Text("Your list is waiting. What's the first game?")
                .font(.body)
                .foregroundColor(.grayText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Add Game Button
            Button {
                showGameSearch = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Log Game")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Sign out button
            Button {
                Task {
                    await supabase.signOut()
                }
            } label: {
                Text("Sign Out")
            }
            .buttonStyle(TertiaryButtonStyle())
            .padding(.bottom, 40)
        }
        .sheet(isPresented: $showGameSearch) {
            GameSearchView()
        }
    }
}

#Preview {
    ContentView()
}
