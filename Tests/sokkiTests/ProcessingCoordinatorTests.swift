import Testing
import Foundation
import SwiftData
@testable import SokkiKit

/// ProcessingCoordinator（録音後処理の直列オーケストレータ / TASK-16）の単体テスト。
///
/// ジョブの実処理は注入した mock runner で観測する。対象セッションは実際の in-memory SwiftData
/// から得た `PersistentIdentifier` を再利用する（コーディネータは sessionID の中身に依存しない）。
@MainActor
@Suite("ProcessingCoordinator")
struct ProcessingCoordinatorTests {

    /// runner の実行状況を記録する観測用ヘルパー（全て MainActor 上で更新されるためデータ競合はない）。
    @MainActor
    final class ExecutionTracker {
        var active = 0
        var maxActive = 0
        var startOrder: [Int] = []
        var endOrder: [Int] = []
        var cancelled: [Int] = []

        func begin(_ tag: Int) {
            startOrder.append(tag)
            active += 1
            maxActive = max(maxActive, active)
        }

        func end(_ tag: Int) {
            active -= 1
            endOrder.append(tag)
        }
    }

    private func makeSessionID() async throws -> PersistentIdentifier {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: SessionModel.self, SegmentModel.self, SpeakerProfileModel.self, AppSettingsModel.self,
            configurations: config
        )
        let manager = SessionManager(modelContainer: container)
        return try await manager.createSession(title: "coordinator-test", mode: .micOnly)
    }

    /// キューが空になるまで待つ（テスト用の同期ポイント）。
    private func waitUntilIdle(_ coordinator: ProcessingCoordinator, timeoutMs: Int = 3000) async {
        var waited = 0
        while (coordinator.isProcessing || coordinator.pendingCount > 0) && waited < timeoutMs {
            try? await Task.sleep(for: .milliseconds(5))
            waited += 5
        }
    }

    /// ジョブが実際に走り始めるまで待つ。
    private func waitUntilProcessing(_ coordinator: ProcessingCoordinator, timeoutMs: Int = 3000) async {
        var waited = 0
        while !coordinator.isProcessing && waited < timeoutMs {
            try? await Task.sleep(for: .milliseconds(2))
            waited += 2
        }
    }

    @Test("複数ジョブが直列に 1 件ずつ実行される（並行実行されない）")
    func serialExecution() async throws {
        let sid = try await makeSessionID()
        let jobs = (0..<4).map { _ in ProcessingJob(sessionID: sid, kind: .finalizeTranscription) }
        var index: [UUID: Int] = [:]
        for (i, j) in jobs.enumerated() { index[j.id] = i }

        let tracker = ExecutionTracker()
        let coordinator = ProcessingCoordinator(runner: { job in
            let tag = index[job.id]!
            tracker.begin(tag)
            defer { tracker.end(tag) }
            try? await Task.sleep(for: .milliseconds(15))
        })
        defer { coordinator.shutdown() }

        for j in jobs { coordinator.enqueue(j) }
        await waitUntilIdle(coordinator)

        #expect(tracker.maxActive == 1)               // 同時実行は常に 1 件
        #expect(tracker.endOrder == [0, 1, 2, 3])     // enqueue 順に直列完了
    }

    @Test("失敗したジョブが後続ジョブをブロックしない")
    func failedJobDoesNotBlockFollowing() async throws {
        let sid = try await makeSessionID()
        let jobs = (0..<3).map { _ in ProcessingJob(sessionID: sid, kind: .finalizeTranscription) }
        var index: [UUID: Int] = [:]
        for (i, j) in jobs.enumerated() { index[j.id] = i }

        struct BoomError: Error {}
        let tracker = ExecutionTracker()
        let coordinator = ProcessingCoordinator(runner: { job in
            let tag = index[job.id]!
            tracker.begin(tag)
            defer { tracker.end(tag) }
            if tag == 1 { throw BoomError() }         // 2 件目が失敗
            try? await Task.sleep(for: .milliseconds(10))
        })
        defer { coordinator.shutdown() }

        for j in jobs { coordinator.enqueue(j) }
        await waitUntilIdle(coordinator)

        // 失敗した 1 も含め、全ジョブが走り、後続の 2 も完了している。
        #expect(tracker.endOrder == [0, 1, 2])
        #expect(tracker.maxActive == 1)
    }

    @Test("実行中ジョブをキャンセルしても後続ジョブは継続する")
    func cancellingCurrentJobKeepsQueueRunning() async throws {
        let sid = try await makeSessionID()
        let longJob = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)
        let nextJob = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)
        let index: [UUID: Int] = [longJob.id: 0, nextJob.id: 1]

        let tracker = ExecutionTracker()
        let coordinator = ProcessingCoordinator(runner: { job in
            let tag = index[job.id]!
            tracker.begin(tag)
            defer { tracker.end(tag) }
            if tag == 0 {
                // longJob: キャンセルされるまでブロックする。
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    tracker.cancelled.append(tag)     // キャンセルを観測
                }
            } else {
                // 後続ジョブはすぐ完了する。
                try? await Task.sleep(for: .milliseconds(10))
            }
        })
        defer { coordinator.shutdown() }

        coordinator.enqueue(longJob)
        await waitUntilProcessing(coordinator)        // longJob が走り始めるまで待つ
        coordinator.enqueue(nextJob)
        coordinator.cancelCurrentJob()                // 実行中の longJob をキャンセル
        await waitUntilIdle(coordinator)

        #expect(tracker.cancelled == [0])             // longJob だけがキャンセルされ
        #expect(tracker.endOrder.contains(1))         // 後続 nextJob は継続実行された
    }

    @Test("process(_:) は対象ジョブのキャンセルを呼び出し元へ伝播する")
    func processRethrowsCancellation() async throws {
        let sid = try await makeSessionID()
        let job = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)

        let coordinator = ProcessingCoordinator(runner: { _ in
            try await Task.sleep(for: .seconds(5))    // キャンセルされるまでブロック
        })
        defer { coordinator.shutdown() }

        let waiter = Task { try await coordinator.process(job) }
        await waitUntilProcessing(coordinator)
        coordinator.cancelCurrentJob()

        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }
    }

    @Test("スリープ復帰（didWake）後もキューが継続処理される")
    func continuesProcessingAfterWake() async throws {
        let sid = try await makeSessionID()
        let firstJob = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)
        let secondJob = ProcessingJob(sessionID: sid, kind: .finalizeTranscription)
        let index: [UUID: Int] = [firstJob.id: 0, secondJob.id: 1]

        let tracker = ExecutionTracker()
        let coordinator = ProcessingCoordinator(runner: { job in
            let tag = index[job.id]!
            tracker.begin(tag)
            defer { tracker.end(tag) }
            try? await Task.sleep(for: .milliseconds(10))
        })
        defer { coordinator.shutdown() }

        coordinator.enqueue(firstJob)
        await waitUntilIdle(coordinator)

        // スリープ復帰を模擬。consumer は生存しているため再起動は起きず、キューはそのまま継続する。
        coordinator.handleWillSleep()
        coordinator.handleDidWake()

        coordinator.enqueue(secondJob)
        await waitUntilIdle(coordinator)

        #expect(tracker.endOrder == [0, 1])
    }

    @Test("shutdown 後は enqueue しても処理されない")
    func noProcessingAfterShutdown() async throws {
        let sid = try await makeSessionID()
        let tracker = ExecutionTracker()
        let coordinator = ProcessingCoordinator(runner: { job in
            tracker.begin(0)
            tracker.end(0)
        })

        coordinator.shutdown()
        coordinator.enqueue(ProcessingJob(sessionID: sid, kind: .finalizeTranscription))
        try? await Task.sleep(for: .milliseconds(30))

        #expect(tracker.startOrder.isEmpty)
    }
}
