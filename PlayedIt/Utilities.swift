// Utilities.swift
// PlayedIt shared utilities

import Foundation

// MARK: - Debug Logging

/// Use instead of debugLog() to keep logs out of production builds.
/// Usage: debugLog("🔍 Found \(count) results")
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
