import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(sort: \SessionModel.createdAt, order: .reverse)
    private var sessions: [SessionModel]

    @State private var selectedSession: SessionModel?
    @Environment(AppDependencyContainer.self) private var deps

    var body: some View {
        List(sessions, selection: $selectedSession) { session in
            SessionRowView(session: session)
                .tag(session)
                .accessibilityIdentifier("sessionRow")
        }
        .listStyle(.sidebar)
        .navigationTitle("録音一覧")
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "録音がありません",
                    systemImage: "waveform",
                    description: Text("新しい録音を開始してください")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    deleteSelected()
                } label: {
                    Label("削除", systemImage: "trash")
                }
                .disabled(selectedSession == nil)
            }
        }
        .navigationDestination(item: $selectedSession) { session in
            SessionDetailView(session: session)
        }
    }

    private func deleteSelected() {
        guard let session = selectedSession else { return }
        // 削除は SessionManager.deleteSession に一元化する。録音ファイル（Both モードは
        // primary + `_system` 派生の 2 ファイル）と SwiftData レコードをまとめて削除する。
        let sessionID = session.id
        selectedSession = nil
        Task {
            try? await deps.sessionManager.deleteSession(sessionID)
        }
    }
}
