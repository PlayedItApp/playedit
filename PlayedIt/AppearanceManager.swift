import Foundation
import SwiftUI
import Combine
import Auth
import Supabase

class AppearanceManager: ObservableObject {
    @Published var appearanceMode: Int {
        didSet {
            UserDefaults.standard.set(appearanceMode, forKey: "appearanceMode")
            Task { await syncToSupabase() }
        }
    }
    
    init() {
        self.appearanceMode = UserDefaults.standard.integer(forKey: "appearanceMode")
    }
    
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
    
    private func syncToSupabase() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        let modeString: String
        switch appearanceMode {
        case 1: modeString = "light"
        case 2: modeString = "dark"
        default: modeString = "system"
        }
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .update(["appearance_mode": modeString])
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            print("⚠️ Failed to sync appearance mode: \(error)")
        }
    }
    
    func syncResolvedAppearance(colorScheme: ColorScheme) async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        let resolved = appearanceMode == 0 ? (colorScheme == .dark ? "system_dark" : "system_light") : (appearanceMode == 2 ? "dark" : "light")
        do {
            try await SupabaseManager.shared.client
                .from("users")
                .update(["appearance_mode": resolved])
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            print("⚠️ Failed to sync resolved appearance: \(error)")
        }
    }
}
