import SwiftUI

// Publishes the global frame of the heart button so overlays can point to it.
struct HeartButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // Prefer the most recent non-zero value
        if next != .zero { value = next }
    }
}

struct PulsingHeartButton: View {
    let isStreaming: Bool      // shows filled heart when streaming
    let isConnectedNoSignal: Bool
    let isPulsing: Bool        // whether to animate a subtle pulse
    let onTap: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    init(isStreaming: Bool, isConnectedNoSignal: Bool = false, isPulsing: Bool, onTap: @escaping () -> Void) {
        self.isStreaming = isStreaming
        self.isConnectedNoSignal = isConnectedNoSignal
        self.isPulsing = isPulsing
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            Image(systemName: isStreaming ? "heart.fill" : (isConnectedNoSignal ? "heart.slash" : "heart"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isStreaming ? AppColors.pulseCoral : (isConnectedNoSignal ? AppColors.pulseCoral : AppColors.textMuted))
                .opacity(isStreaming ? 1.0 : 0.85)
                .scaleEffect(pulseScale)
                .frame(width: 44, height: 44) // min tap target
        }
        .buttonStyle(.plain)
        // Publish this view's frame in global coordinates for spotlight positioning
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: HeartButtonFramePreferenceKey.self, value: proxy.frame(in: .global))
            }
        )
        .onAppear {
            updatePulse()
        }
        .onChange(of: isPulsing) { _, _ in
            updatePulse()
        }
        .task(id: isPulsing) {
            await runPulseLoop()
        }
    }

    private func updatePulse() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            pulseScale = 1.0
        }
    }

    private func runPulseLoop() async {
        guard isPulsing else { return }

        while isPulsing && !Task.isCancelled {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.55)) {
                    pulseScale = 1.16
                }
            }

            try? await Task.sleep(for: .milliseconds(550))
            guard isPulsing, !Task.isCancelled else { break }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.55)) {
                    pulseScale = 0.94
                }
            }

            try? await Task.sleep(for: .milliseconds(550))
        }

        await MainActor.run {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                pulseScale = 1.0
            }
        }
    }

}

#Preview {
    PulsingHeartButton(isStreaming: false, isConnectedNoSignal: false, isPulsing: true, onTap: {})
}
