// PhotoModerator.swift
// Profile photo moderation using Apple's SensitiveContentAnalysis framework
// Requires iOS 17.0+

import Foundation
import SensitiveContentAnalysis
import UIKit

// MARK: - Photo Moderation Result

struct PhotoModerationResult {
    let allowed: Bool
    let reason: String?
    
    static let ok = PhotoModerationResult(allowed: true, reason: nil)
}

// MARK: - Photo Moderator

final class PhotoModerator {
    
    static let shared = PhotoModerator()
    
    private let analyzer: SCSensitivityAnalyzer
    
    private init() {
        self.analyzer = SCSensitivityAnalyzer()
    }
    
    /// Check if the SensitiveContentAnalysis framework is available and the policy allows analysis
    var isAvailable: Bool {
        // The analyzer's policy determines if analysis can run
        // .disabled means the user/device has turned off Communication Safety
        // In that case, we skip on-device moderation (server-side is the backup)
        return analyzer.analysisPolicy != .disabled
    }
    
    /// Analyze a UIImage for sensitive content before uploading
    /// - Parameter image: The image to check
    /// - Returns: PhotoModerationResult indicating if the image is allowed
    func checkImage(_ image: UIImage) async -> PhotoModerationResult {
        guard isAvailable else {
            // Framework not available or disabled — allow the upload
            // The image is still subject to user reporting
            debugLog("[PhotoModerator] SensitiveContentAnalysis not available, allowing upload")
            return .ok
        }
        
        guard let cgImage = image.cgImage else {
            debugLog("[PhotoModerator] Could not get CGImage, allowing upload")
            return .ok
        }
        
        do {
            let response = try await analyzer.analyzeImage(cgImage)
            
            if response.isSensitive {
                return PhotoModerationResult(
                    allowed: false,
                    reason: "This photo can't be used as a profile picture. Please choose a different image."
                )
            }
            
            return .ok
            
        } catch {
            // If analysis fails for any reason, allow the upload
            // Better to let a photo through than block legitimate uploads
            debugLog("[PhotoModerator] Analysis failed: \(error.localizedDescription), allowing upload")
            return .ok
        }
    }
    
    /// Analyze image data (e.g., from PhotosPicker) for sensitive content
    /// - Parameter data: Raw image data
    /// - Returns: PhotoModerationResult indicating if the image is allowed
    func checkImageData(_ data: Data) async -> PhotoModerationResult {
        guard let image = UIImage(data: data) else {
            debugLog("[PhotoModerator] Could not create UIImage from data, allowing upload")
            return .ok
        }
        
        return await checkImage(image)
    }
}
