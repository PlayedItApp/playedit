import SwiftUI
import Supabase

struct ProfileView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var username = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var message: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Avatar
                Circle()
                    .fill(Color.primaryBlue.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Text(String(username.prefix(1)).uppercased())
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.primaryBlue)
                    )
                    .padding(.top, 20)
                
                // Username
                VStack(spacing: 8) {
                    Text("Username")
                        .font(.caption)
                        .foregroundColor(.grayText)
                    
                    if isEditing {
                        TextField("username", text: $username)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .frame(width: 200)
                    } else {
                        Text(username.isEmpty ? "Set a username" : username)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundColor(username.isEmpty ? .grayText : .slate)
                    }
                }
                
                // Edit/Save button
                Button {
                    if isEditing {
                        Task { await saveUsername() }
                    } else {
                        isEditing = true
                    }
                } label: {
                    Text(isEditing ? "Save" : "Edit Username")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isSaving)
                
                if let message = message {
                    Text(message)
                        .font(.callout)
                        .foregroundColor(.success)
                }
                
                Spacer()
                
                // Sign out
                Button {
                    Task {
                        await supabase.signOut()
                    }
                } label: {
                    Text("Sign Out")
                }
                .buttonStyle(TertiaryButtonStyle())
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            await fetchProfile()
        }
    }
    
    private func fetchProfile() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct UserProfile: Decodable {
                let username: String?
            }
            
            let profile: UserProfile = try await supabase.client
                .from("users")
                .select("username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            username = profile.username ?? ""
            
        } catch {
            print("❌ Error fetching profile: \(error)")
        }
    }
    
    private func saveUsername() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        isSaving = true
        message = nil
        
        do {
            try await supabase.client
                .from("users")
                .update(["username": username])
                .eq("id", value: userId.uuidString)
                .execute()
            
            message = "Username saved!"
            isEditing = false
            
        } catch {
            print("❌ Error saving username: \(error)")
            message = "Couldn't save username"
        }
        
        isSaving = false
    }
}

#Preview {
    ProfileView()
}
