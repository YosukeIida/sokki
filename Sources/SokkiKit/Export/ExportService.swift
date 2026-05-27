import Foundation

enum ExportFormat: String, CaseIterable {
    case markdown    = "Markdown"
    case srt         = "SRT"
    case vtt         = "VTT"
    case plainText   = "テキスト"

    var fileExtension: String {
        switch self {
        case .markdown:  "md"
        case .srt:       "srt"
        case .vtt:       "vtt"
        case .plainText: "txt"
        }
    }
}

protocol Exporter {
    var format: ExportFormat { get }
    func export(session: SessionModel) -> String
}

struct ExportService {
    private let exporters: [ExportFormat: any Exporter]

    init() {
        exporters = [
            .markdown:  MarkdownExporter(),
            .srt:       SRTExporter(),
            .vtt:       VTTExporter(),
            .plainText: PlainTextExporter(),
        ]
    }

    func export(session: SessionModel, format: ExportFormat) -> String {
        exporters[format]?.export(session: session) ?? ""
    }
}
