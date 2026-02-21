import SwiftUI
import Supabase

struct EmailConfirmationView: View {
    let email: String
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var isChecking = false
    @State private var showLogin = false
    @State private var resendCooldown = 0
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Email icon
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.primaryBlue)
                
                // Title
                VStack(spacing: 12) {
                    Text("Check your email!")
                        .foregroundStyle(Color.adaptiveSlate)
                        .font(Font.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("We sent a confirmation link to:")
                        .font(Font.body)
                        .foregroundStyle(Color.adaptiveGray)
                    
                    Text(email)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                }
                
                // Instructions
                VStack(spacing: 8) {
                    Text("Tap the link in the email to confirm your account, then come back and sign in.")
                        .font(Font.body)
                        .foregroundStyle(Color.adaptiveGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Text("Check your spam folder if you don't see it!")
                        .font(.callout)
                        .foregroundStyle(Color.adaptiveGray)
                        .italic()
                }
                
                // Buttons
                VStack(spacing: 16) {
                    Button {
                        showLogin = true
                    } label: {
                        Text("Go to Sign In")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    
                    Button {
                        Task { await resendConfirmation() }
                    } label: {
                        if resendCooldown > 0 {
                            Text("Resend in \(resendCooldown)s")
                                .foregroundStyle(Color.adaptiveGray)
                        } else {
                            Text("Resend confirmation email")
                                .foregroundColor(.primaryBlue)
                        }
                    }
                    .disabled(resendCooldown > 0)
                    .font(.callout)
                }
                .padding(.horizontal, 24)
                
                Spacer()
                Spacer()
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(isPresented: $showLogin) {
            LoginView()
        }
    }
    
    private func resendConfirmation() async {
        guard let url = URL(string: "\(Config.supabaseURL)/functions/v1/resend-confirmation") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONEncoder().encode(["email": email])
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                debugLog("🔄 Resend response: \(httpResponse.statusCode)")
            }
        } catch {
            debugLog("❌ Error resending: \(error)")
        }
        
        // Start cooldown
        resendCooldown = 60
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                resendCooldown -= 1
                if resendCooldown <= 0 {
                    timer?.invalidate()
                    timer = nil
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EmailConfirmationView(email: "test@example.com")
    }
}
