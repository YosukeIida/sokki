import SwiftUI
import SwiftData
import SokkiKit

@main
struct sokkiApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try makeModelContainer()
        } catch {
            fatalError("ModelContainer initialization failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(AppDependencyContainer(modelContainer: container))
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .modelContainer(container)
        }
    }
}
