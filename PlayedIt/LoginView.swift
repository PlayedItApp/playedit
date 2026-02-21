import SwiftUI
import AuthenticationServices
import CryptoKit

struct LoginView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var isAnimating = false
    @State private var currentNonce: String?
    @Environment(\.colorScheme) private var colorSchemeValue
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.appBackground
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer()
                            .frame(height: 40)
                        
                        // Logo & Welcome
                        VStack(spacing: 16) {
                            // Checkmark Logo
                                Image("Logo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                                .opacity(isAnimating ? 1.0 : 0.0)
                            
                            // App Name
                            HStack(spacing: 0) {
                                Text("played")
                                    .font(.largeTitle)
                                    .foregroundStyle(Color.adaptiveSlate)
                                Text("it")
                                    .font(.largeTitle)
                                    .foregroundColor(.accentOrange)
                            }
                            .opacity(isAnimating ? 1.0 : 0.0)
                            
                            Text("Rank your games!")
                                .font(.title3)
                                .foregroundStyle(Color.adaptiveGray)
                                .opacity(isAnimating ? 1.0 : 0.0)
                        }
                        .animation(.easeOut(duration: 0.6), value: isAnimating)
/* temp remove email login
                        // Form
                        VStack(spacing: 16) {
                            // Email or Username Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email or Username")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.adaptiveSlate)
                                
                                TextField("email or username", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .textContentType(.username)
                                    .playedItTextField()
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundStyle(Color.adaptiveSlate)
                                
                                SecureField("••••••••", text: $password)
                                    .textContentType(.password)
                                    .playedItTextField()
                                
                                HStack {
                                    Spacer()
                                    NavigationLink {
                                        ForgotPasswordView(prefillEmail: email)
                                    } label: {
                                        Text("Forgot password?")
                                            .font(.callout)
                                            .foregroundColor(.primaryBlue)
                                    }
                                    .simultaneousGesture(TapGesture().onEnded {
                                        supabase.errorMessage = nil
                                    })
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.2), value: isAnimating)
                        
 */
                        // Error Message
                        if let error = supabase.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.error)
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.error)
                            }
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        
                        // Buttons
                        VStack(spacing: 12) {
                            /* Temp hide email login
                             Button {
                             Task {
                             await supabase.signIn(email: email, password: password)
                             }
                             } label: {
                             if supabase.isLoading {
                             ProgressView()
                             .progressViewStyle(CircularProgressViewStyle(tint: .white))
                             } else {
                             Text("Let's go!")
                             }
                             }
                             .buttonStyle(PrimaryButtonStyle())
                             .disabled(email.isEmpty || password.isEmpty || supabase.isLoading)
                             .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                             
                             // Divider
                             HStack {
                             Rectangle()
                             .fill(Color.adaptiveSilver)
                             .frame(height: 1)
                             Text("or")
                             .font(.callout)
                             .foregroundStyle(Color.adaptiveGray)
                             Rectangle()
                             .fill(Color.adaptiveSilver)
                             .frame(height: 1)
                             }
                             .padding(.vertical, 4)
                             
                             */
                            // Sign in with Apple
                            SignInWithAppleButton(.signIn) { request in
                                let nonce = randomNonceString()
                                currentNonce = nonce
                                request.requestedScopes = [.email, .fullName]
                                request.nonce = sha256(nonce)
                            } onCompletion: { result in
                                switch result {
                                case .success(let authorization):
                                    handleAppleSignIn(authorization)
                                case .failure(let error):
                                    debugLog("❌ Apple sign in failed: \(error)")
                                }
                            }
                            .signInWithAppleButtonStyle(colorSchemeValue == .dark ? .white : .black)
                            .frame(height: 50)
                            .cornerRadius(12)
/*temp hide email login
                             Button {
                             showSignUp = true
                             } label: {
                             HStack(spacing: 4) {
                             Text("New here?")
                             .foregroundStyle(Color.adaptiveGray)
                             Text("Create an account")
                             .foregroundColor(.primaryBlue)
                             .fontWeight(.semibold)
                             }
                             .font(.callout)
                             }
                             .padding(.top, 8)
                             }
*/
                        }
                        .padding(.horizontal, 24)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.3), value: isAnimating)
                        
                        Spacer()
                    }
                }
            }
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView(initialEmail: email.contains("@") ? email : "", initialUsername: email.contains("@") ? "" : email, onDismissEmail: { returnedEmail in
                    if !returnedEmail.isEmpty {
                        email = returnedEmail
                    }
                })
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
    
    // MARK: - Apple Sign In Handler
    private func handleAppleSignIn(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8),
              let nonce = currentNonce else {
            debugLog("❌ Missing Apple credential data")
            return
        }
        
        Task {
            await supabase.signInWithApple(idToken: idToken, nonce: nonce)
        }
    }
    
    // MARK: - Nonce Helpers
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Logo View
struct LogoView: View {
    var size: CGFloat = 80
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color.primaryBlue)
                .frame(width: size, height: size)
            
            // Checkmark made of blocks
            HStack(alignment: .bottom, spacing: size * 0.05) {
                // Short bar (left part of check)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.cardBackground)
                    .frame(width: size * 0.15, height: size * 0.25)
                    .rotationEffect(.degrees(-10))
                    .offset(y: -size * 0.05)
                
                // Tall bar (right part of check)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentOrange)
                    .frame(width: size * 0.15, height: size * 0.5)
                    .rotationEffect(.degrees(15))
            }
        }
    }
}

#Preview {
    LoginView()
}
