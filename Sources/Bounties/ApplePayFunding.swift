#if os(iOS)
import Foundation
import BountiesKit

// Apple Pay is available on devices with the merchant entitlement provisioned.
// When the entitlement is absent (simulator, un-provisioned dev builds) the
// controller refuses to present and canMakePayments returns false — we fall back
// to the simulated path so the app still runs. PassKit is only imported here,
// keeping the rest of the codebase independent of the entitlement.
import PassKit

// MARK: - Merchant / network config

private let kMerchantID = "merchant.com.zrottmann.bounties"
private let kNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

// MARK: - Availability check

/// True when Apple Pay is configured and the device can make payments.
/// Depends on the merchant entitlement AND hardware support.
func applePayAvailable() -> Bool {
    PKPaymentAuthorizationController.canMakePayments(
        usingNetworks: kNetworks,
        capabilities: .threeDSecure
    )
}

// MARK: - Payment presenter

/// Presents the Apple Pay sheet for the given amount. Calls `onToken` with the
/// PKPaymentToken JSON (base64-encoded) on success, or `onCancel` on dismiss /
/// failure / unavailability (caller should fall back to simulated path).
@MainActor
func presentApplePay(
    amountCents: Int,
    onToken: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
) {
    guard applePayAvailable() else {
        // Entitlement or hardware not available — caller will simulate.
        onCancel()
        return
    }

    let item = PKPaymentSummaryItem(
        label: "BountyHunter Job",
        amount: NSDecimalNumber(value: Double(amountCents) / 100.0)
    )
    let req = PKPaymentRequest()
    req.merchantIdentifier = kMerchantID
    req.paymentSummaryItems = [item]
    req.supportedNetworks = kNetworks
    req.merchantCapabilities = .threeDSecure
    req.countryCode = "US"
    req.currencyCode = "USD"

    let controller = PKPaymentAuthorizationController(paymentRequest: req)
    let delegate = ApplePayDelegate(onToken: onToken, onCancel: onCancel)
    controller.delegate = delegate
    // Keep delegate alive until sheet dismisses.
    ApplePayDelegate.activeDelegate = delegate

    controller.present { presented in
        if !presented { onCancel() }
    }
}

// MARK: - PKPaymentAuthorizationControllerDelegate

private final class ApplePayDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {
    // Retain the active delegate so ARC doesn't collect it before the sheet closes.
    nonisolated(unsafe) static var activeDelegate: ApplePayDelegate?

    private let onToken: (String) -> Void
    private let onCancel: () -> Void
    private var didSucceed = false

    init(onToken: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.onToken = onToken
        self.onCancel = onCancel
    }

    func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        // Encode the payment token as base64 to send to the backend.
        let tokenData = payment.token.paymentData
        let b64 = tokenData.base64EncodedString()
        didSucceed = true
        onToken(b64)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { }
        if !self.didSucceed { self.onCancel() }
        ApplePayDelegate.activeDelegate = nil
    }
}
#endif
