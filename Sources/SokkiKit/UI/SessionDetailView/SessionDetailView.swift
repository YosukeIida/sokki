import SwiftUI
import UniformTypeIdentifiers

struct SessionDetailView: View {
    let session: SessionModel
    @State private var showingExport = false
    @State private var exportText = ""
    @State private var selectedFormat: ExportFormat = .markdown

    private let exportService = ExportService()
    private let exportSaveService = ExportSaveService()

    var body: some View {
        VStack(spacing: 0) {
            SegmentListView(session: session)
        }
        .navigationTitle(session.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Button("\(format.rawValue) としてコピー") {
                            copyToClipboard(format: format)
                        }
                    }
                    Divider()
                    Button("ファイルへ保存…") {
                        Task { await saveMarkdownToFile() }
                    }
                } label: {
                    Label("エクスポート", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func copyToClipboard(format: ExportFormat) {
        let text = exportService.export(session: session, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func saveMarkdownToFile() async {
        let text = exportService.export(session: session, format: .markdown)
        let fileName = ExportSaveService.suggestedFileName(title: session.title, date: session.createdAt)
        let markdownType = UTType(filenameExtension: "md") ?? .plainText
        _ = await exportSaveService.save(text: text, suggestedFileName: fileName, contentType: markdownType)
    }
}
