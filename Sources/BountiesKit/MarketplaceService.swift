import Foundation

// MARK: - Marketplace service protocol

/// The network seam for all marketplace operations.
/// The live backend (Appwrite) is a future increment; the stub below
/// keeps everything demoable with no server.
public protocol MarketplaceService: Sendable {
    /// Whether a real backend is wired up. False → demo / stub mode.
    var isLive: Bool { get }

    /// Publish a funded bounty so hunters can see it.
    func postBounty(_ bounty: Bounty) async throws -> Bounty

    /// Return open (funded, not yet accepted) bounties near the hunter.
    func listOpenBounties() async throws -> [Bounty]

    /// A hunter claims an open bounty.
    func acceptBounty(id: UUID, hunterID: String) async throws -> Bounty

    /// Hunter submits a photo for a step (base-64 JPEG or URL reference).
    func submitEvidence(bountyID: UUID, stepID: UUID, reference: String) async throws -> Bounty

    /// Holder (or reviewer) approves a step's evidence, releasing that portion.
    func approveStep(bountyID: UUID, stepID: UUID) async throws -> Bounty
}

// MARK: - Stub

/// In-memory fake marketplace. Bounties persist only for the session.
public actor StubMarketplaceService: MarketplaceService {
    public nonisolated let isLive: Bool = false

    private var store: [UUID: Bounty] = [:]

    public init() {}

    public func postBounty(_ bounty: Bounty) async throws -> Bounty {
        var b = bounty
        b.status = .funded
        store[b.id] = b
        return b
    }

    public func listOpenBounties() async throws -> [Bounty] {
        store.values.filter { $0.status == .funded }
                    .sorted { $0.createdAt < $1.createdAt }
    }

    public func acceptBounty(id: UUID, hunterID: String) async throws -> Bounty {
        guard var b = store[id], b.status == .funded else {
            throw MarketplaceError.notFound
        }
        b.hunterID = hunterID
        b.status = .accepted
        store[id] = b
        return b
    }

    public func submitEvidence(bountyID: UUID, stepID: UUID, reference: String) async throws -> Bounty {
        guard var b = store[bountyID] else { throw MarketplaceError.notFound }
        guard let idx = b.steps.firstIndex(where: { $0.id == stepID }) else {
            throw MarketplaceError.stepNotFound
        }
        b.steps[idx].evidenceReference = reference
        b.status = .inProgress
        store[bountyID] = b
        return b
    }

    public func approveStep(bountyID: UUID, stepID: UUID) async throws -> Bounty {
        guard var b = store[bountyID] else { throw MarketplaceError.notFound }
        guard let idx = b.steps.firstIndex(where: { $0.id == stepID }) else {
            throw MarketplaceError.stepNotFound
        }
        b.steps[idx].isApproved = true
        // Auto-complete when all steps approved.
        if b.steps.allSatisfy(\.isApproved) {
            b.status = .completed
        } else {
            b.status = .reviewing
        }
        store[bountyID] = b
        return b
    }
}

// MARK: - Errors

public enum MarketplaceError: LocalizedError {
    case notFound
    case stepNotFound
    case alreadyAccepted

    public var errorDescription: String? {
        switch self {
        case .notFound:       return "Bounty not found."
        case .stepNotFound:   return "Step not found on that bounty."
        case .alreadyAccepted: return "Bounty has already been accepted."
        }
    }
}
