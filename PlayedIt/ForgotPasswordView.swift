import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var prefillEmail: String = ""
    @State private var email = ""
    @State private var emailSent = false
    @State private var code = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var step: Int = 1  // 1=email, 2=code, 3=password, 4=success
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 40)
                    
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: stepIcon)
                            .font(.system(size: 60))
                            .foregroundColor(step == 4 ? .teal : .primaryBlue)
                        
                        Text(stepTitle)
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.slate)
                        
                        Text(stepSubtitle)
                            .font(.body)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    // Step 1: Enter email
                    if step == 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            TextField("your@email.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .playedItTextField()
                        }
                        .padding(.horizontal, 24)
                        
                        if let error = supabase.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.error)
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.error)
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Button {
                            Task {
                                let success = await supabase.requestPasswordReset(email: email)
                                if success {
                                    withAnimation { step = 2 }
                                }
                            }
                        } label: {
                            if supabase.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Send Reset Code")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(email.isEmpty || !email.contains("@") || supabase.isLoading)
                        .opacity(email.isEmpty || !email.contains("@") ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                    }
                    
                    // Step 2: Enter code
                    if step == 2 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Reset Code")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.slate)
                            
                            TextField("6-digit code", text: $code)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .playedItTextField()
                                .onChange(of: code) { oldValue, newValue in
                                    code = String(newValue.filter { $0.isNumber }.prefix(6))
                                }
                        }
                        .padding(.horizontal, 24)
                        
                        if let error = supabase.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.error)
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.error)
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Button {
                            withAnimation { step = 3 }
                        } label: {
                            Text("Verify Code")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(code.count != 6)
                        .opacity(code.count != 6 ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                        
                        Button {
                            code = ""
                            supabase.errorMessage = nil
                            Task {
                                await supabase.requestPasswordReset(email: email)
                            }
                        } label: {
                            Text("Didn't get it? Send again")
                                .font(.callout)
                                .foregroundColor(.primaryBlue)
                        }
                        .disabled(supabase.isLoading)
                        .padding(.horizontal, 24)
                    }
                    
                    // Step 3: New password
                    if step == 3 {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("New Password")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slate)
                                
                                SecureField("••••••••", text: $newPassword)
                                    .playedItTextField()
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Confirm Password")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.slate)
                                
                                SecureField("••••••••", text: $confirmPassword)
                                    .playedItTextField()
                            }
                            
                            if !newPassword.isEmpty && newPassword.count < 6 {
                                Text("Password needs to be at least 6 characters.")
                                    .font(.caption)
                                    .foregroundColor(.grayText)
                            }
                            
                            if !confirmPassword.isEmpty && newPassword != confirmPassword {
                                Text("Passwords don't match.")
                                    .font(.caption)
                                    .foregroundColor(.error)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        if let error = supabase.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.error)
                                Text(error)
                                    .font(.callout)
                                    .foregroundColor(.error)
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Button {
                            Task {
                                let success = await supabase.verifyResetCode(
                                    email: email,
                                    code: code,
                                    newPassword: newPassword
                                )
                                if success {
                                    withAnimation { step = 4 }
                                }
                            }
                        } label: {
                            if supabase.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Reset Password")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(newPassword.count < 6 || newPassword != confirmPassword || supabase.isLoading)
                        .opacity(newPassword.count < 6 || newPassword != confirmPassword ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                    }
                    
                    // Step 4: Success
                    if step == 4 {
                        Button {
                            dismiss()
                        } label: {
                            Text("Back to login")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 24)
                    }
                    
                    Spacer()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if !prefillEmail.isEmpty && email.isEmpty {
                email = prefillEmail
            }
        }
        .toolbar {
            if step < 4 {
                    ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.slate)
                    }
                }
            }
        }
    }
        
        // MARK: - Step Helpers
        
        private var stepIcon: String {
            switch step {
            case 1: return "envelope.fill"
            case 2: return "number.circle.fill"
            case 3: return "key.fill"
            case 4: return "checkmark.circle.fill"
            default: return "key.fill"
            }
        }
        
        private var stepTitle: String {
            switch step {
            case 1: return "Forgot password?"
            case 2: return "Check your email!"
            case 3: return "Set new password"
            case 4: return "Password updated!"
            default: return ""
            }
        }
        
        private var stepSubtitle: String {
            switch step {
            case 1: return "No worries! Enter your email and we'll send you a reset code."
            case 2: return "We sent a 6-digit code to \(email)"
            case 3: return "Choose a new password for your account."
            case 4: return "You're all set. Go log some games! 🎮"
            default: return ""
            }
        }
    }

    #Preview {
    NavigationStack {
        ForgotPasswordView()
    }
}
