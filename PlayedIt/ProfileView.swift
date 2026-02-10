import SwiftUI
import Supabase
import PhotosUI
import AuthenticationServices
import CryptoKit

struct ProfileView: View {
    @ObservedObject var supabase = SupabaseManager.shared
    @State private var username = ""
    @State private var originalUsername = ""
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var message: String?
    @State private var rankedGames: [UserGame] = []
    @State private var isLoadingGames = true
    @State private var avatarURL: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var selectedImage: UIImage?
    @State private var hasAppleLinked = false
    @State private var currentNonce: String?
    @State private var appleLinkDelegate: AppleLinkDelegate?
    @AppStorage("startTab") private var startTab = 0
    @State private var showGameSearch = false
    @State private var selectedListTab = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header - Avatar and Username side by side
                    HStack(spacing: 16) {
                        // Avatar
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            ZStack {
                                if let avatarURL = avatarURL, let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.primaryBlue.opacity(0.2))
                                            .overlay(ProgressView())
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(Color.primaryBlue.opacity(0.2))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Text(String(username.prefix(1)).uppercased())
                                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                                .foregroundColor(.primaryBlue)
                                        )
                                }
                                
                                if isUploadingPhoto {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                        .overlay(ProgressView().tint(.white))
                                } else if isEditing {
                                    Circle()
                                        .fill(Color.black.opacity(0.5))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            VStack(spacing: 2) {
                                                Image(systemName: "camera")
                                                    .font(.system(size: 20))
                                                Text("Edit")
                                                    .font(.caption2)
                                            }
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                        }
                        .disabled(!isEditing)
                        
                        // Username and Stats
                        VStack(alignment: .leading, spacing: 8) {
                            if isEditing {
                                TextField("username", text: $username)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled()
                                
                                HStack(spacing: 12) {
                                    Button {
                                        username = originalUsername
                                        isEditing = false
                                        message = nil
                                    } label: {
                                        Text("Cancel")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    
                                    Button {
                                        Task { await saveUsername() }
                                    } label: {
                                        Text(isSaving ? "Saving..." : "Save")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(PrimaryButtonStyle())
                                    .disabled(isSaving)
                                }
                            } else {
                                Text(username.isEmpty ? "Set a username" : username)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(username.isEmpty ? .grayText : .slate)
                                
                                Text("\(rankedGames.count) games ranked")
                                    .font(.subheadline)
                                    .foregroundColor(.grayText)
                                
                                Button {
                                    isEditing = true
                                } label: {
                                    Text("Edit Profile")
                                        .font(.caption)
                                }
                                .foregroundColor(.primaryBlue)
                            }
                            
                            if let message = message {
                                Text(message)
                                    .font(.caption)
                                    .foregroundColor(.success)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal, 20)
                    
                    // Tab Picker
                    Picker("List", selection: $selectedListTab) {
                        Text("Ranked").tag(0)
                        Text("Want to Play").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    
                    // List Content
                    VStack(alignment: .leading, spacing: 12) {
                        if selectedListTab == 0 {
                            // Ranked Games
                            if isLoadingGames {
                                ProgressView()
                                    .padding(.top, 20)
                            } else if rankedGames.isEmpty {
                                VStack(spacing: 8) {
                                    Text("No games ranked yet")
                                        .font(.body)
                                        .foregroundColor(.grayText)
                                    Text("Your list is waiting. What's the first game?")
                                        .font(.caption)
                                        .foregroundColor(.silver)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                            } else {
                                ForEach(Array(rankedGames.enumerated()), id: \.element.id) { index, game in
                                    RankedGameRow(rank: index + 1, game: game) {
                                        Task { await fetchRankedGames() }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            // Want to Play
                            WantToPlayListView()
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGameSearch) {
                GameSearchView()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showGameSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primaryBlue)
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if !hasAppleLinked {
                            Button {
                                triggerAppleLinking()
                            } label: {
                                Label("Link Apple ID", systemImage: "apple.logo")
                            }
                        }
                        
                        Menu {
                            Button { startTab = 0 } label: {
                                HStack {
                                    Text("Feed")
                                    if startTab == 0 { Image(systemName: "checkmark") }
                                }
                            }
                            Button { startTab = 1 } label: {
                                HStack {
                                    Text("Friends")
                                    if startTab == 1 { Image(systemName: "checkmark") }
                                }
                            }
                            Button { startTab = 2 } label: {
                                HStack {
                                    Text("Profile")
                                    if startTab == 2 { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            Label("Start Screen", systemImage: "house")
                        }
                        
                        NavigationLink {
                            FeedbackView()
                        } label: {
                            Label("Send Feedback", systemImage: "bubble.left.and.bubble.right")
                        }
                        
                        Button(role: .destructive) {
                            Task { await supabase.signOut() }
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.primaryBlue)
                    }
                }
            }
        }
        .task {
            await fetchProfile()
            await fetchRankedGames()
            hasAppleLinked = await supabase.hasAppleIdentity()
        }
        .onChange(of: selectedPhoto) { _, newValue in
            if let newValue = newValue {
                Task {
                    print("📸 Photo selected, loading...")
                    do {
                        if let data = try await newValue.loadTransferable(type: Data.self) {
                            print("📸 Data loaded: \(data.count) bytes")
                            if let uiImage = UIImage(data: data) {
                                print("📸 Image created: \(uiImage.size)")
                                await MainActor.run {
                                    selectedImage = uiImage
                                }
                            } else {
                                print("❌ Could not create UIImage from data")
                            }
                        } else {
                            print("❌ Data was nil")
                        }
                    } catch {
                        print("❌ Error loading photo: \(error)")
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedImage) { image in
            ImageCropperView(
                image: image,
                onCrop: { croppedImage in
                    selectedImage = nil
                    selectedPhoto = nil
                    Task { await uploadCroppedPhoto(croppedImage) }
                },
                onCancel: {
                    selectedImage = nil
                    selectedPhoto = nil
                }
            )
        }
    }
    
    private func fetchProfile() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        do {
            struct UserProfile: Decodable {
                let username: String?
                let avatar_url: String?
            }
            
            let profile: UserProfile = try await supabase.client
                .from("users")
                .select("username, avatar_url")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            username = profile.username ?? ""
            originalUsername = profile.username ?? ""
            avatarURL = profile.avatar_url
            
        } catch {
            print("❌ Error fetching profile: \(error)")
        }
    }
    
    private func fetchRankedGames() async {
        guard let userId = supabase.currentUser?.id else {
            isLoadingGames = false
            return
        }
        
        do {
            struct UserGameRow: Decodable {
                let id: String
                let game_id: Int
                let user_id: String
                let rank_position: Int
                let platform_played: [String]
                let notes: String?
                let logged_at: String?
                let games: GameDetails
                
                struct GameDetails: Decodable {
                    let title: String
                    let cover_url: String?
                    let release_date: String?
                }
            }
            
            let rows: [UserGameRow] = try await supabase.client
                .from("user_games")
                .select("*, games(title, cover_url, release_date)")
                .eq("user_id", value: userId.uuidString)
                .order("rank_position", ascending: true)
                .execute()
                .value
            
            rankedGames = rows.map { row in
                UserGame(
                    id: row.id,
                    gameId: row.game_id,
                    userId: row.user_id,
                    rankPosition: row.rank_position,
                    platformPlayed: row.platform_played,
                    notes: row.notes,
                    loggedAt: row.logged_at,
                    canonicalGameId: nil,
                    gameTitle: row.games.title,
                    gameCoverURL: row.games.cover_url,
                    gameReleaseDate: row.games.release_date
                )
            }
            
        } catch {
            print("❌ Error fetching ranked games: \(error)")
        }
        
        isLoadingGames = false
    }
    private func saveUsername() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        // Only save if username actually changed
        guard username != originalUsername else {
            isEditing = false
            return
        }
        
        isSaving = true
        message = nil
        
        do {
            try await supabase.client
                .from("users")
                .update(["username": username])
                .eq("id", value: userId.uuidString)
                .execute()
            
            originalUsername = username
            message = "Username saved!"
            isEditing = false
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                message = nil
            }
            
        } catch {
            print("❌ Error saving username: \(error)")
            message = "Couldn't save username"
        }
        
        isSaving = false
    }
    
    private func uploadCroppedPhoto(_ image: UIImage) async {
        isUploadingPhoto = true
        
        guard let userId = supabase.currentUser?.id else {
            isUploadingPhoto = false
            return
        }
        
        do {
            guard let compressedData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Could not compress image")
                isUploadingPhoto = false
                return
            }
            
            let fileName = "\(userId.uuidString)/avatar.jpg"
            
            try await supabase.client.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: compressedData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.client.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            
            let urlWithCacheBuster = "\(publicURL.absoluteString)?v=\(Int(Date().timeIntervalSince1970))"
            
            try await supabase.client
                .from("users")
                .update(["avatar_url": urlWithCacheBuster])
                .eq("id", value: userId.uuidString)
                .execute()
            
            // Clear the URL first to force AsyncImage to reload
            await MainActor.run {
                avatarURL = nil
            }
            
            // Small delay then set the new URL
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            await MainActor.run {
                avatarURL = urlWithCacheBuster
            }
            
        } catch {
            print("❌ Error uploading photo: \(error)")
        }
        
        isUploadingPhoto = false
    }
    
    // MARK: - Apple ID Linking
    private func triggerAppleLinking() {
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let delegate = AppleLinkDelegate(nonce: nonce) { success in
            if success {
                hasAppleLinked = true
                message = "Apple ID linked!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    message = nil
                }
            }
        }
        appleLinkDelegate = delegate
        controller.delegate = delegate
        print("🍎 Performing Apple auth request...")
        controller.performRequests()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("SecRandomCopyBytes failed with OSStatus \(errorCode)")
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

// MARK: - Apple Link Delegate
class AppleLinkDelegate: NSObject, ASAuthorizationControllerDelegate {
    let nonce: String
    let completion: (Bool) -> Void
    
    init(nonce: String, completion: @escaping (Bool) -> Void) {
        self.nonce = nonce
        self.completion = completion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        print("🍎 Apple auth completed successfully")
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let idToken = String(data: identityTokenData, encoding: .utf8) else {
            print("❌ Missing Apple credential data")
            completion(false)
            return
        }
        print("🍎 Got Apple ID token, calling Edge Function...")
        
        Task {
            let success = await SupabaseManager.shared.linkAppleID(idToken: idToken, nonce: nonce)
            print("🍎 Edge Function result: \(success)")
            if let error = SupabaseManager.shared.errorMessage {
                print("🍎 Error message: \(error)")
            }
            await MainActor.run {
                completion(success)
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("❌ Apple linking failed: \(error)")
        completion(false)
    }
}

extension UIImage: @retroactive Identifiable {
    public var id: Int {
        hashValue
    }
}

#Preview {
    ProfileView()
}
