// ReportGameDataView.swift

import SwiftUI
import Supabase

enum GameDataIssueType: String, CaseIterable, Identifiable {
    case description
    case genres
    case tags
    case platforms
    case releaseYear = "release_year"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .description: return "Description"
        case .genres: return "Genres"
        case .tags: return "Tags"
        case .platforms: return "Platforms"
        case .releaseYear: return "Release Year"
        }
    }
    
    var icon: String {
        switch self {
        case .description: return "text.alignleft"
        case .genres: return "tag"
        case .tags: return "number"
        case .platforms: return "gamecontroller"
        case .releaseYear: return "calendar"
        }
    }
}

struct ReportGameDataView: View {
    let gameId: Int
    let rawgId: Int
    let gameTitle: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIssues: Set<GameDataIssueType> = []
    @State private var details: String = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    Text("What looks wrong?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.adaptiveSlate)
                    
                    Text("We'll review and fix \(gameTitle)'s info.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                    
                    // Issue type checkboxes
                    VStack(spacing: 8) {
                        ForEach(GameDataIssueType.allCases) { issue in
                            Button {
                                if selectedIssues.contains(issue) {
                                    selectedIssues.remove(issue)
                                } else {
                                    selectedIssues.insert(issue)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: issue.icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(selectedIssues.contains(issue) ? Color.accentOrange : Color.adaptiveGray)
                                        .frame(width: 24)
                                    
                                    Text(issue.displayName)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.adaptiveSlate)
                                    
                                    Spacer()
                                    
                                    Image(systemName: selectedIssues.contains(issue) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIssues.contains(issue) ? Color.accentOrange : Color.adaptiveSilver)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(selectedIssues.contains(issue) ? Color.accentOrange.opacity(0.08) : Color.secondaryBackground)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Optional details
                    if !selectedIssues.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's wrong? (optional)")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            TextField("e.g. \"This is actually a PS2 game, not PS3\"", text: $details, axis: .vertical)
                                .font(.system(size: 15, design: .rounded))
                                .lineLimit(3...6)
                                .padding(12)
                                .background(Color.secondaryBackground)
                                .cornerRadius(12)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, design: .rounded))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                    }
                    
                    if submitted {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            Text("Thanks! We'll take a look.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        Button(action: submitReport) {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Submit")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(!selectedIssues.isEmpty ? Color.accentOrange : Color.adaptiveSilver)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(selectedIssues.isEmpty || isSubmitting)
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.adaptiveGray)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedIssues)
            }
            .presentationBackground(Color.appBackground)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    
    private func submitReport() {
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                guard let userId = SupabaseManager.shared.currentUser?.id else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Not logged in"])
                }
                
                struct GameDataReportInsert: Encodable {
                    let reporter_id: String
                    let game_id: Int
                    let rawg_id: Int
                    let game_title: String
                    let issue_types: [String]
                    let details: String?
                }
                
                let report = GameDataReportInsert(
                    reporter_id: userId.uuidString.lowercased(),
                    game_id: gameId,
                    rawg_id: rawgId,
                    game_title: gameTitle,
                    issue_types: selectedIssues.map(\.rawValue),
                    details: details.isEmpty ? nil : details
                )
                
                try await SupabaseManager.shared.client
                    .from("game_data_reports")
                    .insert(report)
                    .execute()
                
                await MainActor.run {
                    isSubmitting = false
                    submitted = true
                }
                
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { dismiss() }
                
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Couldn't send report. Try again?"
                }
            }
        }
    }
}
