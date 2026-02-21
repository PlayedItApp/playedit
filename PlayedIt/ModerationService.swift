// ModerationService.swift
// Server-side moderation calls via Supabase Edge Function
// This is the enforced gate — client-side is just for instant feedback

import Foundation

// MARK: - Server Moderation Response

private struct ServerModerationResponse: Codable {
    let allowed: Bool
    let reason: String?
}

// MARK: - Moderation Service

final class ModerationService {
    
    static let shared = ModerationService()
    
    // IMPORTANT: Replace with your actual Supabase URL
    // This should match the supabaseURL you already use in SupabaseManager
    private let edgeFunctionURL: String
    
    private init() {
        self.edgeFunctionURL = "\(Config.supabaseURL)/functions/v1/moderate-text"
    }
    
    // MARK: - Server-Side Text Check
    
    /// Validate text server-side before persisting to database
    /// Returns true if allowed, false if blocked
    /// On network failure, falls back to allowing (client-side already checked)
    func validateText(_ text: String, context: TextContext) async -> ModerationResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .ok
        }
        
        do {
            var request = URLRequest(url: URL(string: edgeFunctionURL)!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(Config.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            
            let body: [String: String] = [
                "text": text,
                "context": context.rawValue
            ]
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Server error — fall back to allowing (client-side already filtered)
                debugLog("[ModerationService] Server returned non-200, falling back to allow")
                return .ok
            }
            
            let serverResponse = try JSONDecoder().decode(ServerModerationResponse.self, from: data)
            
            return ModerationResult(
                allowed: serverResponse.allowed,
                reason: serverResponse.reason
            )
            
        } catch {
            // Network error — fall back to allowing (client-side already filtered)
            debugLog("[ModerationService] Network error: \(error.localizedDescription), falling back to allow")
            return .ok
        }
    }
    
    // MARK: - Convenience Methods
    
    /// Full moderation check: client-side first (instant), then server-side (enforced)
    /// Use this as the single entry point for all text moderation
    func moderateUsername(_ username: String) async -> ModerationResult {
        // 1. Client-side check (instant feedback)
        let clientResult = ContentModerator.shared.checkUsername(username)
        if !clientResult.allowed {
            return clientResult
        }
        
        // 2. Server-side check (enforced gate)
        return await validateText(username, context: .username)
    }
    
    func moderateComment(_ text: String) async -> ModerationResult {
        let clientResult = ContentModerator.shared.checkText(text)
        if !clientResult.allowed {
            return clientResult
        }
        
        return await validateText(text, context: .comment)
    }
    
    func moderateGameNote(_ text: String) async -> ModerationResult {
        let clientResult = ContentModerator.shared.checkText(text)
        if !clientResult.allowed {
            return clientResult
        }
        
        return await validateText(text, context: .note)
    }
}

// MARK: - Text Context

enum TextContext: String {
    case username
    case comment
    case note
}
