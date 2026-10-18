import SwiftUI

@main
struct MarkdownTreeApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
    }
}
