import SwiftUI
import Supabase
import PhotosUI

struct FeedbackView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var supabase = SupabaseManager.shared
    
    @State private var feedbackType: FeedbackType = .bug
    @State private var description = ""
    @State private var stepsToReproduce = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var screenshotData: Data?
    @State private var screenshotPreview: UIImage?
    
    enum FeedbackType: String, CaseIterable {
        case bug = "Bug"
        case feature = "Feature"
        case help = "Help"
        
        var displayName: String {
            switch self {
            case .bug: return "Bug Report"
            case .feature: return "Feature Request"
            case .help: return "Help"
            }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Found a bug? Have an idea? We're all ears.")
                    .font(.subheadline)
                    .foregroundColor(.grayText)
                    .padding(.top, 8)
                
                // Feedback Type Picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.slate)
                    
                    Picker("Feedback Type", selection: $feedbackType) {
                        ForEach(FeedbackType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text(descriptionLabel)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.slate)
                    
                    TextEditor(text: $description)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color.lightGray)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.silver, lineWidth: 1)
                        )
                    
                    Text(descriptionPlaceholder)
                        .font(.caption)
                        .foregroundColor(.silver)
                }
                
                // Steps to reproduce (bug only)
                if feedbackType == .bug {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Steps to reproduce (optional)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.slate)
                        
                        TextEditor(text: $stepsToReproduce)
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color.lightGray)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.silver, lineWidth: 1)
                            )
                        
                        Text("1. I tapped on... 2. Then I...")
                            .font(.caption)
                            .foregroundColor(.silver)
                    }
                }
                
                // Screenshot (optional)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Screenshot (optional)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.slate)
                    
                    if let preview = screenshotPreview {
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: preview)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .cornerRadius(8)
                            
                            Button {
                                selectedScreenshot = nil
                                screenshotData = nil
                                screenshotPreview = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .padding(8)
                        }
                    } else {
                        PhotosPicker(selection: $selectedScreenshot, matching: .screenshots) {
                            HStack {
                                Image(systemName: "camera")
                                Text("Add Screenshot")
                            }
                            .font(.subheadline)
                            .foregroundColor(.primaryBlue)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(Color.lightGray)
                            .cornerRadius(8)
                        }
                    }
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.error)
                }
                
                // Submit button
                Button {
                    Task { await submitFeedback() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send Feedback")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(description.isEmpty || isSubmitting)
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thanks! 🙌", isPresented: $showSuccess) {
            Button("Got it") {
                dismiss()
            }
        } message: {
            Text("Your feedback has been sent.")
        }
        .onChange(of: selectedScreenshot) { _, newValue in
            Task {
                if let newValue = newValue,
                   let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    screenshotData = image.jpegData(compressionQuality: 0.7)
                    screenshotPreview = image
                }
            }
        }
    }
    
    private var descriptionLabel: String {
        switch feedbackType {
        case .bug: return "What went wrong?"
        case .feature: return "What would you like to see?"
        case .help: return "What do you need help with?"
        }
    }
    
    private var descriptionPlaceholder: String {
        switch feedbackType {
        case .bug: return "Describe the issue..."
        case .feature: return "Describe your idea..."
        case .help: return "Describe what you need help with..."
        }
    }
    
    private func submitFeedback() async {
        guard let userId = supabase.currentUser?.id else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        // Get username and email
        let username = await fetchUsername()
        let email = supabase.currentUser?.email
        
        // Get device info
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = getDeviceModel()
        
        // Upload screenshot if provided
        var screenshotURL: String? = nil
        if let imageData = screenshotData {
            screenshotURL = await uploadScreenshot(imageData, userId: userId.uuidString)
        }
        
        do {
            struct FeedbackInsert: Encodable {
                let user_id: String
                let type: String
                let description: String
                let steps_to_reproduce: String?
                let app_version: String
                let ios_version: String
                let device_model: String
                let username: String?
                let email: String?
                let screenshot_url: String?
            }
            
            let feedback = FeedbackInsert(
                user_id: userId.uuidString,
                type: feedbackType.rawValue.lowercased(),
                description: description,
                steps_to_reproduce: stepsToReproduce.isEmpty ? nil : stepsToReproduce,
                app_version: appVersion,
                ios_version: iosVersion,
                device_model: deviceModel,
                username: username,
                email: email,
                screenshot_url: screenshotURL
            )
            
            try await supabase.client
                .from("feedback")
                .insert(feedback)
                .execute()
            
            showSuccess = true
            
        } catch {
            print("❌ Error submitting feedback: \(error)")
            errorMessage = "Couldn't send feedback. Try again?"
        }
        
        isSubmitting = false
    }
    
    private func fetchUsername() async -> String? {
        guard let userId = supabase.currentUser?.id else { return nil }
        
        do {
            struct UserRow: Decodable {
                let username: String?
            }
            
            let user: UserRow = try await supabase.client
                .from("users")
                .select("username")
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value
            
            return user.username
        } catch {
            return nil
        }
    }
    
    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let model = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return model
    }
    
    private func uploadScreenshot(_ data: Data, userId: String) async -> String? {
        let fileName = "\(userId)/feedback_\(Date().timeIntervalSince1970).jpg"
        
        do {
            try await supabase.client.storage
                .from("avatars")
                .upload(
                    fileName,
                    data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
            
            let publicURL = try supabase.client.storage
                .from("avatars")
                .getPublicURL(path: fileName)
            
            return publicURL.absoluteString
        } catch {
            print("❌ Error uploading screenshot: \(error)")
            return nil
        }
    }
}

#Preview {
    NavigationStack {
        FeedbackView()
    }
}
