import Foundation

struct SRTExporter: Exporter {
    let format: ExportFormat = .srt

    func export(session: SessionModel) -> String {
        session.sortedSegments.enumerated().map { (i, seg) in
            """
            \(i + 1)
            \(srtTimestamp(seg.start)) --> \(srtTimestamp(seg.end))
            \(seg.text)

            """
        }.joined()
    }

    private func srtTimestamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}

struct VTTExporter: Exporter {
    let format: ExportFormat = .vtt

    func export(session: SessionModel) -> String {
        var lines = ["WEBVTT", ""]
        for seg in session.sortedSegments {
            lines += [
                "\(vttTimestamp(seg.start)) --> \(vttTimestamp(seg.end))",
                seg.text,
                ""
            ]
        }
        return lines.joined(separator: "\n")
    }

    private func vttTimestamp(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - floor(seconds)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
