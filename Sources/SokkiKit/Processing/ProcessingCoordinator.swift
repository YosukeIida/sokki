import Foundation
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

/// 録音後処理ジョブの種別。
///
/// 「停止 → 文字起こし仕上げ →（将来: 話者分離）→ 保存」というパイプラインの各段階を表す。
/// `.diarize` は TASK-25 系列（別スタック）の話者分離を後から挿入するための **拡張フック** であり、
/// 本ブランチでは enqueue されない（マージ時に統合する）。
public enum ProcessingJobKind: Sendable, Equatable {
    /// 録音停止後の最終 flush 待ち・フォールバック永続化・録音長確定をまとめて行う。
    case finalizeTranscription
    /// 将来のフック（本ブランチ未使用）: 確定済みセグメントに対してバッチ話者分離を実行する。
    case diarize

    /// 進捗 UI に表示する処理名。既存の `loadingMessage` と整合させる。
    public var displayName: String {
        switch self {
        case .finalizeTranscription: return "文字起こし処理中…"
        case .diarize: return "話者分離処理中…"
        }
    }
}

/// 後処理キューに積む 1 件のジョブ。
///
/// `@Model` を actor 境界越しに渡さないため、対象セッションは `PersistentIdentifier`（Sendable）で参照する。
/// ジョブ自体は Sendable な値型で、実際の処理内容は `ProcessingCoordinator` に注入された runner が解決する。
public struct ProcessingJob: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let sessionID: PersistentIdentifier
    public let kind: ProcessingJobKind

    public init(id: UUID = UUID(), sessionID: PersistentIdentifier, kind: ProcessingJobKind) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
    }
}

/// 録音後処理を直列に流すオーケストレータ。
///
/// 設計（TASK-16 / P2-6）:
/// - **AsyncStream ベースの直列キュー**。consumer タスクが 1 件ずつ `await` で実行するため、
///   ジョブが並行実行されることはない。
/// - **スリープ復帰**: `NSWorkspace` の willSleep / didWake を購読する。Swift Concurrency の
///   タスクはスリープ中に OS によって suspend され、復帰時に自動で resume されるため、キュー自体は
///   復帰後もそのまま継続処理される。observer は主に診断ログと、万一 consumer が停止していた場合の
///   防御的な再起動のために置く（`handleDidWake()` 参照）。
/// - **キャンセル**: ジョブ単位の `Task` cancellation。実行中ジョブをキャンセルしても後続ジョブは継続する
///   （1 件の失敗・キャンセルがキュー全体をブロックしない）。アプリ終了時（willTerminate）は現在ジョブを
///   キャンセルし、runner 側のキャンセルハンドラで部分結果を保存する best-effort フックを提供する。
/// - **進捗公開**: `@Observable` で `isProcessing` / `pendingCount` / `activeJobName` を公開する。
@MainActor
@Observable
public final class ProcessingCoordinator {

    /// ジョブを実際に処理するクロージャ。呼び出し側（Pipeline 等）が段階ごとの処理を注入する。
    /// runner の内部で `Task.isCancelled` / `CancellationError` を検知し、部分結果を保存する責務を持つ。
    public typealias Runner = @MainActor (ProcessingJob) async throws -> Void

    // MARK: - 公開状態（進捗 UI 用）

    /// 現在ジョブを処理中か。キューが空になると false に戻る。
    public private(set) var isProcessing: Bool = false
    /// 実行待ち + 実行中のジョブ総数。
    public private(set) var pendingCount: Int = 0
    /// 現在実行中のジョブの表示名（アイドル時は nil）。
    public private(set) var activeJobName: String? = nil

    // MARK: - 内部状態

    private let runner: Runner
    private var continuation: AsyncStream<ProcessingJob>.Continuation?
    private var consumerTask: Task<Void, Never>?
    /// 現在実行中ジョブの Task。ジョブ単位キャンセルのため保持する。
    private var currentJobTask: Task<Void, Error>?
    /// `process(_:)` の呼び出し元を、対応ジョブ完了時に再開するための継続。
    private var completions: [UUID: CheckedContinuation<Void, Error>] = [:]

    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var isShutDown = false

