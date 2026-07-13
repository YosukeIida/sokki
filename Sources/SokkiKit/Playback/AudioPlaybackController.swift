import AVFoundation
import Foundation

/// セグメントの時刻範囲。`AudioPlaybackController.segmentIndex(at:in:)` の入力として使う、
/// AVAudioPlayer に依存しない値型（テスト容易性のため `SegmentModel` から切り離してある）。
struct SegmentTimeRange: Sendable, Equatable {
    let start: Double
    let end: Double
}

/// `AudioPlaybackController` の再生系メソッドで発生しうるエラー。
enum AudioPlaybackError: Error, Sendable {
    /// `AVAudioPlayer.play()` が `false` を返した（オーディオ出力の確保に失敗した等）。
    case playFailed
}

/// 保存済み音声ファイルの再生を担当するコントローラ（FR-DATA-3 / TASK-33）。
///
/// AVAudioPlayer を MainActor に閉じ込めてラップする。`currentTime` は
/// CADisplayLink ではなく Timer（0.25秒間隔）で定期更新し、再生バー・
/// セグメントハイライトの UI から参照される。
@MainActor
@Observable
final class AudioPlaybackController: NSObject {

    /// 再生位置の表示更新間隔。
    private static let timeUpdateInterval: TimeInterval = 0.25

    /// - Note: セット可能なのは自身のみ（`private(set)`）。delegate コールバックが
    ///   古い/無関係な `AVAudioPlayer` インスタンスからの通知かどうかを `===` で
    ///   判定できるよう、テストからは `@testable import` で読み取り専用アクセスする。
    private(set) var player: AVAudioPlayer?
    private var timer: Timer?

    /// 現在の再生位置（秒）。
    private(set) var currentTime: TimeInterval = 0
    /// 音声の総時間（秒）。ロード前・失敗時は 0。
    private(set) var duration: TimeInterval = 0
    /// 再生中かどうか。
    private(set) var isPlaying = false
    /// `load` / `play` で発生した直近のエラー。UI からポーリングして表示する。
    private(set) var playbackError: Error?

    override init() {
        super.init()
    }

    // Note: Timer(target: self, ...) は self を強参照するため、repeats タイマーが
    // 生きている間 deinit は呼ばれない。画面離脱時は View 側の `onDisappear` で
    // 明示的に `stop()` を呼び、タイマーを invalidate してもらうことを前提とする。

    /// 音声ファイルをロードする。既存の再生・タイマーは停止される。
    /// - Note: 失敗時は `playbackError` にエラーを記録し、`duration` は 0 のままとなる。
    func load(url: URL) {
        stop()
        playbackError = nil
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            newPlayer.delegate = self
            newPlayer.prepareToPlay()
            player = newPlayer
            duration = newPlayer.duration
            currentTime = 0
        } catch {
            player = nil
            duration = 0
            currentTime = 0
            playbackError = error
        }
    }

    /// 再生を開始する（一時停止していた位置から再開）。
    /// - Note: `AVAudioPlayer.play()` が失敗（出力デバイス確保失敗等）した場合は
    ///   `isPlaying` を `false` のままにし、タイマーも開始せず `playbackError` に記録する。
    func play() {
        guard let player else { return }
        guard player.play() else {
            isPlaying = false
            playbackError = AudioPlaybackError.playFailed
            return
        }
        isPlaying = true
        startTimer()
    }

    /// 再生を一時停止する。位置は保持される。
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    /// 再生中なら一時停止、それ以外なら再生する。
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// 指定秒数へシークする（0...duration にクランプ）。再生状態は変えない。
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// 指定秒数へシークしたうえで再生を開始する（セグメント行クリック用）。
    func seekAndPlay(to time: TimeInterval) {
        seek(to: time)
        play()
    }

    /// 再生を止めてプレイヤーを解放する（画面離脱時・再ロード前に使う）。
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        stopTimer()
        currentTime = 0
        duration = 0
    }

    private func startTimer() {
        stopTimer()
        // Timer(target:selector:) + @objc 経由にすることで、Sendable クロージャに
        // MainActor 隔離の self を捕捉する際の並行性チェックを回避する
        // （Timer は RunLoop.main の .common モードで駆動されるため実質 MainActor 安全）。
        let newTimer = Timer(
            timeInterval: Self.timeUpdateInterval,
            target: self,
            selector: #selector(handleTimerTick),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    @objc private func handleTimerTick() {
        guard let player else { return }
        currentTime = player.currentTime
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackController: AVAudioPlayerDelegate {
    /// 再生が終了した（正常終了 or 中断）ときに呼ばれる。
    /// - Note: `flag == false`（正常終了しなかった）場合は `duration` へスキップせず、
    ///   実際に停止した位置（`player.currentTime`）を反映する。
    /// - Note: `player`（`AVAudioPlayer`、非 Sendable）自体を `@MainActor` の Task へ
    ///   キャプチャさせると "sending risks data race" になるため、Task に渡す前に
    ///   `ObjectIdentifier`（Sendable）と `currentTime`（Double）へ変換しておく。
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let notifiedPlayerID = ObjectIdentifier(player)
        let lastKnownPosition = player.currentTime
        Task { @MainActor [weak self] in
            guard let self,
                  let current = self.player,
                  ObjectIdentifier(current) == notifiedPlayerID else { return }
            self.isPlaying = false
            self.stopTimer()
            self.currentTime = flag ? self.duration : lastKnownPosition
        }
    }

    /// 再生中にデコードエラーが発生した（破損・途中欠損したファイル等）ときに呼ばれる。
    /// - Note: このコールバックが未実装だと `audioPlayerDidFinishPlaying` も呼ばれず、
    ///   `isPlaying` が `true` のまま・タイマーが動き続けたまま UI が固まる。
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let notifiedPlayerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self,
                  let current = self.player,
                  ObjectIdentifier(current) == notifiedPlayerID else { return }
            self.isPlaying = false
            self.stopTimer()
            self.playbackError = error
        }
    }
}

// MARK: - セグメント同期（AVAudioPlayer 非依存の純粋関数）

extension AudioPlaybackController {
    /// 現在の再生時刻に対応するセグメントの index を返す（ハイライト用）。
    ///
    /// `segments` は start 昇順でソート済みであることを前提とする（`SessionModel.sortedSegments`）。
    /// 「直近に開始したセグメント」を現在セグメントとみなすため、セグメント間の無音区間でも
    /// 直前のセグメントがハイライトされ続ける（字幕追従に近い挙動）。
    /// - Returns: `time` がまだ最初のセグメントの開始前なら `nil`。
    ///
    /// AVAudioPlayer に依存しない純粋関数のため MainActor 隔離を外し、
    /// テストから直接（`await` なしで）呼べるようにしてある。
    nonisolated static func segmentIndex(at time: TimeInterval, in segments: [SegmentTimeRange]) -> Int? {
        var result: Int?
        for (index, segment) in segments.enumerated() {
            if segment.start <= time {
                result = index
            } else {
                break
            }
        }
        return result
    }
}
