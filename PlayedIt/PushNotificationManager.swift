import UIKit
import UserNotifications
import Supabase

class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationManager()
    
    func requestPermissionAndRegister() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            debugLog("🔔 Push permission granted: \(granted)")
            if granted {
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    func saveDeviceToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        debugLog("🔔 Device token: \(token)")
        
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("device_tokens")
                    .upsert([
                        "user_id": userId.uuidString,
                        "token": token,
                        "platform": "ios",
                        "updated_at": ISO8601DateFormatter().string(from: Date())
                    ], onConflict: "user_id,token")
                    .execute()
                debugLog("🔔 Device token saved to Supabase")
            } catch {
                debugLog("❌ Error saving device token: \(error)")
            }
        }
    }
    
    func removeDeviceToken() {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        Task {
            do {
                try await SupabaseManager.shared.client
                    .from("device_tokens")
                    .delete()
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                debugLog("🔔 Device tokens removed")
            } catch {
                debugLog("❌ Error removing device token: \(error)")
            }
        }
    }
    
    // Show banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        debugLog("🔔 Notification tapped: \(userInfo)")
        completionHandler()
    }
}
