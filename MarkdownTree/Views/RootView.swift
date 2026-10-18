import SwiftUI

struct RootView: View {
    @Environment(Library.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = Router()

    var body: some View {
        @Bindable var library = library
        Group {
            if library.rootURL != nil {
                NavigationStack(path: $router.path) {
                    FolderView(relativePath: "")
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .folder(let path): FolderView(relativePath: path)
                            case .file(let path): DocumentView(relativePath: path)
                            }
                        }
                }
                .environment(router)
            } else {
                WelcomeView()
            }
        }
        .fileImporter(isPresented: $library.isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                router.popToRoot()
                library.setRoot(url)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await library.reload() } }
        }
    }
}

struct WelcomeView: View {
    @Environment(Library.self) private var library

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Markdown Tree")
                    .font(.largeTitle.bold())
                Text("Wähle einen Ordner – zum Beispiel deinen Cowork-OS-Ordner in iCloud Drive –, um durch seine Ordnerstruktur zu navigieren und alle Markdown-Dateien zu lesen.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            if let error = library.restoreError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Button {
                library.isPickingFolder = true
            } label: {
                Label("Ordner auswählen", systemImage: "folder.badge.plus")
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
            Text("Der Ordner wird nur gelesen, nie verändert.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
    }
}
