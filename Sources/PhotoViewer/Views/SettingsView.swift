import SwiftUI

struct SettingsView: View {
    @AppStorage("autoAdvanceAfterRating") private var autoAdvance = true

    var body: some View {
        Form {
            Toggle("评分或标记后自动显示下一张", isOn: $autoAdvance)

            Text("关闭后，按 1–5、P、X 会停留在当前照片，方便连续调整星级或旗标。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(12)
    }
}
