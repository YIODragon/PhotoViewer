import PhotoViewerCore
import SwiftUI

/// Slim bottom handle shown while the filmstrip is collapsed.
struct CollapsedFilmstripBar: View {
    @Bindable var model: BrowserViewModel

    var body: some View {
        Button {
            model.toggleFilmstrip()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)

                Text("胶片条")
                    .font(.system(size: 10, weight: .medium))

                Text("\(model.shots.count)")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Text("展开")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .help("展开胶片条（T）")
    }
}
