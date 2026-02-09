import Foundation
import Combine
import Supabase

// MARK: - Supabase Manager
@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        
        Task {
            await checkSession()
        }
    }
    
    // MARK: - Check Existing Session
    func checkSession() async {
        do {
            let session = try await client.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
        } catch {
            self.isAuthenticated = false
            self.currentUser = nil
        }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String, username: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        print("📝 Starting signup for email: \(email), username: \(username)")
        
        do {
            // Create auth user with username in metadata
            print("📝 Calling Supabase auth.signUp...")
            let authResponse = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["username": .string(username)]
            )
            
            let user = authResponse.user
            print("✅ Auth user created with ID: \(user.id)")
            print("📝 User metadata: \(String(describing: user.userMetadata))")
            
            self.currentUser = user
            self.isAuthenticated = true
            isLoading = false
            print("✅ Signup complete!")
            return true
            
        } catch {
            print("❌ Signup error: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            var loginEmail = email
            
            // If input doesn't contain @, it's a username — look up the email
            if !email.contains("@") {
                let response = try await client.from("users")
                    .select("email")
                    .eq("username", value: email)
                    .single()
                    .execute()
                
                if let userData = try? JSONDecoder().decode([String: String].self, from: response.data),
                   let foundEmail = userData["email"] {
                    loginEmail = foundEmail
                } else {
                    errorMessage = "Couldn't find that username. Try again?"
                    isLoading = false
                    return false
                }
            }
            
            let session = try await client.auth.signIn(
                email: loginEmail,
                password: password
            )
            
            self.currentUser = session.user
            self.isAuthenticated = true
            isLoading = false
            return true
            
        } catch {
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign Out
    func signOut() async {
        do {
            try await client.auth.signOut()
            self.currentUser = nil
            self.isAuthenticated = false
        } catch {
            errorMessage = parseError(error)
        }
    }
    
    // MARK: - Reset Password
    func resetPassword(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            try await client.auth.resetPasswordForEmail(
                email,
                redirectTo: URL(string: "playedit://reset-callback")
            )
            isLoading = false
            return true
        } catch {
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign in with Apple
    func signInWithApple(idToken: String, nonce: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            
            self.currentUser = session.user
            self.isAuthenticated = true
            isLoading = false
            return true
        } catch {
            print("❌ Apple sign in error: \(error)")
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Error Parsing
    private func parseError(_ error: Error) -> String {
        let errorString = error.localizedDescription.lowercased()
        
        if errorString.contains("invalid login credentials") {
            return "Hmm, that didn't work. Check your email and password?"
        } else if errorString.contains("email") && errorString.contains("taken") {
            return "That email's already in use. Try signing in instead?"
        } else if errorString.contains("username") {
            return "That username's taken. Try another one?"
        } else if errorString.contains("network") || errorString.contains("connection") {
            return "Can't connect right now. Check your internet and try again?"
        } else if errorString.contains("rate") || errorString.contains("limit") {
            return "Slow down, speedrunner! Give it a sec."
        } else {
            return "Oops! Something went wrong. Try again?"
        }
    }
    
    // MARK: - Link Apple ID
    func linkAppleID(idToken: String, nonce: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let session = try? await client.auth.session else {
                errorMessage = "No active session"
                isLoading = false
                return false
            }
            
            let url = URL(string: "\(Config.supabaseURL)/functions/v1/link-apple-identity")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: String] = ["idToken": idToken, "nonce": nonce]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                isLoading = false
                return false
            }
            
            if httpResponse.statusCode == 200 {
                // Refresh the session to pick up the new identity
                _ = try? await client.auth.refreshSession()
                isLoading = false
                return true
            } else {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let error = json["error"] as? String {
                    errorMessage = error
                } else {
                    errorMessage = "Failed to link Apple ID"
                }
                isLoading = false
                return false
            }
        } catch {
            print("❌ Link Apple ID error: \(error)")
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }

    // MARK: - Check if Apple ID is linked
    func hasAppleIdentity() async -> Bool {
        do {
            let identities = try await client.auth.userIdentities()
            return identities.contains { $0.provider == "apple" }
        } catch {
            print("❌ Error fetching identities: \(error)")
            return false
        }
    }
}
