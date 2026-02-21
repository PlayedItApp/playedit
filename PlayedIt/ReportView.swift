// ReportView.swift
// User reporting UI for flagging inappropriate content
// Presented as a sheet from comment/profile/feed item context menus

import SwiftUI
import Supabase

// MARK: - Report Types

enum ReportContentType: String, CaseIterable {
    case comment
    case note
    case username
    case profilePhoto = "profile_photo"
    case other
}

enum ReportReason: String, CaseIterable, Identifiable {
    case offensive
    case spam
    case harassment
    case inappropriateImage = "inappropriate_image"
    case other
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .offensive: return "Offensive language"
        case .spam: return "Spam"
        case .harassment: return "Harassment"
        case .inappropriateImage: return "Inappropriate image"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .offensive: return "exclamationmark.bubble"
        case .spam: return "envelope.badge"
        case .harassment: return "hand.raised"
        case .inappropriateImage: return "photo"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - Report View

struct ReportView: View {
    let contentType: ReportContentType
    let contentId: UUID?
    let contentText: String? // snapshot of the content being reported
    let reportedUserId: UUID
    var didSubmit: Binding<Bool>?
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedReason: ReportReason?
    @State private var details: String = ""
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var submitted = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Header
                    Text("What's the issue?")
                        .font(.custom("Nunito-Bold", size: 22))
                        .foregroundColor(Color.adaptiveSlate)
                    
                    // Reason selection
                    VStack(spacing: 8) {
                        ForEach(filteredReasons) { reason in
                            ReportReasonRow(
                                reason: reason,
                                isSelected: selectedReason == reason,
                                onTap: { selectedReason = reason }
                            )
                        }
                    }
                    
                    // Optional details
                    if selectedReason != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Anything else? (optional)")
                                .font(.custom("Nunito-SemiBold", size: 16))
                                .foregroundStyle(Color.adaptiveSlate)
                            
                            TextField("Add details...", text: $details, axis: .vertical)
                                .font(.custom("Nunito-Regular", size: 17))
                                .lineLimit(3...6)
                                .padding(12)
                                .background(Color.secondaryBackground)
                                .cornerRadius(12)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Error message
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.custom("Nunito-Regular", size: 14))
                            .foregroundColor(Color.error)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    
                    // Submit button
                    if submitted {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.success)
                            Text("Thanks for letting us know.")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.adaptiveSlate)
                            Text("We'll look into it.")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color.adaptiveGray)
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
                                Text("Submit Report")
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(selectedReason != nil ? Color.accentOrange : Color.adaptiveSilver)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(selectedReason == nil || isSubmitting)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                            .font(.custom("Nunito-SemiBold", size: 16))
                            .foregroundStyle(Color.adaptiveGray)
                    }
                }
            }
            .padding(20)
            }
        }
    
    // Filter reasons based on content type
    private var filteredReasons: [ReportReason] {
        switch contentType {
        case .profilePhoto:
            return [.inappropriateImage, .offensive, .other]
        case .comment, .note:
            return [.offensive, .spam, .harassment, .other]
        case .username:
            return [.offensive, .spam, .other]
        case .other:
            return ReportReason.allCases
        }
    }
    
    private func submitReport() {
        guard let reason = selectedReason else { return }
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            do {
                struct ReportInsert: Encodable {
                    let reporter_id: String
                    let reported_user_id: String
                    let content_type: String
                    let content_id: String?
                    let content_text: String?
                    let reason: String
                    let details: String?
                }

                let report = ReportInsert(
                    reporter_id: SupabaseManager.shared.currentUser?.id.uuidString ?? "",
                    reported_user_id: reportedUserId.uuidString,
                    content_type: contentType.rawValue,
                    content_id: contentId?.uuidString,
                    content_text: contentText,
                    reason: reason.rawValue,
                    details: details.isEmpty ? nil : details
                )
                
                try await SupabaseManager.shared.client
                    .from("reports")
                    .insert(report)
                    .execute()
                
                await MainActor.run {
                    isSubmitting = false
                    submitted = true
                    didSubmit?.wrappedValue = true
                }
                
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = "Couldn't send report. Try again?"
                }
            }
        }
    }
}

// MARK: - Report Reason Row

struct ReportReasonRow: View {
    let reason: ReportReason
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: reason.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentOrange : Color.adaptiveGray)
                    .frame(width: 24)
                
                Text(reason.displayName)
                    .font(.custom("Nunito-SemiBold", size: 16))
                    .foregroundStyle(Color.adaptiveSlate)
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentOrange : Color.adaptiveSilver)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(isSelected ? Color.accentOrange.opacity(0.08) : Color.secondaryBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Report Button (reusable, for context menus)

struct ReportButton: View {
    let contentType: ReportContentType
    let contentId: UUID?
    let contentText: String?
    let reportedUserId: UUID
    
    @State private var showReportSheet = false
    
    var body: some View {
        Button(role: .destructive) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showReportSheet = true
            }
        } label: {
            Label("Report", systemImage: "flag")
        }
        .background(
                Color.clear
                    .sheet(isPresented: $showReportSheet) {
            ReportView(
                contentType: contentType,
                contentId: contentId,
                contentText: contentText,
                reportedUserId: reportedUserId
            )
            .presentationDetents([.medium, .large])
            }
        )
    }
}
