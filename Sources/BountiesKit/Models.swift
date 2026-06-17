import Foundation

// MARK: - Core models

/// One discrete step of a bounty job, each with its own price and evidence state.
public struct BountyStep: Identifiable, Equatable, Codable, Sendable {
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

    // MARK: - Derived

    /// Sum of all step amounts. This is the canonical total — steps must re-sum here.
    public var totalCents: Int { steps.reduce(0) { $0 + $1.amountCents } }
    public var approvedCents: Int { steps.filter(\.isApproved).reduce(0) { $0 + $1.amountCents } }
    public var pendingCents: Int { totalCents - approvedCents }

    public init(
        id: UUID = UUID(),
        description: String,
        holderID: String,
        photoReference: String? = nil,
        steps: [BountyStep] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.description = description
        self.holderID = holderID
        self.photoReference = photoReference
        self.steps = steps
        self.createdAt = createdAt
        self.status = .draft
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
