import Foundation

// MARK: - Marketplace service protocol

/// The network seam for all marketplace operations.
/// The live `BackendMarketplaceService` (Appwrite) is injected at runtime;
/// the stub below keeps everything demoable with no server.
public protocol MarketplaceService: Sendable {
    /// Whether a real backend is wired up. False → demo / stub mode.
    var isLive: Bool { get }

    /// Publish a funded bounty so hunters can see it.
    func postBounty(_ bounty: Bounty) async throws -> Bounty

    /// Return open (funded, not yet accepted) bounties.
    /// Pass lat/lng to get nearest-first ordering from the backend.
    func listOpenBounties(lat: Double?, lng: Double?) async throws -> [Bounty]

    /// A hunter claims an open bounty.
    func acceptBounty(serverID: String, hunterID: String) async throws -> Bounty

    /// Hunter submits a photo for a step (base-64 JPEG).
    func submitEvidence(serverBountyID: String, stepIdx: Int, base64Photo: String) async throws -> Bounty

    /// Holder (or reviewer) approves a step's evidence, releasing that portion.
    func approveStep(serverBountyID: String, stepIdx: Int, accountID: String) async throws -> Bounty

    /// Fetch the message thread for a bounty.
    func messages(serverBountyID: String) async throws -> [BountyMessage]

    /// Post a new message to the thread.
    func sendMessage(serverBountyID: String, accountID: String, text: String) async throws -> BountyMessage

    /// Open a dispute on a step.
    func openDispute(serverBountyID: String, stepIdx: Int, accountID: String, reason: String) async throws -> BountyDispute

    /// Resolve an open dispute.
    func resolveDispute(disputeID: String, resolution: String, accountID: String) async throws -> BountyDispute
}

// MARK: - Stub

/// In-memory fake marketplace. Bounties persist only for the session.
public actor StubMarketplaceService: MarketplaceService {
    public nonisolated let isLive: Bool = false

    private var store: [UUID: Bounty] = [:]
    private var messages: [String: [BountyMessage]] = [:]

    public init() {}

    public func postBounty(_ bounty: Bounty) async throws -> Bounty {
        var b = bounty
        b.status = .funded
        b.serverID = "stub-\(b.id.uuidString.prefix(8))"
        store[b.id] = b
        return b
    }

    public func listOpenBounties(lat: Double?, lng: Double?) async throws -> [Bounty] {
        store.values.filter { $0.status == .funded }
                    .sorted { $0.createdAt < $1.createdAt }
    }

    public func acceptBounty(serverID: String, hunterID: String) async throws -> Bounty {
        guard var entry = store.values.first(where: { $0.serverID == serverID }),
              entry.status == .funded else {
            throw MarketplaceError.notFound
        }
        entry.hunterID = hunterID
        entry.status = .accepted
        store[entry.id] = entry
        return entry
    }

    public func submitEvidence(serverBountyID: String, stepIdx: Int, base64Photo: String) async throws -> Bounty {
        guard var b = store.values.first(where: { $0.serverID == serverBountyID }) else {
            throw MarketplaceError.notFound
        }
        guard stepIdx < b.steps.count else { throw MarketplaceError.stepNotFound }
        b.steps[stepIdx].evidenceReference = base64Photo
        b.status = .inProgress
        store[b.id] = b
        return b
    }

    public func approveStep(serverBountyID: String, stepIdx: Int, accountID: String) async throws -> Bounty {
        guard var b = store.values.first(where: { $0.serverID == serverBountyID }) else {
            throw MarketplaceError.notFound
        }
        guard stepIdx < b.steps.count else { throw MarketplaceError.stepNotFound }
        b.steps[stepIdx].isApproved = true
        if b.steps.allSatisfy(\.isApproved) {
            b.status = .completed
        } else {
            b.status = .reviewing
        }
        store[b.id] = b
        return b
    }

    public func messages(serverBountyID: String) async throws -> [BountyMessage] {
        messages[serverBountyID] ?? []
    }

    public func sendMessage(serverBountyID: String, accountID: String, text: String) async throws -> BountyMessage {
        let msg = BountyMessage(bountyID: serverBountyID, fromRole: "holder",
                                accountID: accountID, text: text)
        messages[serverBountyID, default: []].append(msg)
        return msg
    }

    public func openDispute(serverBountyID: String, stepIdx: Int, accountID: String, reason: String) async throws -> BountyDispute {
        BountyDispute(bountyID: serverBountyID, stepIdx: stepIdx, openedBy: accountID, reason: reason)
    }

    public func resolveDispute(disputeID: String, resolution: String, accountID: String) async throws -> BountyDispute {
        BountyDispute(id: disputeID, bountyID: "unknown", stepIdx: 0,
                      openedBy: accountID, reason: "", state: "resolved", resolution: resolution)
    }
}

// MARK: - Errors

public enum MarketplaceError: LocalizedError {
    case notFound
    case stepNotFound
    case alreadyAccepted
    case backendError(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:             return "Bounty not found."
        case .stepNotFound:         return "Step not found on that bounty."
        case .alreadyAccepted:      return "Bounty has already been accepted."
        case .backendError(let m):  return "Backend error: \(m)"
        }
    }
}
