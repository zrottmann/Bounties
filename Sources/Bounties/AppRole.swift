#if os(iOS)
import Foundation

/// The role the local user is playing in this session.
/// Holder posts and funds bounties; hunter accepts and completes them;
/// reviewer can inspect evidence and resolve disputes.
enum AppRole: String, CaseIterable {
    case holder   = "Holder"    // posts and funds bounties
    case hunter   = "Hunter"    // accepts and completes bounties
    case reviewer = "Reviewer"  // inspects evidence, resolves disputes
}
#endif