    public init(runner: @escaping Runner) {
        self.runner = runner
        startConsumer()
        observeSystemNotifications()
    }

    // MARK: - Enqueue API

    /// ジョブを積む（fire-and-forget）。完了を待たずに返る。
    public func enqueue(_ job: ProcessingJob) {
        guard !isShutDown else { return }
        pendingCount += 1
        continuation?.yield(job)
    }

    /// ジョブを積み、その **このジョブ** の完了まで待つ。
    /// キューは直列なので、先行ジョブが処理中なら順番待ちになる。runner が throw / キャンセルした場合は
    /// その error を rethrow する（後続ジョブの実行には影響しない）。
    public func process(_ job: ProcessingJob) async throws {
        guard !isShutDown else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            completions[job.id] = cont
            pendingCount += 1
            continuation?.yield(job)
        }
    }

    // MARK: - キャンセル / 終了

    /// 現在実行中のジョブをキャンセルする（後続ジョブは継続）。
    public func cancelCurrentJob() {
        currentJobTask?.cancel()
    }

    /// コーディネータを停止し、observer と consumer を片付ける。テストの teardown / アプリ終了時に呼ぶ。
    public func shutdown() {
        guard !isShutDown else { return }
        isShutDown = true
        currentJobTask?.cancel()
        continuation?.finish()
        consumerTask?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { center.removeObserver(o) }
        if let o = wakeObserver { center.removeObserver(o) }
        if let o = terminateObserver { NotificationCenter.default.removeObserver(o) }
        sleepObserver = nil
        wakeObserver = nil
        terminateObserver = nil
    }

    // MARK: - Consumer

    private func startConsumer() {
        let (stream, cont) = AsyncStream<ProcessingJob>.makeStream(bufferingPolicy: .unbounded)
        continuation = cont
        consumerTask = Task { @MainActor [weak self] in
            for await job in stream {
                guard let self else { break }
                await self.execute(job)
            }
        }
    }

    private func execute(_ job: ProcessingJob) async {
        pendingCount = max(0, pendingCount - 1)
        isProcessing = true
        activeJobName = job.kind.displayName

        // ジョブ単位でキャンセルできるよう子タスクとして実行する。
        let task = Task { @MainActor [runner] in
            try await runner(job)
        }
        currentJobTask = task
        let result = await task.result
        currentJobTask = nil

        // process(_:) で待っている呼び出し元があれば、その完了/失敗を通知する。
        if let waiter = completions.removeValue(forKey: job.id) {
            switch result {
            case .success: waiter.resume()
            case .failure(let error): waiter.resume(throwing: error)
            }
        }
        // 失敗・キャンセルは握りつぶし、for-await ループは次のジョブへ進む
        // （1 件の失敗が後続をブロックしない）。

        if pendingCount == 0 {
            isProcessing = false
            activeJobName = nil
        }
    }

    // MARK: - システム通知（スリープ復帰 / アプリ終了）

    private func observeSystemNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        sleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillSleep() }
        }
        wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleDidWake() }
        }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWillTerminate() }
        }
    }

    /// スリープに入るときの処理。consumer タスクは OS により suspend されるだけなので特別な停止は不要。
    /// 診断用にログのみ残す。
    func handleWillSleep() {
        NSLog("ProcessingCoordinator: system will sleep (pending=\(pendingCount))")
    }

    /// スリープ復帰時の処理。Swift Concurrency のタスクは自動で resume されるためキューはそのまま継続する。
    /// ここでは万一 consumer が終了していた場合に備えて防御的に再起動する。
    func handleDidWake() {
        NSLog("ProcessingCoordinator: system did wake (pending=\(pendingCount))")
        guard !isShutDown else { return }
        if consumerTask == nil || consumerTask?.isCancelled == true {
            startConsumer()
        }
    }

    /// アプリ終了時の best-effort フック。現在ジョブをキャンセルし、runner 側の
    /// キャンセルハンドラで部分結果の保存を試みる。なお確定セグメントはストリーミング中に逐次
    /// 永続化済みのため、ここで失われるのは高々「未確定 hypothesis」のみである。
    func handleWillTerminate() {
        NSLog("ProcessingCoordinator: app will terminate (pending=\(pendingCount))")
        cancelCurrentJob()
    }
}
