#if os(iOS)
import SwiftUI
import BountiesKit

// MARK: - BusyBannerModifier
//
// Attach .busyBanner(message:isPresented:onRetry:) to any view.
// Shows a bottom sheet with the demand message and a Retry button.

struct BusyBannerModifier: ViewModifier {
    let message: String
    @Binding var isPresented: Bool
    let onRetry: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if isPresented {
                    BusyBannerView(message: message, onRetry: onRetry) {
                        isPresented = false
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: isPresented)
                    .padding(.bottom, 16)
                }
            }
    }
}

private struct BusyBannerView: View {
    let message: String
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.orange)
                    .font(.title3)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            if let retry = onRetry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
        .shadow(radius: 8, y: 4)
    }
}

extension View {
    /// Show a friendly high-demand banner. `isPresented` clears on dismiss.
    func busyBanner(
        message: String = MarketplaceError.busyMessage,
        isPresented: Binding<Bool>,
        onRetry: (() -> Void)? = nil
    ) -> some View {
        modifier(BusyBannerModifier(message: message, isPresented: isPresented, onRetry: onRetry))
    }

    /// Convenience: show the banner when `error` is a `.serviceUnavailable`.
    func busyBannerForError(
        _ error: Binding<Error?>,
        onRetry: (() -> Void)? = nil
    ) -> some View {
        let isBusy = Binding<Bool>(
            get: { (error.wrappedValue as? MarketplaceError)?.isBusy == true },
            set: { if !$0 { error.wrappedValue = nil } }
        )
        return busyBanner(isPresented: isBusy, onRetry: onRetry)
    }
}
#endif
