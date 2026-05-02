import SwiftUI

@main
struct MusicMakerAIApp: App {
    @StateObject private var viewModel = MusicGeneratorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 980, minHeight: 700)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("播放") {
                Button("播放 / 暂停") {
                    viewModel.togglePlaybackFromCommand()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }
}
