import SwiftUI

struct SignUpView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) var dismiss
    
    var initialEmail: String = ""
    var initialUsername: String = ""
    var onDismissEmail: ((String) -> Void)?
    
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isAnimating = false
    @State private var moderationError: String?
    @State private var showEmailConfirmation = false
    
    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    private var hasMinLength: Bool { password.count >= 6 }
    private var hasUppercase: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    private var hasLowercase: Bool { password.rangeOfCharacter(from: .lowercaseLetters) != nil }
    private var hasNumberOrSpecial: Bool {
        password.rangeOfCharacter(from: .decimalDigits) != nil ||
        password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;':\",./<>?")) != nil
    }
    private var passwordMeetsRequirements: Bool {
        hasMinLength && hasUppercase && hasLowercase && hasNumberOrSpecial
    }

    var isFormValid: Bool {
        !email.isEmpty && !username.isEmpty && !password.isEmpty && passwordMeetsRequirements
    }
    /*
    var isFormValid: Bool {
        !email.isEmpty && !username.isEmpty && !password.isEmpty && passwordsMatch
    }
    */
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 20)
                    
                    // Header
                    VStack(spacing: 12) {
                        Text("Let's build your gaming history!")
                            .font(Font.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.adaptiveSlate)
                            .multilineTextAlignment(.center)
                        
                        Text("Rank games you've played and see how your taste stacks up against friends.")
                            .font(.body)
                            .foregroundStyle(Color.adaptiveGray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.5), value: isAnimating)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Username
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            TextField("coolplayer42", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .playedItTextField()
                            
                            Text("This is how friends will find you")
                                .font(.caption)
                                .foregroundStyle(Color.adaptiveGray)
                        }
                        
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            TextField("your@email.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .playedItTextField()
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            SecureField("At least 6 characters", text: $password)
                                .textContentType(.password)
                                .playedItTextField()
                            
                            // Password Requirements
                            if !password.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    PasswordRequirementRow(label: "At least 6 characters", isMet: hasMinLength)
                                    PasswordRequirementRow(label: "One uppercase letter", isMet: hasUppercase)
                                    PasswordRequirementRow(label: "One lowercase letter", isMet: hasLowercase)
                                    PasswordRequirementRow(label: "One number or special character", isMet: hasNumberOrSpecial)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: isAnimating)
                    
                    // Error Message
                    if let error = moderationError ?? supabase.errorMessage {
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
                    
                    // Sign Up Button
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                moderationError = nil
                                
                                // Check username moderation
                                let result = await ModerationService.shared.moderateUsername(username)
                                if !result.allowed {
                                    moderationError = result.reason
                                    return
                                }
                                
                                let success = await supabase.signUp(
                                    email: email,
                                    password: password,
                                    username: username
                                )
                                if success {
                                    if supabase.needsEmailConfirmation {
                                        showEmailConfirmation = true
                                    } else {
                                        dismiss()
                                    }
                                }
                            }
                        } label: {
                            if supabase.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Create Account")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!isFormValid || supabase.isLoading)
                        .opacity(isFormValid ? 1.0 : 0.6)
                        
                        Button {
                            onDismissEmail?(email)
                            dismiss()
                        } label: {
                            Text("Already have an account? Sign in")
                                .font(.callout)
                                .foregroundColor(.primaryBlue)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: isAnimating)
                    
                    Spacer()
                }
            }
        }
        .navigationDestination(isPresented: $showEmailConfirmation) {
            EmailConfirmationView(email: email)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onDismissEmail?(email)
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                        Text("Back")
                    }
                    .foregroundColor(.primaryBlue)
                }
            }
        }
        .onAppear {
            if email.isEmpty && !initialEmail.isEmpty {
                email = initialEmail
            }
            if username.isEmpty && !initialUsername.isEmpty {
                username = initialUsername
            }
            withAnimation {
                isAnimating = true
            }
        }
    }
}

struct PasswordRequirementRow: View {
    let label: String
    let isMet: Bool
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.caption)
                .foregroundColor(isMet ? .success : .silver)
                .contentTransition(.interpolate)
            Text(label)
                .font(.caption)
                .foregroundColor(isMet ? .success : .gray)
                .contentTransition(.interpolate)
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView(initialEmail: "", onDismissEmail: nil)
    }
}
