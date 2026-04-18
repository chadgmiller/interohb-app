import SwiftUI

/// Overlay that dims the screen and highlights a target rect (heart button) with a cut-out.
/// Shows a helper bubble with actions related to connecting a heart rate device.
struct DeviceCoachMarkOverlay: View {
    /// Frame of the heart button in global coordinates to highlight
    let targetFrame: CGRect
    /// Action to open the device connection sheet
    let onConnect: () -> Void
    /// Action to dismiss the overlay and persist the user's choice
    let onLater: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.frame(in: .global)

            ZStack(alignment: .topLeading) {
                // Dim background with a cutout around the target frame
                spotlightBackground(screen: screen, hole: targetFrame)
                    .ignoresSafeArea()
                    .transition(.opacity)

                // Helper bubble positioned near the heart button (below-left by default)
                helperBubble
                    .frame(maxWidth: 260)
                    .background(AppColors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
                    .padding(.top, max(8, targetFrame.maxY + 8))
                    .padding(.leading, max(8, min(max(16, targetFrame.minX - 180), screen.width - 276)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Creates a dimmed layer with a rounded rectangle hole over the target to create a spotlight effect.
    private func spotlightBackground(screen: CGRect, hole: CGRect) -> some View {
        // Slightly expand the hole for a comfortable halo effect.
        let inset: CGFloat = -8
        let target = hole.insetBy(dx: inset, dy: inset)

        return Canvas { context, size in
            // Fill entire screen with a semi-transparent black color
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black.opacity(0.45)))

            // Cut out the target area using destinationOut blend mode to create the spotlight hole
            var path = Path(roundedRect: target, cornerRadius: 22)
            context.blendMode = .destinationOut
            context.fill(path, with: .color(.black))
        }
        .compositingGroup()
    }

    /// The helper bubble view showing explanatory text and action buttons.
    private var helperBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your heart rate device")
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            Text("Tap the heart icon to Find Devices and connect to a Bluetooth heart rate device.")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)

            HStack(spacing: 12) {
                Button(action: onConnect) {
                    Text("Connect now")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(AppColors.breathTeal)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: onLater) {
                    Text("Later")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(AppColors.cardSurface.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
    }
}

#Preview {
    DeviceCoachMarkOverlay(targetFrame: CGRect(x: 300, y: 50, width: 44, height: 44), onConnect: {}, onLater: {})
}
