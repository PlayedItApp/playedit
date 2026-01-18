import SwiftUI

struct SignUpView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isAnimating = false
    
    var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }
    
    var isFormValid: Bool {
        !email.isEmpty && !username.isEmpty && !password.isEmpty && passwordsMatch
    }
    
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
                            .font(.title1)
                            .foregroundColor(.slate)
                            .multilineTextAlignment(.center)
                        
                        Text("Rank games you've played and see how your taste stacks up against friends.")
                            .font(.body)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.5), value: isAnimating)
                    
                    // Form
                    VStack(spacing: 16) {
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            TextField("your@email.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .playedItTextField()
                        }
                        
                        // Username
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            TextField("coolplayer42", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .playedItTextField()
                            
                            Text("This is how friends will find you")
                                .font(.caption)
                                .foregroundColor(.grayText)
                        }
                        
                        // Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            SecureField("At least 8 characters", text: $password)
                                .playedItTextField()
                        }
                        
                        // Confirm Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            SecureField("Type it again", text: $confirmPassword)
                                .playedItTextField()
                            
                            // Password match indicator
                            if !confirmPassword.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(passwordsMatch ? .success : .error)
                                    Text(passwordsMatch ? "Passwords match!" : "Passwords don't match")
                                        .font(.caption)
                                        .foregroundColor(passwordsMatch ? .success : .error)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(isAnimating ? 1.0 : 0.0)
                    .offset(y: isAnimating ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: isAnimating)
                    
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
                    
                    // Sign Up Button
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                let success = await supabase.signUp(
                                    email: email,
                                    password: password,
                                    username: username
                                )
                                if success {
                                    dismiss()
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
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
            withAnimation {
                isAnimating = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        SignUpView()
    }
}
