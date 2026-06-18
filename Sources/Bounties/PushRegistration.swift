#if os(iOS)
import Foundation
import UIKit
import UserNotifications
import BountiesKit

// MARK: - Push notification registration
//
// Requests authorization and registers with APNs.
// On success, the device token is sent to the backend via /register-push.
// The APNs certificate/key is owner-pending (not compiled in) — registration
// completes locally; server push delivery is gated on the owner adding the key.

enum PushRegistration {
    static func requestAndRegister(marketplace: any MarketplaceService,
                                   accountID: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
        } catch {
            return
        }
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        // The token arrives in AppDelegate.didRegisterForRemoteNotifications.
        // We store it and forward it to the backend from there.
    }

    /// Called from AppDelegate (or SwiftUI .onReceive) with the raw token data.
    static func sendToken(_ tokenData: Data, marketplace: any MarketplaceService,
                          accountID: String) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            do {
                try await (marketplace as? BackendMarketplaceService)?
                    .registerPush(token: token, accountID: accountID)
            } catch {
                // Non-fatal — push will retry on next launch.
            }
        }
    }
}

// Extend BackendMarketplaceService with the push registration call.
extension BackendMarketplaceService {
    func registerPush(token: String, accountID: String) async throws {
        _ = try await call(path: "/register-push", bodyFields: [
            "accountId": accountID,
            "token": token,
            "platform": "ios"
        ])
    }
}
#endif
