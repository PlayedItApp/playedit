import SwiftUI
import Auth
import Supabase

struct ResetPasswordView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSuccess = false
    @State private var errorMessage: String?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 40)
                    
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: isSuccess ? "checkmark.circle.fill" : "key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(isSuccess ? .teal : .primaryBlue)
                        
                        Text(isSuccess ? "Password updated!" : "Set new password")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.slate)
                        
                        Text(isSuccess
                             ? "You're all set. Go log some games!"
                             : "Choose a new password for your account.")
                            .font(.body)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    if !isSuccess {
                        // Password fields
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
                        }
                        .padding(.horizontal, 24)
                        
                        // Error message
                        if let error = errorMessage {
                            Text(error)
                                .font(.callout)
                                .foregroundColor(.error)
                                .padding(.horizontal, 24)
                        }
                        
                        // Save button
                        Button {
                            Task { await updatePassword() }
                        } label: {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Update Password")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(newPassword.isEmpty || confirmPassword.isEmpty || isLoading)
                        .opacity(newPassword.isEmpty || confirmPassword.isEmpty ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                    } else {
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
    }
    
    private func updatePassword() async {
        errorMessage = nil
        
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords don't match. Try again?"
            return
        }
        
        guard newPassword.count >= 6 else {
            errorMessage = "Password needs to be at least 6 characters."
            return
        }
        
        isLoading = true
        
        do {
            try await supabase.client.auth.update(user: .init(password: newPassword))
            isSuccess = true
        } catch {
            errorMessage = "Couldn't update password. Try again?"
        }
        
        isLoading = false
    }
}

#Preview {
    ResetPasswordView()
}
