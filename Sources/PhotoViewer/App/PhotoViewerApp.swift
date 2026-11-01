import SwiftUI

@main
struct PhotoViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState.shared

    var body: some Scene {
        Window("PhotoViewer", id: "main") {
            ContentView(model: appState.browser)
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    KeyboardManager.shared.install()
                    appState.browser.consumeOpenRequests()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("撤销删除") {
                    appState.browser.undoLastDeletion()
                }
                .keyboardShortcut("z", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("打开图片…") {
                    appState.browser.openPanelForImage()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("打开文件夹…") {
                    appState.browser.openPanelForFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("图片") {
                Button("上一张") {
                    appState.browser.goPrevious()
                }

                Button("下一张") {
                    appState.browser.goNext()
                }

                Divider()

                Button("切换 RAW / JPEG") {
                    appState.browser.toggleDisplayFormat()
                }
                .keyboardShortcut("j", modifiers: [])

                Divider()

                Button("删除当前图片（整张）") {
                    appState.browser.requestDelete()
                }

                Divider()

                Button("全屏") {
                    appState.toggleFullScreen()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }

            CommandMenu("显示") {
                Button("网格视图") {
                    appState.browser.toggleGridView()
                }
                .keyboardShortcut("g", modifiers: [])

                Button("单张视图") {
                    appState.browser.showLoupe()
                }
                .keyboardShortcut("e", modifiers: [])

                Button("对比视图") {
                    appState.browser.toggleCompare()
                }
                .keyboardShortcut("c", modifiers: [])

                Button("Survey 4-up") {
                    appState.browser.toggleSurvey()
                }
                .keyboardShortcut("n", modifiers: [])

                Button("折叠/展开胶片条") {
                    appState.browser.toggleFilmstrip()
                }
                .keyboardShortcut("t", modifiers: [])

                Divider()

                Button("放大") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("缩小") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button("适应窗口") {
                    NotificationCenter.default.post(name: .zoomFit, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("原始比例（100%）") {
                    NotificationCenter.default.post(name: .zoomActualSize, object: nil)
                }
                .keyboardShortcut("1", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
