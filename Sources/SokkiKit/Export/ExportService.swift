import Foundation
import UniformTypeIdentifiers

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

    /// ファイル保存ダイアログ（NSSavePanel）に渡す UTType。
    /// 拡張子から解決する（srt/vtt はシステム未登録のため動的型になるが、
    /// preferredFilenameExtension は正しく拡張子を返す）。万一解決できない場合のみ
    /// プレーンテキストにフォールバックする。
    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .plainText
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
