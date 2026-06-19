import Foundation

// MARK: - Surge pricing (inverse-Uber: price RISES to attract hunters)
//
// After posting, a bounty's offered price rises linearly from basePriceCents
// (at t=0) to maxPriceCents (at t=surgeHours). This is the INVERSE of
// rider-surge: here rising price attracts supply (hunters), not demand.
//
// currentOfferCents is computed on-read by linear interpolation of elapsed
// time — no cron job or background task required. Once a hunter accepts, the
// price is frozen (lockedPriceCents) so it never changes after acceptance.
//
// The model is purely additive to the existing step-based total:
//   basePriceCents  — AI-suggested market price shown to the holder
//   maxPriceCents   — holder's ceiling (they're willing to pay up to this)
//   surgeHours      — hours until the offer reaches maxPriceCents
//   postedAt        — when the bounty was posted (used to compute elapsed time)
//   lockedPriceCents — nil while open; set to currentOffer at acceptance
//
// The step amountCents are pro-rated proportionally when the locked price
// differs from the base (future increment; for now steps stay at base splits).

public enum SurgePricing {

    /// Compute the current offered price given elapsed time.
    ///
    /// - Parameters:
    ///   - basePriceCents: The starting price (t = 0).
    ///   - maxPriceCents: The ceiling price (t ≥ surgeHours).
    ///   - surgeHours: Duration over which the price rises.
    ///   - postedAt: When the bounty was posted.
    ///   - now: Current time (defaults to `.now`; injectable for tests).
    /// - Returns: The interpolated offer, clamped to [base, max].
    public static func currentOfferCents(
        basePriceCents: Int,
        maxPriceCents: Int,
        surgeHours: Double,
        postedAt: Date,
        now: Date = .now
    ) -> Int {
        // Guard degenerate cases.
        guard surgeHours > 0, maxPriceCents > basePriceCents else {
            return max(basePriceCents, min(basePriceCents, maxPriceCents))
        }
        let elapsed = max(0, now.timeIntervalSince(postedAt))
        let fraction = min(1.0, elapsed / (surgeHours * 3600))
        let offer = Double(basePriceCents) + fraction * Double(maxPriceCents - basePriceCents)
        // Round to the nearest cent; clamp to [base, max].
        return max(basePriceCents, min(maxPriceCents, Int(offer.rounded())))
    }

    /// True when the bounty is still in the surge window (offer still rising).
    public static func isSurging(surgeHours: Double, postedAt: Date, now: Date = .now) -> Bool {
        guard surgeHours > 0 else { return false }
        return now.timeIntervalSince(postedAt) < surgeHours * 3600
    }

    /// Formatted countdown string, e.g. "Offer rises for 1h 23m".
    public static func countdownLabel(surgeHours: Double, postedAt: Date, now: Date = .now) -> String {
        let remaining = max(0, surgeHours * 3600 - now.timeIntervalSince(postedAt))
        guard remaining > 0 else { return "Max offer reached" }
        let h = Int(remaining / 3600)
        let m = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
        if h > 0 { return "Offer rises for \(h)h \(m)m" }
        return "Offer rises for \(m)m"
    }
}
