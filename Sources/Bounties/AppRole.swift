#if os(iOS)
import Foundation

/// The role the local user is playing in this session.
/// In v1 this is a simple toggle — the same device can be a holder or a hunter.
/// Real auth and role separation is a future increment.
enum AppRole: String, CaseIterable {
    case holder = "Holder"  // posts and funds bounties
    case hunter = "Hunter"  // accepts and completes bounties
}
#endif
