import Testing
@testable import SokkiKit

@Suite("Exporter")
struct ExportTests {

    @Test("Markdown エクスポートのフォーマット確認")
    func markdownFormat() {
        let exporter = MarkdownExporter()

        let session = SessionModel(title: "Meeting_20260527", audioFilePath: "", captureMode: "mic")
        let seg1 = SegmentModel(start: 0, end: 5, text: "こんにちは、はじめまして。")
        let seg2 = SegmentModel(start: 7, end: 12, text: "よろしくお願いします。")
        seg1.session = session
        seg2.session = session
        session.segments = [seg1, seg2]

        let output = exporter.export(session: session)

        #expect(output.contains("## Meeting_20260527"))
        #expect(output.contains("こんにちは、はじめまして。"))
        #expect(output.contains("00:00:00"))
        #expect(output.contains("00:00:07"))
    }

    @Test("SRT エクスポートのタイムスタンプフォーマット")
    func srtTimestampFormat() {
        let exporter = SRTExporter()

        let session = SessionModel(title: "Test", audioFilePath: "", captureMode: "mic")
        let seg = SegmentModel(start: 3661.5, end: 3665.0, text: "テスト")
        seg.session = session
        session.segments = [seg]

        let output = exporter.export(session: session)

        #expect(output.contains("01:01:01,500"))
        #expect(output.contains("01:01:05,000"))
    }

    @Test("VTT エクスポートのタイムスタンプフォーマット（1時間超の繰り上がり）")
    func vttTimestampFormat() {
        let exporter = VTTExporter()

        let session = SessionModel(title: "Test", audioFilePath: "", captureMode: "mic")
        let seg = SegmentModel(start: 3661.5, end: 3665.0, text: "テスト")
        seg.session = session
        session.segments = [seg]

        let output = exporter.export(session: session)

        #expect(output.hasPrefix("WEBVTT"))
        #expect(output.contains("01:01:01.500"))
        #expect(output.contains("01:01:05.000"))
        #expect(output.contains("テスト"))
    }

    @Test("SRT はカンマ区切り、VTT はドット区切りのミリ秒になる（回帰テスト）")
    func srtCommaVsVttDotMilliseconds() {
        let session = SessionModel(title: "Test", audioFilePath: "", captureMode: "mic")
        let seg = SegmentModel(start: 1.25, end: 2.5, text: "区切りテスト")
        seg.session = session
        session.segments = [seg]

        let srtOutput = SRTExporter().export(session: session)
        let vttOutput = VTTExporter().export(session: session)

        #expect(srtOutput.contains("00:00:01,250"))
        #expect(!srtOutput.contains("00:00:01.250"))
        #expect(vttOutput.contains("00:00:01.250"))
        #expect(!vttOutput.contains("00:00:01,250"))
    }

    @Test("SRT: セグメントが空のセッションは空文字を返す")
    func srtEmptySegments() {
        let session = SessionModel(title: "Empty", audioFilePath: "", captureMode: "mic")

        let output = SRTExporter().export(session: session)

        #expect(output.isEmpty)
    }

    @Test("VTT: セグメントが空のセッションはヘッダーのみを返す")
    func vttEmptySegments() {
        let session = SessionModel(title: "Empty", audioFilePath: "", captureMode: "mic")

        let output = VTTExporter().export(session: session)

        #expect(output.hasPrefix("WEBVTT"))
        #expect(!output.contains("-->"))
    }

    @Test("formatTimestamp の正確性")
    func timestampFormatting() {
        #expect(formatTimestamp(0) == "00:00:00")
        #expect(formatTimestamp(65) == "00:01:05")
        #expect(formatTimestamp(3661) == "01:01:01")
    }
}
