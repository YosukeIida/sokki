import SwiftUI
import SwiftData
import SokkiKit

@main
@MainActor
struct sokkiApp: App {
    let container: ModelContainer
    // WindowGroup と Settings の両シーンで同一インスタンスを共有する。
    // 翻訳設定（TASK-20）は SettingsView での変更を RecordingView が使う
    // TranslationCoordinator にも反映する必要があるため、シーンごとに
    // 別インスタンスを作ってはならない。
    let deps: AppDependencyContainer

    init() {
        do {
            container = try makeModelContainer()
        } catch {
            fatalError("ModelContainer initialization failed: \(error)")
        }
        deps = AppDependencyContainer(modelContainer: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environment(deps)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .modelContainer(container)
                .environment(deps)
        }
    }
}
