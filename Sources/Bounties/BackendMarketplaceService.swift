#if os(iOS)
import Foundation
import BountiesKit

// MARK: - Backend marketplace service (bounties-api Appwrite Function)
//
// Calls are routed via the Appwrite Executions API so no client API key is
// needed in the app. Every request is a POST to
//   POST {appwriteEndpoint}/v1/functions/bounties-api/executions
// with body { path, method, body (JSON-stringified), headers }.
// The function returns JSON in responseBody.
//
// Identity: a UUID stored in Keychain under "com.zrottmann.bounties.accountId".

actor BackendMarketplaceService: MarketplaceService {
    nonisolated let isLive: Bool = true

    // Appwrite project details — function is "execute any" so no client key.
    static let appwriteEndpoint = "https://nyc.cloud.appwrite.io/v1"
    static let projectID        = "69e5a408000ff43aa282"
    static let functionID       = "bounties-api"

    // Default base URL; user can override in Settings (stored in UserDefaults).
    static var baseURL: String {
        UserDefaults.standard.string(forKey: "bounties_api_base_url")
            ?? "https://bounties-api.appwrite.network"
    }

    private let accountID: String

    init() {
        self.accountID = BackendMarketplaceService.loadOrCreateAccountID()
    }

    // MARK: - Protocol

    func postBounty(_ bounty: Bounty) async throws -> Bounty {
        let photoB64 = bounty.photoReference  // already base64 from picker
        var body: [String: Any] = [
            "accountId": accountID,
            "title": bounty.description,
            "description": bounty.summary ?? bounty.description,
            "steps": bounty.steps.enumerated().map { i, s in
                ["title": s.title, "amountCents": s.amountCents]
            },
            "basePriceCents": bounty.basePriceCents,
            "maxPriceCents": bounty.maxPriceCents,
            "surgeHours": bounty.surgeHours,
            "postedAt": ISO8601DateFormatter().string(from: bounty.postedAt)
        ]
        if let p = photoB64 { body["photoBase64"] = p }

        let resp = try await call(path: "/post-bounty", bodyFields: body)
        guard let raw = resp["bounty"] as? [String: Any],
              let rawSteps = resp["steps"] as? [[String: Any]] else {
            throw MarketplaceError.notFound
        }
        return try mapBounty(raw, steps: rawSteps, localBounty: bounty)
    }

    func listOpenBounties(lat: Double?, lng: Double?) async throws -> [Bounty] {
        var body: [String: Any] = ["limit": 50]
        if let lat, let lng {
            body["lat"] = lat
            body["lng"] = lng
            body["radiusKm"] = 50.0
        }
        let resp = try await call(path: "/list-open", bodyFields: body)
        guard let raws = resp["bounties"] as? [[String: Any]] else { return [] }
        return raws.compactMap { try? mapBounty($0, steps: nil, localBounty: nil) }
    }

    func acceptBounty(serverID: String, hunterID: String) async throws -> Bounty {
        let resp = try await call(path: "/accept", bodyFields: [
            "accountId": hunterID,
            "bountyId": serverID
        ])
        guard let raw = resp["bounty"] as? [String: Any] else {
            throw MarketplaceError.notFound
        }
        return try mapBounty(raw, steps: nil, localBounty: nil)
    }

    func submitEvidence(serverBountyID: String, stepIdx: Int, base64Photo: String) async throws -> Bounty {
        var body: [String: Any] = [
            "accountId": accountID,
            "bountyId": serverBountyID,
            "stepIdx": stepIdx
        ]
        if !base64Photo.isEmpty { body["photoBase64"] = base64Photo }
        let resp = try await call(path: "/submit-evidence", bodyFields: body)
        // Backend returns { step } not a full bounty — synthesise a minimal one.
        if let rawStep = resp["step"] as? [String: Any] {
            _ = rawStep  // step state updated; caller should refresh from listOpen
        }
        // Re-fetch to get the updated bounty state.
        let bounties = try await listOpenBounties(lat: nil, lng: nil)
        return bounties.first(where: { $0.serverID == serverBountyID })
            ?? Bounty(serverID: serverBountyID, description: "", holderID: "")
    }

    func approveStep(serverBountyID: String, stepIdx: Int, accountID: String) async throws -> Bounty {
        _ = try await call(path: "/approve-step", bodyFields: [
            "accountId": accountID,
            "bountyId": serverBountyID,
            "stepIdx": stepIdx
        ])
        // Re-fetch updated state.
        let bounties = try await listOpenBounties(lat: nil, lng: nil)
        return bounties.first(where: { $0.serverID == serverBountyID })
            ?? Bounty(serverID: serverBountyID, description: "", holderID: "")
    }

    func messages(serverBountyID: String) async throws -> [BountyMessage] {
        let resp = try await call(path: "/messages",
                                  bodyFields: ["bountyId": serverBountyID],
                                  method: "GET")
        guard let raws = resp["messages"] as? [[String: Any]] else { return [] }
        return raws.compactMap(mapMessage)
    }

    func sendMessage(serverBountyID: String, accountID: String, text: String) async throws -> BountyMessage {
        let resp = try await call(path: "/messages", bodyFields: [
            "accountId": accountID,
            "bountyId": serverBountyID,
            "text": text
        ])
        guard let raw = resp["message"] as? [String: Any],
              let msg = mapMessage(raw) else {
            throw MarketplaceError.notFound
        }
        return msg
    }

    func openDispute(serverBountyID: String, stepIdx: Int, accountID: String, reason: String) async throws -> BountyDispute {
        let resp = try await call(path: "/dispute", bodyFields: [
            "accountId": accountID,
            "bountyId": serverBountyID,
            "stepIdx": stepIdx,
            "reason": reason
        ])
        guard let raw = resp["dispute"] as? [String: Any],
              let d = mapDispute(raw) else {
            throw MarketplaceError.notFound
        }
        return d
    }

    // MARK: - Funding (Apple Pay → Stripe or simulated)

    /// POST /fund — sends the Apple Pay token (base64) and amount to the backend.
    /// When `applePayToken` is nil, the backend falls back to simulated funding.
    func fund(bountyID: String, amountCents: Int, applePayToken: String?) async throws {
        var body: [String: Any] = [
            "accountId": accountID,
            "bountyId": bountyID,
            "amountCents": amountCents
        ]
        if let token = applePayToken { body["applePayToken"] = token }
        _ = try await call(path: "/fund", bodyFields: body)
    }

    func resolveDispute(disputeID: String, resolution: String, accountID: String) async throws -> BountyDispute {
        let resp = try await call(path: "/dispute", bodyFields: [
            "accountId": accountID,
            "disputeId": disputeID,
            "resolution": resolution
        ])
        guard let raw = resp["dispute"] as? [String: Any],
              let d = mapDispute(raw) else {
            throw MarketplaceError.notFound
        }
        return d
    }

    // MARK: - HTTP layer (Appwrite Executions API)

    func call(path: String,
              bodyFields: [String: Any],
              method: String = "POST") async throws -> [String: Any] {
        let url = URL(string: "\(Self.appwriteEndpoint)/functions/\(Self.functionID)/executions")!
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.projectID, forHTTPHeaderField: "x-appwrite-project")

        // Appwrite Executions API payload: path + method + body as JSON string.
        let innerBody = (try? String(data: JSONSerialization.data(withJSONObject: bodyFields), encoding: .utf8)) ?? "{}"
        let outer: [String: Any] = ["path": path, "method": method, "body": innerBody]
        req.httpBody = try? JSONSerialization.data(withJSONObject: outer)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch let urlErr as URLError {
            // No network, DNS failure, timeout → friendly busy.
            switch urlErr.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw MarketplaceError.serviceUnavailable(retryAfterHours: 24)
            default:
                throw MarketplaceError.serviceUnavailable(retryAfterHours: 24)
            }
        }

        guard let execution = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseBody = execution["responseBody"] as? String,
              let bodyData = responseBody.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        let statusCode = execution["responseStatusCode"] as? Int ?? 200

        // Detect busy signal from backend ({busy:true} at any 5xx/503 or explicit 503).
        if statusCode == 503 || statusCode == 429 {
            let hours = parsed["retryAfterHours"] as? Int ?? 24
            throw MarketplaceError.serviceUnavailable(retryAfterHours: hours)
        }
        if let busy = parsed["busy"] as? Bool, busy {
            let hours = parsed["retryAfterHours"] as? Int ?? 24
            throw MarketplaceError.serviceUnavailable(retryAfterHours: hours)
        }
        // General 5xx → busy.
        if statusCode >= 500 {
            throw MarketplaceError.serviceUnavailable(retryAfterHours: 24)
        }

        guard statusCode < 400 else {
            let detail = parsed["error"] as? String ?? parsed["message"] as? String ?? "HTTP \(statusCode)"
            throw MarketplaceError.serverError(detail)
        }
        return parsed
    }

    // MARK: - Response mappers

    private func mapBounty(_ raw: [String: Any],
                            steps: [[String: Any]]?,
                            localBounty: Bounty?) throws -> Bounty {
        let serverID = raw["id"] as? String ?? raw["$id"] as? String ?? ""
        let title    = raw["title"] as? String ?? raw["description"] as? String ?? ""
        let holderID = raw["accountId"] as? String ?? localBounty?.holderID ?? ""
        let statusStr = raw["status"] as? String ?? "open"
        let distKm   = raw["distanceKm"] as? Double

        var bounty = localBounty ?? Bounty(description: title, holderID: holderID)
        bounty.serverID = serverID
        if title.isEmpty == false { bounty.description = title }
        bounty.hunterID = raw["hunterId"] as? String
        bounty.photoReference = raw["photoUrl"] as? String
        bounty.status = mapStatus(statusStr)
        bounty.distanceKm = distKm

        // Surge pricing fields from server response.
        if let base = raw["basePriceCents"] as? Int    { bounty.basePriceCents = base }
        if let max  = raw["maxPriceCents"] as? Int     { bounty.maxPriceCents  = max  }
        if let sh   = raw["surgeHours"] as? Double     { bounty.surgeHours     = sh   }
        if let pa   = raw["postedAt"] as? String       { bounty.postedAt       = parseDate(pa) }
        if let lp   = raw["lockedPriceCents"] as? Int  { bounty.lockedPriceCents = lp }
        if let co   = raw["currentOfferCents"] as? Int { bounty.currentOfferCents = co }

        // Map steps from server response or local.
        if let rawSteps = steps, !rawSteps.isEmpty {
            bounty.steps = rawSteps.enumerated().map { idx, rs in
                var step = BountyStep(
                    title: rs["title"] as? String ?? "Step \(idx + 1)",
                    amountCents: rs["amountCents"] as? Int ?? 0
                )
                step.isApproved = rs["approved"] as? Bool ?? false
                step.evidenceReference = rs["evidenceUrl"] as? String
                return step
            }
        }
        return bounty
    }

    private func mapStatus(_ s: String) -> BountyStatus {
        switch s {
        case "open":          return .funded
        case "accepted":      return .accepted
        case "in-progress":   return .inProgress
        case "disputed":      return .disputed
        case "completed":     return .completed
        default:              return .funded
        }
    }

    private func mapMessage(_ raw: [String: Any]) -> BountyMessage? {
        guard let id = raw["id"] as? String ?? raw["$id"] as? String,
              let bountyID = raw["bountyId"] as? String,
              let text = raw["text"] as? String else { return nil }
        return BountyMessage(
            id: id,
            bountyID: bountyID,
            fromRole: raw["fromRole"] as? String ?? "holder",
            accountID: raw["accountId"] as? String ?? "",
            text: text,
            createdAt: parseDate(raw["createdAt"] as? String)
        )
    }

    private func mapDispute(_ raw: [String: Any]) -> BountyDispute? {
        guard let id = raw["id"] as? String ?? raw["$id"] as? String else { return nil }
        return BountyDispute(
            id: id,
            bountyID: raw["bountyId"] as? String ?? "",
            stepIdx: raw["stepIdx"] as? Int ?? 0,
            openedBy: raw["openedBy"] as? String ?? "",
            reason: raw["reason"] as? String ?? "",
            state: raw["state"] as? String ?? "open",
            resolution: raw["resolution"] as? String
        )
    }

    private func parseDate(_ str: String?) -> Date {
        guard let str else { return .now }
        let fmt = ISO8601DateFormatter()
        return fmt.date(from: str) ?? .now
    }

    // MARK: - Anonymous account ID (Keychain-persisted)

    static func loadOrCreateAccountID() -> String {
        let key = "com.zrottmann.bounties.accountId"
        // UserDefaults is fine for an anonymous ID (not a credential).
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let new = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(32).description
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}

// MARK: - Errors

extension MarketplaceError {
    static func serverError(_ message: String) -> MarketplaceError { .backendError(message) }
}
#endif
