import Testing
import SnapshotTesting
import SwiftUI
import AppKit
@testable import SokkiKit

// MARK: - RecordingView スナップショットテスト
//
// 初回実行時: __Snapshots__/ に PNG を記録（テストは失敗 → 正常）
// 2回目以降: 記録済み PNG と比較（差分があればテスト失敗）
// 意図的な変更時: RECORD=1 swift test --filter SnapshotTests で再記録

@Suite("RecordingView Snapshots")
@MainActor
struct RecordingViewSnapshotTests {

    private let size = CGSize(width: 800, height: 560)

    // RecordingView は @Query（AppSettingsModel）と @Environment(\.modelContext) を使うため、
    // SwiftUI 環境に .modelContainer を注入しないと @Query が空になりクエリ経路が検証されない（TASK-45）。
    @Test("アイドル状態")
    func idle() throws {
        let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.idle())
        let view = wrap(RecordingView()
            .environment(deps)
            .modelContainer(deps.modelContainer))
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(size: size))
        }
    }

    @Test("ローディング状態（モデルDL中）")
    func loading() throws {
        let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.loading())
        let view = wrap(RecordingView()
            .environment(deps)
            .modelContainer(deps.modelContainer))
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(size: size))
        }
    }

    @Test("録音中（テキストあり）")
    func recordingWithText() throws {
        let deps = AppDependencyContainer.preview(pipeline: PreviewPipeline.recordingWithText())
        let view = wrap(RecordingView()
            .environment(deps)
            .modelContainer(deps.modelContainer))
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: view, as: .image(size: size))
        }
    }

    private func wrap<V: View>(_ view: V) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        return host
    }
}

// MARK: - SessionDetailView スナップショットテスト

@Suite("SessionDetailView Snapshots")
@MainActor
struct SessionDetailViewSnapshotTests {

    private let size = CGSize(width: 800, height: 560)

    @Test("セグメントあり")
    func withSegments() throws {
        let session = makeSession(segmentTexts: [
            "本日はお集まりいただきありがとうございます。",
            "今日のアジェンダを共有します。",
            "まず進捗報告から始めましょう。",
        ])
        let host = NSHostingView(rootView:
            SessionDetailView(session: session)
                .frame(width: size.width, height: size.height)
        )
        host.frame = CGRect(origin: .zero, size: size)
        withSnapshotTesting(record: recordMode) {
            assertSnapshot(of: host, as: .image(size: size))
        }
    }

    private func makeSession(segmentTexts: [String]) -> SessionModel {
        let session = SessionModel(title: "テストセッション", audioFilePath: "", captureMode: "mic")
        for (i, text) in segmentTexts.enumerated() {
            let seg = SegmentModel(start: Double(i) * 3, end: Double(i + 1) * 3, text: text)
            session.segments.append(seg)
        }
        return session
    }
}

// MARK: - ヘルパー

/// 環境変数 RECORD=1 でスナップショットを全件再記録する
private var recordMode: SnapshotTestingConfiguration.Record {
    ProcessInfo.processInfo.environment["RECORD"] == "1" ? .all : .missing
}
