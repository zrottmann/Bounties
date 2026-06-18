#if os(iOS)
import SwiftUI
import BountiesKit

// MARK: - Per-bounty message thread (holder ↔ hunter ↔ observer)

struct MessageThreadView: View {
    let bounty: Bounty
    let role: AppRole
    let marketplace: any MarketplaceService

    @State private var messages: [BountyMessage] = []
    @State private var draftText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var accountID: String { BackendMarketplaceService.loadOrCreateAccountID() }
    private var serverBountyID: String { bounty.serverID ?? bounty.id.uuidString }

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && messages.isEmpty {
                ProgressView("Loading messages…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if messages.isEmpty {
                ContentUnavailableView(
                    "No Messages Yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start the conversation below.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { msg in
                                MessageBubble(message: msg,
                                              isFromMe: msg.accountID == accountID)
                                    .id(msg.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            if let err = errorMessage {
                Text(err).foregroundColor(.red).font(.caption).padding(.horizontal)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Message…", text: $draftText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Messages")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            messages = try await marketplace.messages(serverBountyID: serverBountyID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftText = ""
        errorMessage = nil
        do {
            let msg = try await marketplace.sendMessage(serverBountyID: serverBountyID,
                                                        accountID: accountID,
                                                        text: text)
            messages.append(msg)
        } catch {
            errorMessage = error.localizedDescription
            draftText = text  // restore on failure
        }
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: BountyMessage
    let isFromMe: Bool

    var body: some View {
        HStack {
            if isFromMe { Spacer(minLength: 40) }
            VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
                Text(message.fromRole.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(message.text)
                    .padding(10)
                    .background(isFromMe ? Color.accentColor : Color(.systemGray5))
                    .foregroundColor(isFromMe ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !isFromMe { Spacer(minLength: 40) }
        }
    }
}
#endif
