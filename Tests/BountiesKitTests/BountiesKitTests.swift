import XCTest
@testable import BountiesKit

/// Unit tests for BountiesKit pure logic.
/// Run with: swift test  (on any host — no simulator required)
final class BountiesKitTests: XCTestCase {

    // MARK: - Fee math: 1% platform fee

    func testAppFeeIsOnePercent() {
        // $10.00 → fee = $0.10 = 10 cents
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 1000), 10)
        // $25.00 → fee = $0.25 = 25 cents
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 2500), 25)
        // $1.00 → fee floors to 1 cent (minimum)
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 100), 1)
    }

    func testHunterPayoutIs99Percent() {
        // $10.00 total → hunter gets $9.90 = 990 cents
        XCTAssertEqual(FeeMath.hunterPayoutCents(totalCents: 1000), 990)
        // $25.00 total → hunter gets $24.75 = 2475 cents
        XCTAssertEqual(FeeMath.hunterPayoutCents(totalCents: 2500), 2475)
    }

    func testFeeAndPayoutSumToTotal() {
        for total in [0, 1, 99, 100, 1000, 2500, 9999, 10000] {
            let fee = FeeMath.appFeeCents(totalCents: total)
            let payout = FeeMath.hunterPayoutCents(totalCents: total)
            XCTAssertEqual(fee + payout, total,
                           "fee + payout must equal total for totalCents=\(total)")
        }
    }

    func testZeroTotalProducesZeroFeeAndPayout() {
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 0), 0)
        XCTAssertEqual(FeeMath.hunterPayoutCents(totalCents: 0), 0)
    }

    func testFeeRoundingFloor() {
        // $0.99 → 1% = 0.0099 cents → floors to 0, but minimum is 1 cent
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 99), 1)
        // $1.01 → 1% = 0.0101 → floor → 0, minimum = 1 cent
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 101), 1)
        // $3.33 → 1% = 0.0333 → floor = 0, minimum = 1 cent
        XCTAssertEqual(FeeMath.appFeeCents(totalCents: 333), 3)
    }

    // MARK: - Step reconciliation (sum must equal target)

    func testReconcileExactSumNoOp() {
        let steps = [
            BountyStep(title: "A", amountCents: 500),
            BountyStep(title: "B", amountCents: 300),
            BountyStep(title: "C", amountCents: 200),
        ]
        let result = FeeMath.reconcile(steps: steps, to: 1000)
        XCTAssertEqual(result.reduce(0) { $0 + $1.amountCents }, 1000)
        XCTAssertEqual(result[2].amountCents, 200) // no change needed
    }

    func testReconcileAddsDeltaToLastStep() {
        // Steps sum to 990, target is 1000 → last step gains 10 cents
        let steps = [
            BountyStep(title: "A", amountCents: 500),
            BountyStep(title: "B", amountCents: 490),
        ]
        let result = FeeMath.reconcile(steps: steps, to: 1000)
        XCTAssertEqual(result.reduce(0) { $0 + $1.amountCents }, 1000)
        XCTAssertEqual(result[1].amountCents, 500) // 490 + 10
    }

    func testReconcileSubtractsDeltaFromLastStep() {
        // Steps sum to 1010, target is 1000 → last step loses 10 cents
        let steps = [
            BountyStep(title: "A", amountCents: 600),
            BountyStep(title: "B", amountCents: 410),
        ]
        let result = FeeMath.reconcile(steps: steps, to: 1000)
        XCTAssertEqual(result.reduce(0) { $0 + $1.amountCents }, 1000)
        XCTAssertEqual(result[1].amountCents, 400) // 410 - 10
    }

    func testReconcileEmptyStepsNoop() {
        let result = FeeMath.reconcile(steps: [], to: 1000)
        XCTAssertTrue(result.isEmpty)
    }

    func testReconcileSingleStep() {
        let steps = [BountyStep(title: "All in one", amountCents: 800)]
        let result = FeeMath.reconcile(steps: steps, to: 1000)
        XCTAssertEqual(result[0].amountCents, 1000)
    }

    // MARK: - Bounty model: derived totals

    func testBountyTotalCentsIsStepSum() {
        var b = Bounty(description: "Test job", holderID: "h1")
        b.steps = [
            BountyStep(title: "Step 1", amountCents: 500),
            BountyStep(title: "Step 2", amountCents: 750),
            BountyStep(title: "Step 3", amountCents: 250),
        ]
        XCTAssertEqual(b.totalCents, 1500)
    }

    func testApprovedAndPendingCents() {
        var b = Bounty(description: "Rake yard", holderID: "h1")
        b.steps = [
            BountyStep(title: "Rake", amountCents: 1000),
            BountyStep(title: "Bag",  amountCents: 500),
            BountyStep(title: "Haul", amountCents: 750),
        ]
        b.steps[0].isApproved = true
        XCTAssertEqual(b.approvedCents, 1000)
        XCTAssertEqual(b.pendingCents, 1250)
    }

    // MARK: - Ledger: approve steps, track earnings

    func testLedgerRecordsApproval() {
        var ledger = BountyLedger()
        let bid = UUID()
        let sid = UUID()
        ledger.recordApproval(bountyID: bid, stepID: sid, amountCents: 800)
        XCTAssertEqual(ledger.earnedCents(for: bid), 800)
        XCTAssertEqual(ledger.totalEarnedCents, 800)
    }

    func testLedgerAccumulatesMultipleApprovals() {
        var ledger = BountyLedger()
        let bid = UUID()
        ledger.recordApproval(bountyID: bid, stepID: UUID(), amountCents: 500)
        ledger.recordApproval(bountyID: bid, stepID: UUID(), amountCents: 750)
        XCTAssertEqual(ledger.earnedCents(for: bid), 1250)
    }

    func testLedgerIsolatesByBounty() {
        var ledger = BountyLedger()
        let bid1 = UUID()
        let bid2 = UUID()
        ledger.recordApproval(bountyID: bid1, stepID: UUID(), amountCents: 1000)
        ledger.recordApproval(bountyID: bid2, stepID: UUID(), amountCents: 300)
        XCTAssertEqual(ledger.earnedCents(for: bid1), 1000)
        XCTAssertEqual(ledger.earnedCents(for: bid2), 300)
        XCTAssertEqual(ledger.totalEarnedCents, 1300)
    }

    func testLedgerStartsEmpty() {
        let ledger = BountyLedger()
        XCTAssertEqual(ledger.totalEarnedCents, 0)
        XCTAssertEqual(ledger.earnedCents(for: UUID()), 0)
    }

    // MARK: - AI service stub

    func testStubBreakdownReturnsSensibleResult() async {
        let svc = StubBountyAIService()
        let result = await svc.breakdown(description: "Rake the leaves", photoContext: nil)
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertGreaterThan(result.suggestedTotalCents, 0)
        XCTAssertFalse(result.steps.isEmpty)
    }

    func testStubStepsSumToSuggestedTotal() async {
        let svc = StubBountyAIService()
        let result = await svc.breakdown(description: "Mow the lawn", photoContext: nil)
        let stepSum = result.steps.reduce(0) { $0 + $1.amountCents }
        XCTAssertEqual(stepSum, result.suggestedTotalCents,
                       "stub step amounts must sum to the suggested total")
    }

    // MARK: - Marketplace stub

    func testStubMarketplaceFullFlow() async throws {
        let svc = StubMarketplaceService()
        XCTAssertFalse(svc.isLive)

        // Post a bounty.
        var bounty = Bounty(description: "Pull weeds in back yard", holderID: "holder-1")
        let step1 = BountyStep(title: "Pull weeds", amountCents: 1500)
        let step2 = BountyStep(title: "Bag and dispose", amountCents: 500)
        bounty.steps = [step1, step2]
        let posted = try await svc.postBounty(bounty)
        XCTAssertEqual(posted.status, .funded)

        // List open bounties — should include our post.
        let open = try await svc.listOpenBounties()
        XCTAssertTrue(open.contains { $0.id == posted.id })

        // Hunter accepts.
        let accepted = try await svc.acceptBounty(id: posted.id, hunterID: "hunter-1")
        XCTAssertEqual(accepted.status, .accepted)
        XCTAssertEqual(accepted.hunterID, "hunter-1")

        // Hunter submits evidence for step 1.
        let evidenced = try await svc.submitEvidence(
            bountyID: posted.id, stepID: step1.id, reference: "photo_ref_abc")
        XCTAssertEqual(evidenced.steps.first?.evidenceReference, "photo_ref_abc")

        // Holder approves step 1.
        let afterApprove1 = try await svc.approveStep(bountyID: posted.id, stepID: step1.id)
        XCTAssertTrue(afterApprove1.steps.first(where: { $0.id == step1.id })!.isApproved)
        XCTAssertEqual(afterApprove1.status, .reviewing)

        // Holder approves step 2 → bounty auto-completes.
        let final = try await svc.approveStep(bountyID: posted.id, stepID: step2.id)
        XCTAssertEqual(final.status, .completed)
        XCTAssertTrue(final.steps.allSatisfy(\.isApproved))
    }

    func testAcceptingNonExistentBountyThrows() async {
        let svc = StubMarketplaceService()
        do {
            _ = try await svc.acceptBounty(id: UUID(), hunterID: "h1")
            XCTFail("Should have thrown")
        } catch MarketplaceError.notFound {
            // expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Formatted display

    func testFormattedCents() {
        XCTAssertEqual(FeeMath.formatted(cents: 0),    "$0.00")
        XCTAssertEqual(FeeMath.formatted(cents: 100),  "$1.00")
        XCTAssertEqual(FeeMath.formatted(cents: 1099), "$10.99")
        XCTAssertEqual(FeeMath.formatted(cents: 2500), "$25.00")
    }
}
