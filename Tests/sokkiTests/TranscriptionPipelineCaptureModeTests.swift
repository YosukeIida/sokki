import Testing
import Foundation
import SwiftData
@testable import SokkiKit

/// TranscriptionPipeline のキャプチャモード別フロー検証。
/// Both（TASK-12）で mic/system の両ストリームが購読され、停止で flush が完了することと、
/// 既存 .micOnly / .systemOnly の回帰を確認する。
@Suite("TranscriptionPipeline capture modes")
@MainActor
struct TranscriptionPipelineCaptureModeTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: SessionModel.self,
                 SegmentModel.self,
                 SpeakerProfileModel.self,
                 AppSettingsModel.self,
            configurations: config
        )
    }

    private func makePipeline(
        systemTap: MockSystemAudioTap,
        micTap: MockMicrophoneCapture,
        engine: MockTranscriptionEngine,
        container: ModelContainer
    ) -> (TranscriptionPipeline, SessionManager) {
        let capture = AudioCaptureManager(systemTap: systemTap, microphone: micTap)
        let sessionManager = SessionManager(modelContainer: container)
        let store = SpeakerProfileStore(modelContext: ModelContext(container))
        let pipeline = TranscriptionPipeline(
            captureManager: capture,
            transcriptionEngine: engine,
            diarizationEngine: SpeakerKitEngine(),
            speakerStore: store,
            sessionManager: sessionManager
        )
        return (pipeline, sessionManager)
    }

    /// SessionManager が払い出した録音ファイル（primary + `_system` 派生）を削除する。
    private func cleanupAudioFiles(_ manager: SessionManager) async {
        guard let snapshots = try? await manager.allSessionSnapshots() else { return }
        for snapshot in snapshots {
            let url = URL(fileURLWithPath: snapshot.audioFilePath)
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: AudioCaptureManager.systemFileURL(forPrimary: url))
        }
    }

    /// `condition` が true になるまで最大 `timeout` 待つ（非同期伝播の収束待ち）。
    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ condition: () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func stubUpdate(_ text: String) -> TranscriptionStreamUpdate {
        TranscriptionStreamUpdate(
            newlyConfirmed: [TranscriptionSegmentSnapshot(start: 0, end: 1, text: text)],
            hypothesis: ""
        )
    }

    @Test(".both: mic/system の両ストリームを購読し、停止で flush が完了する")
    func bothSubscribesBothStreamsAndFlushes() async throws {
        let container = try makeContainer()
        let systemTap = MockSystemAudioTap()
        let micTap = MockMicrophoneCapture()
        let engine = MockTranscriptionEngine()
        await engine.setStubbedStreamUpdates([stubUpdate("both")])
        let (pipeline, sessionManager) = makePipeline(
            systemTap: systemTap, micTap: micTap, engine: engine, container: container
        )

        try await pipeline.start(mode: .both, sessionTitle: "both-test")

        micTap.send(Array(repeating: 0.3, count: 160))
        systemTap.send(Array(repeating: 0.2, count: 160))

        // 両レーンのチャンクがエンジンに届くまで待つ（停止前に確実に配信させる）。
        await waitUntil {
            let lanes = await engine.receivedLanes
            return lanes.contains(.microphone) && lanes.contains(.system)
        }

        try await pipeline.stop()

        let lanes = await engine.receivedLanes
        #expect(lanes.contains(.microphone))
        #expect(lanes.contains(.system))
        #expect(pipeline.confirmedSegments.count == 1)
        #expect(pipeline.confirmedSegments.first?.text == "both")
        #expect(pipeline.isRunning == false)

        await cleanupAudioFiles(sessionManager)
    }

    @Test("回帰 .micOnly: mic ストリームのみ購読し flush が完了する")
    func micOnlyRegression() async throws {
        let container = try makeContainer()
        let systemTap = MockSystemAudioTap()
        let micTap = MockMicrophoneCapture()
        let engine = MockTranscriptionEngine()
        await engine.setStubbedStreamUpdates([stubUpdate("mic")])
        let (pipeline, sessionManager) = makePipeline(
            systemTap: systemTap, micTap: micTap, engine: engine, container: container
        )

        try await pipeline.start(mode: .micOnly, sessionTitle: "mic-test")
        micTap.send(Array(repeating: 0.3, count: 160))
        await waitUntil { await engine.receivedLanes.contains(.microphone) }
        try await pipeline.stop()

        let lanes = await engine.receivedLanes
        #expect(lanes.allSatisfy { $0 == .microphone })
        #expect(lanes.contains(.microphone))
        #expect(pipeline.confirmedSegments.first?.text == "mic")
        #expect(pipeline.isRunning == false)

        await cleanupAudioFiles(sessionManager)
    }

    @Test(".both: micLevelStream / systemLevelStream が UI 配線用に独立して流れる（TASK-13）")
    func bothLevelStreamsFlowIndependentlyForUI() async throws {
        let container = try makeContainer()
        let systemTap = MockSystemAudioTap()
        let micTap = MockMicrophoneCapture()
        let engine = MockTranscriptionEngine()
        let (pipeline, sessionManager) = makePipeline(
            systemTap: systemTap, micTap: micTap, engine: engine, container: container
        )

        try await pipeline.start(mode: .both, sessionTitle: "level-stream-test")

        var micIterator = pipeline.micLevelStream.makeAsyncIterator()
        var systemIterator = pipeline.systemLevelStream.makeAsyncIterator()

        micTap.send(Array(repeating: 0.4, count: 160))
        systemTap.send(Array(repeating: 0.1, count: 160))

        let micLevel = try #require(await micIterator.next())
        let systemLevel = try #require(await systemIterator.next())

        #expect(micLevel > -60 && micLevel <= 0)
        #expect(systemLevel > -60 && systemLevel <= 0)
        // 振幅が異なるサンプルを流したので、独立配信であればレベル値も異なる。
        #expect(micLevel != systemLevel)

        try await pipeline.stop()
        await cleanupAudioFiles(sessionManager)
    }

    @Test("設定した文字起こし言語が pipeline.start 経由で engine.setTranscriptionLanguage に伝播する（TASK-45）")
    func transcriptionLanguagePropagatesToEngine() async throws {
        let container = try makeContainer()
        let engine = MockTranscriptionEngine()
        let (pipeline, sessionManager) = makePipeline(
            systemTap: MockSystemAudioTap(), micTap: MockMicrophoneCapture(),
            engine: engine, container: container
        )

        try await pipeline.start(mode: .micOnly, sessionTitle: "lang-ja", transcriptionLanguage: "ja")
        try await pipeline.stop()

        #expect(await engine.receivedLanguageSettings == ["ja"])

        await cleanupAudioFiles(sessionManager)
    }

    @Test("transcriptionLanguage を省略した場合は nil（自動検出）が engine に伝播する（TASK-45）")
    func omittedTranscriptionLanguagePropagatesNil() async throws {
        let container = try makeContainer()
        let engine = MockTranscriptionEngine()
        let (pipeline, sessionManager) = makePipeline(
            systemTap: MockSystemAudioTap(), micTap: MockMicrophoneCapture(),
            engine: engine, container: container
        )

        try await pipeline.start(mode: .micOnly, sessionTitle: "lang-default")
        try await pipeline.stop()

        #expect(await engine.receivedLanguageSettings == [String?.none])

        await cleanupAudioFiles(sessionManager)
    }

    @Test("回帰 .systemOnly: system ストリームのみ購読し flush が完了する")
    func systemOnlyRegression() async throws {
        let container = try makeContainer()
        let systemTap = MockSystemAudioTap()
        let micTap = MockMicrophoneCapture()
        let engine = MockTranscriptionEngine()
        await engine.setStubbedStreamUpdates([stubUpdate("system")])
        let (pipeline, sessionManager) = makePipeline(
            systemTap: systemTap, micTap: micTap, engine: engine, container: container
        )

        try await pipeline.start(mode: .systemOnly, sessionTitle: "system-test")
        systemTap.send(Array(repeating: 0.2, count: 160))
        await waitUntil { await engine.receivedLanes.contains(.system) }
        try await pipeline.stop()

        let lanes = await engine.receivedLanes
        #expect(lanes.allSatisfy { $0 == .system })
        #expect(lanes.contains(.system))
        #expect(pipeline.confirmedSegments.first?.text == "system")
        #expect(pipeline.isRunning == false)

        await cleanupAudioFiles(sessionManager)
    }
}
