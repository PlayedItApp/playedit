import Foundation
import UIKit
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
    @Published var needsEmailConfirmation = false
    @Published var pendingEmail: String?
    
    // MARK: - Diagnostic Logs
    func submitDiagnosticLogs(notes: String = "") async -> Bool {
        guard let userId = currentUser?.id else { return false }
        
        let username = try? await client.from("users")
            .select("username")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
        
        let usernameStr = (try? JSONDecoder().decode([String: String].self, from: username?.data ?? Data()))? ["username"] ?? "unknown"
        
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        
        struct DiagnosticLog: Encodable {
            let user_id: String
            let username: String
            let app_version: String
            let ios_version: String
            let device_model: String
            let logs: String
            let notes: String
        }
        
        let log = DiagnosticLog(
            user_id: userId.uuidString,
            username: usernameStr,
            app_version: "\(appVersion) (\(buildNumber))",
            ios_version: "\(device.systemName) \(device.systemVersion)",
            device_model: getDeviceModel(),
            logs: LogCollector.shared.export(),
            notes: notes
        )
        
        do {
            try await client.from("diagnostic_logs").insert(log).execute()
            debugLog("✅ Diagnostic logs submitted")
            return true
        } catch {
            debugLog("❌ Failed to submit logs: \(error)")
            return false
        }
    }

    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
    
    private init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
        
        Task {
            await checkSession()
        }

        Task {
            await setupAuthListener()
        }
    }
    
    // MARK: - Check Existing Session
    func checkSession() async {
        do {
            let session = try await client.auth.session
            if session.user.emailConfirmedAt == nil {
                try await client.auth.signOut()
                self.isAuthenticated = false
                self.currentUser = nil
                return
            }
            self.currentUser = session.user
            self.isAuthenticated = true
            debugLog("✅ Session restored for user \(session.user.id.uuidString.prefix(8))…")
        } catch {
            self.isAuthenticated = false
            self.currentUser = nil
            debugLog("ℹ️ No valid session found")
        }
    }
    
    // MARK: - Validate Session (called on foreground)
    func validateSession() async {
        do {
            let session = try await client.auth.session
            await MainActor.run {
                self.currentUser = session.user
                self.isAuthenticated = true
            }
            debugLog("✅ Session valid, token refreshed if needed")
        } catch {
            debugLog("⚠️ Session validation failed: \(error)")
            await MainActor.run {
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }
    
    // MARK: - Auth State Listener
    private func setupAuthListener() async {
        for await (event, session) in client.auth.authStateChanges {
            await MainActor.run {
                switch event {
                case .signedIn, .tokenRefreshed:
                    self.currentUser = session?.user
                    self.isAuthenticated = true
                case .signedOut:
                    self.currentUser = nil
                    self.isAuthenticated = false
                default:
                    break
                }
            }
        }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String, username: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        debugLog("📝 Starting signup for username: \(username)")
        
        do {
            // Create auth user with username in metadata
            debugLog("📝 Calling Supabase auth.signUp...")
            let authResponse = try await client.auth.signUp(
                email: email,
                password: password,
                data: ["username": .string(username)]
            )
            
            if let session = authResponse.session {
                self.currentUser = session.user
                self.isAuthenticated = true
                debugLog("✅ Auth user created with session, ID: \(session.user.id)")
            } else {
                // Email confirmation required
                self.needsEmailConfirmation = true
                self.pendingEmail = email
                debugLog("📧 Auth user created, awaiting email confirmation")
            }
            isLoading = false
            return true
            
        } catch {
            debugLog("❌ Signup error: \(error)")
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
            
            // If input doesn't contain @, it's a username - look up the email
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
            
            // Block unconfirmed email accounts
            if session.user.emailConfirmedAt == nil {
                try await client.auth.signOut()
                errorMessage = "Please confirm your email before signing in. Check your inbox!"
                isLoading = false
                return false
            }
            
            self.currentUser = session.user
            self.isAuthenticated = true
            isLoading = false
            return true
            
        } catch {
            debugLog("❌ Sign in error: \(error)")
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Sign Out
    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = parseError(error)
        }
        debugLog("👋 User signed out")
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    // MARK: - Custom Password Reset (bypasses Supabase email)
    func requestPasswordReset(email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(Config.supabaseURL)/functions/v1/request-reset")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email])
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if httpResponse.statusCode == 200 {
                isLoading = false
                return true
            } else {
                let result = try? JSONDecoder().decode([String: String].self, from: data)
                errorMessage = result?["error"] ?? "Something went wrong. Try again?"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Can't connect right now. Check your internet and try again?"
            isLoading = false
            return false
        }
    }
    
    func verifyResetCode(email: String, code: String, newPassword: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(Config.supabaseURL)/functions/v1/verify-reset")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: String] = [
                "email": email,
                "code": code,
                "new_password": newPassword
            ]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            if httpResponse.statusCode == 200 {
                isLoading = false
                return true
            } else {
                let result = try? JSONDecoder().decode([String: String].self, from: data)
                errorMessage = result?["error"] ?? "Something went wrong. Try again?"
                isLoading = false
                return false
            }
        } catch {
            errorMessage = "Can't connect right now. Check your internet and try again?"
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
            debugLog("❌ Apple sign in error: \(error)")
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
        } else if errorString.contains("email not confirmed") {
            return "Please confirm your email before signing in. Check your inbox!"
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
            debugLog("❌ Link Apple ID error: \(error)")
            errorMessage = parseError(error)
            isLoading = false
            return false
        }
    }
    
    // MARK: - Local Game Search
    func searchLocalGames(query: String) async throws -> [Game] {
        struct LocalGameRow: Decodable {
            let id: Int
            let rawg_id: Int
            let title: String
            let cover_url: String?
            let genres: [String]?
            let platforms: [String]?
            let release_date: String?
            let metacritic_score: Int?
            let tags: [String]?
            let curated_genres: [String]?
            let curated_tags: [String]?
        }

        let rows: [LocalGameRow] = try await client
            .from("games")
            .select("id, rawg_id, title, cover_url, genres, platforms, release_date, metacritic_score, tags, curated_genres, curated_tags")
            .ilike("title", pattern: "%\(query)%")
            .limit(20)
            .execute()
            .value

        return rows.map { row in
            Game(
                id: row.id,
                rawgId: row.rawg_id,
                title: row.title,
                coverURL: row.cover_url,
                genres: row.curated_genres ?? row.genres ?? [],
                platforms: row.platforms ?? [],
                releaseDate: row.release_date,
                metacriticScore: row.metacritic_score,
                added: nil,
                rating: nil,
                gameDescription: nil,
                tags: row.curated_tags ?? row.tags ?? []
            )
        }
    }

    // MARK: - Check if Apple ID is linked
    func hasAppleIdentity() async -> Bool {
        do {
            let identities = try await client.auth.userIdentities()
            return identities.contains { $0.provider == "apple" }
        } catch {
            debugLog("❌ Error fetching identities: \(error)")
            return false
        }
    }
}
