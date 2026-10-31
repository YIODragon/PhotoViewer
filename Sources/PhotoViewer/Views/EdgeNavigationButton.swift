import SwiftUI

/// Large, easy-to-hit navigation button that floats over the left/right edge of
/// the image canvas. Kept separate from the toolbar so culling can be done with
/// the mouse without moving all the way to the title bar.
struct EdgeNavigationButton: View {
    let systemName: String
    let help: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? (isHovering ? 0.95 : 0.62) : 0.16))
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(.black.opacity(isHovering && isEnabled ? 0.48 : 0.22))
                }
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(isEnabled ? 0.14 : 0.04), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
        .scaleEffect(isHovering && isEnabled ? 1.06 : 1)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
