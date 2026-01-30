import SwiftUI

struct ForgotPasswordView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var email = ""
    @State private var emailSent = false
    
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
                        Image(systemName: emailSent ? "checkmark.circle.fill" : "key.fill")
                            .font(.system(size: 60))
                            .foregroundColor(emailSent ? .teal : .primaryBlue)
                        
                        Text(emailSent ? "Check your email!" : "Forgot password?")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.slate)
                        
                        Text(emailSent
                             ? "We sent a reset link to \(email). Check your inbox (and spam folder)."
                             : "No worries! Enter your email and we'll send you a reset link.")
                            .font(.body)
                            .foregroundColor(.grayText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    
                    if !emailSent {
                        // Email Field
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
                        }
                        
                        // Send Button
                        Button {
                            Task {
                                let success = await supabase.resetPassword(email: email)
                                if success {
                                    withAnimation {
                                        emailSent = true
                                    }
                                }
                            }
                        } label: {
                            if supabase.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Send reset link")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(email.isEmpty || !email.contains("@") || supabase.isLoading)
                        .opacity(email.isEmpty || !email.contains("@") ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                    } else {
                        // Back to Login Button
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
        .navigationBarBackButtonHidden(emailSent)
        .toolbar {
            if !emailSent {
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
}

#Preview {
    NavigationStack {
        ForgotPasswordView()
    }
}
