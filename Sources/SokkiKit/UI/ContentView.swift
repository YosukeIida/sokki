import SwiftUI

public struct ContentView: View {
    public init() {}
    public var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: RecordingView()) {
                    Label("録音", systemImage: "record.circle")
                }
                NavigationLink(destination: NavigationStack { SessionListView() }) {
                    Label("録音一覧", systemImage: "list.bullet")
                }
                NavigationLink(destination: NavigationStack { SpeakerProfileView() }) {
                    Label("話者プロファイル", systemImage: "person.2")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("sokki")
        } detail: {
            RecordingView()
        }
        .sokkiDesignSystem()
    }
}
