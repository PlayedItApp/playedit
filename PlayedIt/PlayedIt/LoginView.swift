import SwiftUI

struct LoginView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var isAnimating = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.white
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
                                    .foregroundColor(.slate)
                                Text("it")
                                    .font(.largeTitle)
                                    .foregroundColor(.accentOrange)
                            }
                            .opacity(isAnimating ? 1.0 : 0.0)
                            
                            Text("Welcome back!")
                                .font(.title3)
                                .foregroundColor(.grayText)
                                .opacity(isAnimating ? 1.0 : 0.0)
                        }
                        .animation(.easeOut(duration: 0.6), value: isAnimating)
                        
                        // Form
                        VStack(spacing: 16) {
                            // Email or Username Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Email or Username")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slate)
                                
                                TextField("email or username", text: $email)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .playedItTextField()
                            }
                            
                            // Password Field
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Password")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slate)
                                
                                SecureField("••••••••", text: $password)
                                    .playedItTextField()
                            }
                        }
                        .padding(.horizontal, 24)
                        .opacity(isAnimating ? 1.0 : 0.0)
                        .offset(y: isAnimating ? 0 : 20)
                        .animation(.easeOut(duration: 0.6).delay(0.2), value: isAnimating)
                        
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
                            
                            Button {
                                showSignUp = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("New here?")
                                        .foregroundColor(.grayText)
                                    Text("Create an account")
                                        .foregroundColor(.primaryBlue)
                                        .fontWeight(.semibold)
                                }
                                .font(.callout)
                            }
                            .padding(.top, 8)
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
                SignUpView()
            }
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
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
                    .fill(Color.white)
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
