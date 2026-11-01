import PhotoViewerCore
import SwiftUI

/// Thin bottom handle shown while the filmstrip is collapsed. Kept text-free,
/// matching Lightroom's small disclosure arrow.
struct CollapsedFilmstripBar: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        Button {
            model.toggleFilmstrip()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: 20)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .help("展开胶片条（T）")
    }
}
