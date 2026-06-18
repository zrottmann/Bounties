#if os(iOS)
import SwiftUI
import BountiesKit

// MARK: - Reviewer feed
//
// Shows bounties in "reviewing" or "disputed" status.
// Reviewer can navigate to any bounty's DisputeView to inspect evidence + resolve.

struct ReviewerFeedView: View {
    let marketplace: any MarketplaceService
    let location: LocationService

    @State private var allBounties: [Bounty] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var reviewQueue: [Bounty] {
        allBounties.filter {
            $0.status == .reviewing || $0.status == .disputed
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading review queue…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if reviewQueue.isEmpty {
                    ContentUnavailableView(
                        "Review Queue Empty",
                        systemImage: "checkmark.shield",
                        description: Text("No bounties are awaiting review.")
                    )
                } else {
                    List(reviewQueue) { bounty in
                        NavigationLink(destination: DisputeView(
                            bounty: bounty,
                            role: .reviewer,
                            marketplace: marketplace
                        )) {
                            ReviewQueueRow(bounty: bounty)
                        }
                    }
                }
            }
            .navigationTitle("Review Queue")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { Task { await load() } }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Fetch all open bounties; reviewer sees reviewing + disputed too.
            allBounties = try await marketplace.listOpenBounties(
                lat: location.coordinate?.latitude,
                lng: location.coordinate?.longitude
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ReviewQueueRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bounty.description).lineLimit(1)
                Spacer()
                StatusBadge(status: bounty.status)
            }
            Text("\(bounty.steps.count) steps · \(FeeMath.formatted(cents: bounty.totalCents))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct StatusBadge: View {
    let status: BountyStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .disputed:  return .red
        case .reviewing: return .orange
        default:         return .secondary
        }
    }
}
#endif
