import AVFoundation

public enum AudioLane: Sendable {
    case microphone
    case system
}

public struct AudioChunk: Sendable {
    public let lane: AudioLane
    public let samples: [Float]   // 16kHz, mono, Float32
    public let capturedAt: Date
}

actor AudioCaptureManager {

    enum CaptureMode: String {
        case micOnly    = "mic"
        case systemOnly = "system"
        case both       = "both"
    }

    enum CaptureError: Error {
        case audioEngineStartFailed(Error)
        /// システム音声キャプチャ（Core Audio Taps）の生成に失敗。基底の OSStatus を保持する。
        case systemAudioCaptureFailed(SystemAudioTapError)
    }

    private var micContinuation:      AsyncStream<AudioChunk>.Continuation?
    private var systemContinuation:   AsyncStream<AudioChunk>.Continuation?
    private var micLevelContinuation: AsyncStream<Float>.Continuation?
    private var systemLevelContinuation: AsyncStream<Float>.Continuation?

    private(set) var micStream:      AsyncStream<AudioChunk>
    private(set) var systemStream:   AsyncStream<AudioChunk>
    private(set) var micLevelStream: AsyncStream<Float>
    private(set) var systemLevelStream: AsyncStream<Float>

    /// レーンごとの録音ファイルライター（2 ファイル別保存・TASK-12）。
    private var micFileWriter: AudioFileWriter?
    private var systemFileWriter: AudioFileWriter?

    /// マイク音声キャプチャ（AVAudioEngine）。テストではモックを注入する。
    private let microphone: MicrophoneCapturing
    /// システム音声キャプチャ（Core Audio Taps）。テストではモックを注入する。
    private let systemTap: SystemAudioTapping

    /// 録音セッションの世代。start（resetStreams）ごとに採番し、IO コールバックから発火する
    /// 非構造化 Task が採番時の世代を捕捉する。dispatch 時に現行世代と照合し、停止後に遅れて
    /// 走った旧セッションのサンプルが新しい continuation へ混入するのを防ぐ（tap の IO ブロックや
    /// AVAudioEngine の tap は stop 後も 1 回程度呼ばれうるため）。
    private var captureGeneration: UInt64 = 0

    /// 録音ファイルの初期化・書き込みで発生した最新のエラー（容量不足など）。
    /// 音声認識自体は継続するため録音は止めないが、呼び出し元が利用者へ通知できるよう保持する（P1）。
    private(set) var recordingSaveError: Error?

    init(
        systemTap: SystemAudioTapping = SystemAudioTap(),
        microphone: MicrophoneCapturing = MicrophoneCapture()
    ) {
        self.systemTap = systemTap
        self.microphone = microphone

        var micCont:    AsyncStream<AudioChunk>.Continuation!
        var sysCont:    AsyncStream<AudioChunk>.Continuation!
        var micLvlCont: AsyncStream<Float>.Continuation!
        var sysLvlCont: AsyncStream<Float>.Continuation!

        micStream          = AsyncStream { micCont    = $0 }
        systemStream       = AsyncStream { sysCont    = $0 }
        // レベルストリームは表示専用（UI が追いつかない間の未消費値が無制限に溜まらないよう
        // 最新値のみ保持する。音声認識/録音が読む micStream/systemStream は無制限のまま・
        // 1 サンプルも欠落させない・codex レビュー対応 TASK-13）。
        micLevelStream     = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { micLvlCont = $0 }
        systemLevelStream  = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sysLvlCont = $0 }

        micContinuation         = micCont
        systemContinuation      = sysCont
        micLevelContinuation    = micLvlCont
        systemLevelContinuation = sysLvlCont
    }

    func startCapture(mode: CaptureMode, outputURL: URL? = nil) async throws {
        // 2回目以降の録音のために新しいストリームを作り直す（AsyncStream は使い捨て）
        resetStreams()
        switch mode {
        case .micOnly:
            try startMicCapture(outputURL: outputURL)
        case .systemOnly:
            try startSystemCapture(outputURL: outputURL)
        case .both:
            try startBothCapture(primaryURL: outputURL)
        }
    }

    private func resetStreams() {
        var micCont:    AsyncStream<AudioChunk>.Continuation!
        var sysCont:    AsyncStream<AudioChunk>.Continuation!
        var micLvlCont: AsyncStream<Float>.Continuation!
        var sysLvlCont: AsyncStream<Float>.Continuation!

        micStream         = AsyncStream { micCont    = $0 }
        systemStream      = AsyncStream { sysCont    = $0 }
        // 表示専用レベルストリームは最新値のみ保持（codex レビュー対応 TASK-13。詳細は init 参照）。
        micLevelStream    = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { micLvlCont = $0 }
        systemLevelStream = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sysLvlCont = $0 }

        micContinuation         = micCont
        systemContinuation      = sysCont
        micLevelContinuation    = micLvlCont
        systemLevelContinuation = sysLvlCont
        // 新しい録音セッションのために前回のエラー状態をリセットする
        recordingSaveError = nil
        // 新しい世代を採番する。以降に発火する dispatch はこの世代でのみ配信される。
        captureGeneration &+= 1
    }

    func stopCapture() async {
        // 停止は起動の逆順: mic を先に、system を後に止める（TASK-12 受け入れ基準 #1）。
        microphone.stop()
        systemTap.stop()

        // 書き込み中に発生したエラー（容量不足など）があれば記録する
        if let writeError = micFileWriter?.lastWriteError {
            recordingSaveError = writeError
        }
        if let writeError = systemFileWriter?.lastWriteError {
            recordingSaveError = writeError
        }
        // tap / engine 停止後にファイルを閉じる（書き込み中の競合は AudioFileWriter のロックで防ぐ）
        micFileWriter?.close()
        micFileWriter = nil
        systemFileWriter?.close()
        systemFileWriter = nil

        // ストリームを閉じる → transcribeStream の for-await ループが終了し、フラッシュが走る
        micContinuation?.finish()
        micContinuation = nil
        micLevelContinuation?.finish()
        micLevelContinuation = nil
        systemContinuation?.finish()
        systemContinuation = nil
        systemLevelContinuation?.finish()
        systemLevelContinuation = nil
    }

    // MARK: - Both（マイク + システム同時 / TASK-12）

    /// マイクとシステム音声を同時にキャプチャする。
    ///
    /// 起動順は **system（tap）先 → mic 後**（受け入れ基準 #1）。system 起動後に mic が失敗した場合は、
    /// 起動済みの system を確実に停止して巻き戻す。ファイルは **primary（mic）と `_system` 派生（system）の
    /// 2 ファイルに別保存**する（受け入れ基準 #2）。既存の再生／エクスポート動線は primary（mic）を読むため、
    /// primary を mic レーンに割り当ててモデル変更を避ける。
    private func startBothCapture(primaryURL: URL?) throws {
        let systemURL = primaryURL.map { Self.systemFileURL(forPrimary: $0) }

        // 1. system を先に起動する。
        try startSystemCapture(outputURL: systemURL)

        // 2. mic を後に起動する。失敗したら起動済みの system を巻き戻す。
        do {
            try startMicCapture(outputURL: primaryURL)
        } catch {
            systemTap.stop()
            systemFileWriter?.close()
            systemFileWriter = nil
            micFileWriter?.close()
            micFileWriter = nil
            throw error
        }
    }

    /// primary（mic）ファイル URL から system レーンの派生 URL を作る純粋関数（テスト対象）。
    /// 拡張子の直前に `_system` を挿入する（`foo.m4a` → `foo_system.m4a`）。
    static func systemFileURL(forPrimary url: URL) -> URL {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        let name = ext.isEmpty ? "\(base)_system" : "\(base)_system.\(ext)"
        return directory.appendingPathComponent(name)
    }

    // MARK: - Microphone (Phase 1)

    private func startMicCapture(outputURL: URL?) throws {
        let writer = openWriter(at: outputURL)
        self.micFileWriter = writer
        let generation = captureGeneration

        do {
            try microphone.start { [weak self, writer] samples, capturedAt in
                // 音声スレッドで同期書き込み（順序保証）。
                if let writer, let buffer = AudioSampleConversion.makeBuffer(from: samples) {
                    writer.write(buffer)
                }
                Task { [weak self] in
                    await self?.dispatchMic(samples: samples, capturedAt: capturedAt, generation: generation)
                }
            }
        } catch {
            self.micFileWriter?.close()
            self.micFileWriter = nil
            throw CaptureError.audioEngineStartFailed(error)
        }
    }

    private func dispatchMic(samples: [Float], capturedAt: Date, generation: UInt64) {
        // 停止後に遅延実行された旧セッションの Task を破棄する（新 stream への混入防止）。
        guard generation == captureGeneration else { return }
        let chunk = AudioChunk(lane: .microphone, samples: samples, capturedAt: capturedAt)
        micContinuation?.yield(chunk)
        micLevelContinuation?.yield(AudioSampleConversion.rmsLevel(samples))
    }

    // MARK: - System audio (Phase 2 / Core Audio Taps)

    /// システム音声キャプチャを開始し、systemStream / systemLevelStream に流す。
    ///
    /// IO クロージャは専用 IO キュー上で呼ばれ、変換済み `[Float]` のみをアクター境界へ渡す。
    /// `outputURL` が指定されていれば同期的にファイルへ書き出す（2 ファイル別保存・TASK-12）。
    private func startSystemCapture(outputURL: URL?) throws {
        let writer = openWriter(at: outputURL)
        self.systemFileWriter = writer
        let generation = captureGeneration
        do {
            try systemTap.start { [weak self, writer] samples, capturedAt in
                // IO キュー上で同期書き込み（順序保証）。
                if let writer, let buffer = AudioSampleConversion.makeBuffer(from: samples) {
                    writer.write(buffer)
                }
                Task { [weak self] in
                    await self?.dispatchSystem(samples: samples, capturedAt: capturedAt, generation: generation)
                }
            }
        } catch let error as SystemAudioTapError {
            self.systemFileWriter?.close()
            self.systemFileWriter = nil
            throw CaptureError.systemAudioCaptureFailed(error)
        }
    }

    private func dispatchSystem(samples: [Float], capturedAt: Date, generation: UInt64) {
        // 停止後に遅延実行された旧セッションの Task を破棄する（新 stream への混入防止）。
        guard generation == captureGeneration else { return }
        let chunk = AudioChunk(lane: .system, samples: samples, capturedAt: capturedAt)
        systemContinuation?.yield(chunk)
        systemLevelContinuation?.yield(AudioSampleConversion.rmsLevel(samples))
    }

    // MARK: - File writer

    /// 録音ファイルライターを開く。初期化に失敗しても音声認識は継続するため、エラーは
    /// `recordingSaveError` に記録し呼び出し元が利用者へ通知できるようにする（P1）。
    private func openWriter(at url: URL?) -> AudioFileWriter? {
        guard let url else { return nil }
        do {
            return try AudioFileWriter(
                url: url,
                processingFormat: AudioSampleConversion.makeTargetFormat()
            )
        } catch {
            recordingSaveError = error
            return nil
        }
    }
}
