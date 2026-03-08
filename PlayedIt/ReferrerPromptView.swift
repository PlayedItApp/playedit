import SwiftUI
import Supabase

struct ReferrerPromptView: View {
    let referrerUsername: String
    let onDismiss: () -> Void
    
    @State private var isSending = false
    @State private var didSend = false
    @EnvironmentObject var supabase: SupabaseManager
    
    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.adaptiveSilver)
                .frame(width: 36, height: 4)
                .padding(.top, 12)
            
            Text("👋")
                .font(.system(size: 48))
            
            VStack(spacing: 8) {
                Text("You found PlayedIt through")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
                Text(referrerUsername)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
                Text("Want to add them as a friend?")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Color.adaptiveGray)
            }
            .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button("Maybe later") {
                    onDismiss()
                }
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.adaptiveGray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Button {
                    Task { await sendFriendRequest() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else if didSend {
                            Label("Sent!", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        } else {
                            Text("Add Friend")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(didSend ? Color.success : Color.primaryBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSending || didSend)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground)
        .onAppear {
            AnalyticsService.shared.track(.referrerPromptShown, properties: [
                "referrer_username": referrerUsername
            ])
        }
    }
    
    private func sendFriendRequest() async {
        guard let myId = supabase.currentUser?.id else { return }
        isSending = true
        
        do {
            // Look up referrer's user ID by username
            struct UserRow: Decodable {
                let id: String
            }
            let users: [UserRow] = try await supabase.client
                .from("users")
                .select("id")
                .eq("username", value: referrerUsername)
                .limit(1)
                .execute()
                .value
            
            guard let referrerId = users.first?.id else {
                isSending = false
                onDismiss()
                return
            }
            
            // Insert friendship request
            try await supabase.client
                .from("friendships")
                .insert([
                    "user_id": myId.uuidString.lowercased(),
                    "friend_id": referrerId.lowercased(),
                    "status": "pending"
                ])
                .execute()
            
            AnalyticsService.shared.track(.referrerPromptAccepted, properties: [
                "referrer_username": referrerUsername
            ])
            didSend = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                onDismiss()
            }
        } catch {
            debugLog("❌ ReferrerPrompt: failed to send friend request: \(error)")
            isSending = false
            onDismiss()
        }
    }
}
