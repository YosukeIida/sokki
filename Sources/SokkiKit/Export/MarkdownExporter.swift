import Foundation

struct MarkdownExporter: Exporter {
    let format: ExportFormat = .markdown

    func export(session: SessionModel) -> String {
        var lines: [String] = ["## \(session.title)", ""]

        for seg in session.sortedSegments {
            let name = seg.speakerDisplayName
            let ts = formatTimestamp(seg.start)
            lines += ["**\(name)** `\(ts)`", seg.text, ""]
        }

        return lines.joined(separator: "\n")
    }
}

struct PlainTextExporter: Exporter {
    let format: ExportFormat = .plainText

    func export(session: SessionModel) -> String {
        session.sortedSegments.map(\.text).joined(separator: "\n")
    }
}

func formatTimestamp(_ seconds: Double) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    return String(format: "%02d:%02d:%02d", h, m, s)
}
