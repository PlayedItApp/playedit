import SwiftUI

struct PSNAuthView: View {
    let onSuccess: (String) -> Void
    let onCancel: () -> Void

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var hasOpenedSafari = false
    @State private var npssoToken = ""
    @State private var step2Unlocked = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        Spacer().frame(height: 16)

                        ZStack {
                            Circle()
                                .fill(Color.primaryBlue.opacity(0.12))
                                .frame(width: 80, height: 80)
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.primaryBlue)
                        }

                        VStack(spacing: 8) {
                            Text("Connect PlayStation")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                            Text("Follow these steps to import your PSN library.")
                                .font(.system(size: 15, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }

                        // Step cards
                        VStack(alignment: .leading, spacing: 12) {
                            stepCard(
                                number: "1",
                                title: "Sign in to PlayStation in Safari",
                                description: "Tap below to open PlayStation.com. If you're already logged in, sign out first, then sign back in. The token only works right after a fresh login.",
                                action: {
                                    Button {
                                        startAuth()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "safari")
                                            Text(hasOpenedSafari ? "Re-open in Safari" : "Open in Safari")
                                        }
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.primaryBlue)
                                        .clipShape(Capsule())
                                    }
                                }
                            )

                            stepCard(
                                number: "2",
                                title: "Set Gaming History to 'Anyone'",
                                description: "In your PlayStation privacy settings, make sure Gaming History is set to Anyone. Otherwise we can't see your library.",
                                action: {
                                    Button {
                                        UIApplication.shared.open(URL(string: "https://id.sonyentertainmentnetwork.com/id/management_ca/")!)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "safari")
                                            Text("Open Privacy Settings")
                                        }
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color.primaryBlue)
                                        .clipShape(Capsule())
                                    }
                                }
                            )

                            stepCard(
                                number: "3",
                                title: "Get your token",
                                description: "After signing in, tap below to open the token page. You'll see a short line of text. Highlight and then copy it.",
                                action: {
                                    Button {
                                        UIApplication.shared.open(URL(string: "https://ca.account.sony.com/api/v1/ssocookie")!)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "safari")
                                            Text("Open token page")
                                        }
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundColor(step2Unlocked ? .white : Color.adaptiveGray)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(step2Unlocked ? Color.primaryBlue : Color.adaptiveSilver.opacity(0.3))
                                        .clipShape(Capsule())
                                    }
                                    .disabled(!step2Unlocked)
                                }
                            )

                            stepCard(
                                number: "4",
                                title: "Paste your token",
                                description: "Come back here and paste. You can paste the full page contents. We'll extract the token automatically.",
                                action: {
                                    VStack(spacing: 8) {
                                        TextField("Paste token here", text: $npssoToken)
                                            .font(.system(size: 14, design: .monospaced))
                                            .padding(10)
                                            .background(Color.cardBackground)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(npssoToken.isEmpty ? Color.primaryBlue.opacity(0.4) : Color.primaryBlue, lineWidth: 1.5)
                                            )
                                            .autocorrectionDisabled()
                                            .textInputAutocapitalization(.never)

                                        if let error = errorMessage {
                                            Text(error)
                                                .font(.system(size: 13, design: .rounded))
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            )
                        }
                        .padding(.horizontal, 20)

                        // Continue button
                        Button {
                            submitToken()
                        } label: {
                            HStack(spacing: 8) {
                                if isAuthenticating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                    Text("Connecting…")
                                } else {
                                    Text("Connect PlayStation")
                                }
                            }
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(npssoToken.count > 10 ? Color.accentOrange : Color.adaptiveSilver)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(npssoToken.count <= 10 || isAuthenticating)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Sign in to PlayStation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    @ViewBuilder
    private func stepCard<A: View>(number: String, title: String, description: String, @ViewBuilder action: () -> A) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.primaryBlue)
                        .frame(width: 26, height: 26)
                    Text(number)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.adaptiveSlate)
            }
            Text(description)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Color.adaptiveGray)
                .fixedSize(horizontal: false, vertical: true)

            action()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private func startAuth() {
        errorMessage = nil
        hasOpenedSafari = true
        step2Unlocked = false
        UIApplication.shared.open(URL(string: "https://www.playstation.com/en-us/")!)
        // Give them 10 seconds to log in before enabling step 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            step2Unlocked = true
        }
    }

    private func submitToken() {
        var cleaned = npssoToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "Please paste your token first."
            return
        }

        // Accept full JSON blob: {"npsso":"abc123..."} or just the raw token
        if cleaned.hasPrefix("{"),
           let data = cleaned.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let npsso = json["npsso"] as? String {
            cleaned = npsso
        }

        guard cleaned.count >= 10 else {
            errorMessage = "That doesn't look like a valid token. Try again."
            return
        }

        isAuthenticating = true
        errorMessage = nil
        onSuccess(cleaned)
    }
}
