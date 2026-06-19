import Foundation

// MARK: - Core models

/// One discrete step of a bounty job, each with its own price and evidence state.
public struct BountyStep: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: UUID
    /// Human-readable title, e.g. "Rake leaves into piles".
    public var title: String
    /// Agreed price for this step in US cents.
    public var amountCents: Int
    /// Evidence photo submitted by the hunter (base-64 JPEG or URL).
    public var evidenceReference: String?
    /// Whether the holder (or a reviewer) has approved this step's evidence.
    public var isApproved: Bool

    public init(id: UUID = UUID(), title: String, amountCents: Int) {
        self.id = id
        self.title = title
        self.amountCents = amountCents
        self.evidenceReference = nil
        self.isApproved = false
    }
}

/// The state a bounty moves through over its lifetime.
public enum BountyStatus: String, Codable, Equatable, Sendable {
    case draft        // holder is still editing
    case funded       // Apple Pay succeeded; visible to hunters
    case accepted     // a hunter claimed it
    case inProgress   // hunter is completing steps
    case reviewing    // all steps submitted; holder reviewing
    case completed    // all steps approved; bounty closed
    case disputed     // holder or hunter opened a dispute
}

/// A posted household chore job.
public struct Bounty: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    /// Server-assigned document ID (e.g. "bnty_abc123"). Set after the backend
    /// creates the record; nil for locally-created drafts that haven't been posted yet.
    public var serverID: String?
    /// Short description typed by the holder, e.g. "Rake my front yard".
    public var description: String
    /// AI-produced one-sentence summary (set after the AI call).
    public var summary: String?
    /// Photo taken/picked by the holder (base-64 JPEG or URL).
    public var photoReference: String?
    /// The breakdown of work produced by the AI.
    public var steps: [BountyStep]
    /// ISO-8601 timestamp of creation.
    public var createdAt: Date
    public var status: BountyStatus
    /// Device/user ID of the holder who posted the bounty.
    public var holderID: String
    /// Device/user ID of the hunter who accepted the bounty (nil when open).
    public var hunterID: String?
    /// Approximate distance from the hunter (km). Set by backend on /list-open.
    public var distanceKm: Double?

    // MARK: - Surge pricing fields

    /// AI-suggested market base price (cents). Offer starts here at t=0.
    public var basePriceCents: Int
    /// Holder's maximum offer ceiling (cents). Offer reaches this at t=surgeHours.
    public var maxPriceCents: Int
    /// Hours over which the offer rises from base to max.
    public var surgeHours: Double
    /// When the bounty was posted (for elapsed-time interpolation).
    public var postedAt: Date
    /// Set at acceptance to freeze the price. Nil while the bounty is open.
    public var lockedPriceCents: Int?
    /// Current interpolated offer from the server (set by /list-open or /detail).
    /// If nil, compute locally with SurgePricing.currentOfferCents.
    public var currentOfferCents: Int?

    // MARK: - Derived

    /// Sum of all step amounts. This is the canonical total — steps must re-sum here.
    public var totalCents: Int { steps.reduce(0) { $0 + $1.amountCents } }
    public var approvedCents: Int { steps.filter(\.isApproved).reduce(0) { $0 + $1.amountCents } }
    public var pendingCents: Int { totalCents - approvedCents }

    /// The price to show right now: locked > server-provided > locally interpolated.
    public var displayOfferCents: Int {
        if let locked = lockedPriceCents { return locked }
        if let current = currentOfferCents { return current }
        return SurgePricing.currentOfferCents(
            basePriceCents: basePriceCents,
            maxPriceCents: maxPriceCents,
            surgeHours: surgeHours,
            postedAt: postedAt
        )
    }

    public init(
        id: UUID = UUID(),
        serverID: String? = nil,
        description: String,
        holderID: String,
        photoReference: String? = nil,
        steps: [BountyStep] = [],
        createdAt: Date = .now,
        basePriceCents: Int = 0,
        maxPriceCents: Int = 0,
        surgeHours: Double = 2.0,
        postedAt: Date = .now
    ) {
        self.id = id
        self.serverID = serverID
        self.description = description
        self.holderID = holderID
        self.photoReference = photoReference
        self.steps = steps
        self.createdAt = createdAt
        self.status = .draft
        self.distanceKm = nil
        self.basePriceCents = basePriceCents
        self.maxPriceCents = maxPriceCents
        self.surgeHours = surgeHours
        self.postedAt = postedAt
        self.lockedPriceCents = nil
        self.currentOfferCents = nil
    }
}

// MARK: - Message

/// A chat message on a per-bounty thread (holder ↔ hunter ↔ observer).
public struct BountyMessage: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var bountyID: String
    public var fromRole: String   // "holder" | "hunter" | "observer"
    public var accountID: String
    public var text: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, bountyID: String, fromRole: String,
                accountID: String, text: String, createdAt: Date = .now) {
        self.id = id
        self.bountyID = bountyID
        self.fromRole = fromRole
        self.accountID = accountID
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - Dispute

public struct BountyDispute: Identifiable, Equatable, Codable, Sendable {
    public var id: String
    public var bountyID: String
    public var stepIdx: Int
    public var openedBy: String
    public var reason: String
    public var state: String       // "open" | "resolved"
    public var resolution: String?

    public init(id: String = UUID().uuidString, bountyID: String, stepIdx: Int,
                openedBy: String, reason: String, state: String = "open",
                resolution: String? = nil) {
        self.id = id
        self.bountyID = bountyID
        self.stepIdx = stepIdx
        self.openedBy = openedBy
        self.reason = reason
        self.state = state
        self.resolution = resolution
    }
}

// MARK: - Ledger

/// A credit entry recording a release or deduction against a bounty.
public struct LedgerEntry: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var bountyID: UUID
    public var stepID: UUID
    public var amountCents: Int
    public var note: String
    public var recordedAt: Date

    public init(bountyID: UUID, stepID: UUID, amountCents: Int, note: String, recordedAt: Date = .now) {
        self.id = UUID()
        self.bountyID = bountyID
        self.stepID = stepID
        self.amountCents = amountCents
        self.note = note
        self.recordedAt = recordedAt
    }
}

/// Tracks hunter earnings (step approvals) per bounty. Real bank payouts are
/// an explicit future increment — this ledger records what is owed.
public struct BountyLedger: Sendable {
    private(set) public var entries: [LedgerEntry] = []

    public init() {}

    /// Record a step approval, crediting `amountCents` to the hunter.
    public mutating func recordApproval(bountyID: UUID, stepID: UUID, amountCents: Int) {
        let entry = LedgerEntry(bountyID: bountyID, stepID: stepID,
                                amountCents: amountCents, note: "step approved")
        entries.append(entry)
    }

    /// Total credited to the hunter across all approved steps for a bounty.
    public func earnedCents(for bountyID: UUID) -> Int {
        entries.filter { $0.bountyID == bountyID }.reduce(0) { $0 + $1.amountCents }
    }

    /// Total earned across all bounties (gross, before payout).
    public var totalEarnedCents: Int { entries.reduce(0) { $0 + $1.amountCents } }
}
