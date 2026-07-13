import SwiftUI
import SwiftData

struct SessionListView: View {
    @Query(sort: \SessionModel.createdAt, order: .reverse)
    private var sessions: [SessionModel]

    @State private var selectedSession: SessionModel?
    @Environment(\.modelContext) private var modelContext
    @Environment(AppDependencyContainer.self) private var deps
    private var importer: AudioFileImporter { deps.importer }

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
                    description: Text("新しい録音を開始してください、またはファイルを読み込んでください")
                )
            }
            if importer.isImporting {
                importingOverlay
            }
        }
        .safeAreaInset(edge: .top) {
            if let message = importer.importErrorMessage {
                importErrorBanner(message)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await importer.presentOpenPanelAndImport()
                    }
                } label: {
                    Label("ファイルを読み込む…", systemImage: "square.and.arrow.down")
                }
                .disabled(importer.isImporting)
                .accessibilityIdentifier("importFileButton")
            }
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

    private var importingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(importer.importingMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .accessibilityIdentifier("importingOverlay")
    }

    private func importErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                importer.dismissImportError()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding()
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
