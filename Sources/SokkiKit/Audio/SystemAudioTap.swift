import AVFoundation
import CoreAudio

/// システム音声キャプチャ（Core Audio Process Tap / macOS 14.2+）の生成失敗を表すエラー。
/// 失敗した Core Audio API の `OSStatus` を保持し、呼び出し元がログ・利用者通知に使えるようにする。
enum SystemAudioTapError: Error {
    case processTapCreationFailed(OSStatus)
    case defaultOutputDeviceUnavailable(OSStatus)
    case outputDeviceUIDUnavailable(OSStatus)
    case tapStreamFormatUnavailable(OSStatus)
    case tapStreamFormatInvalid
    case aggregateDeviceCreationFailed(OSStatus)
    case converterUnavailable
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
}

/// システム音声キャプチャの抽象。実装（`SystemAudioTap`）は Core Audio Process Tap を、
/// テストはモックを注入する。`start` の `onSamples` は専用 IO キュー上で 16kHz mono の
/// `[Float]` とキャプチャ時刻を渡す（アクター境界を越えるのは `[Float]` のみ）。
protocol SystemAudioTapping: Sendable {
    /// キャプチャを開始する。`onSamples` は専用のリアルタイム IO キューから呼ばれる。
    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws
    /// キャプチャを停止し、tap / aggregate device / IOProc を解放する。冪等。
    func stop()
}

/// Core Audio Process Tap によるシステム音声キャプチャの実プラミング。
///
/// tap 生成 → aggregate device 生成 → IOProc 起動 → 解放（逆順）の全ライフサイクルを担う。
/// IO ブロックはアクター（`AudioCaptureManager`）を捕捉せず、`IOContext`（変換器・フォーマット・
/// yield クロージャを閉じ込めた不変オブジェクト）だけを捕捉する。`AVAudioConverter` は IO キューに
/// 閉じ込め、アクター境界を越えるのは変換後の `[Float]` のみ。
///
/// `start` / `stop` はアクターから直列に呼ばれるが、`@unchecked Sendable` を honest に満たすため
/// 内部状態を `NSLock` で保護する。
final class SystemAudioTap: SystemAudioTapping, @unchecked Sendable {

    /// IO キュー上で走る不変コンテキスト。変換器とフォーマットと yield 先を閉じ込める。
    /// すべてのアクセスが単一の直列 IO キュー上で行われるため `@unchecked Sendable`。
    private final class IOContext: @unchecked Sendable {
        let converter: AVAudioConverter
        let tapFormat: AVAudioFormat
        let targetFormat: AVAudioFormat
        let onSamples: @Sendable ([Float], Date) -> Void

        init(
            converter: AVAudioConverter,
            tapFormat: AVAudioFormat,
            targetFormat: AVAudioFormat,
            onSamples: @escaping @Sendable ([Float], Date) -> Void
        ) {
            self.converter = converter
            self.tapFormat = tapFormat
            self.targetFormat = targetFormat
            self.onSamples = onSamples
        }

        /// IOProc から渡される tap のバッファリストを 16kHz mono へ変換して yield する。
        func process(_ bufferList: UnsafePointer<AudioBufferList>) {
            guard let inBuffer = AVAudioPCMBuffer(
                pcmFormat: tapFormat,
                bufferListNoCopy: bufferList,
                deallocator: nil
            ) else { return }
            guard inBuffer.frameLength > 0 else { return }
            guard let outBuffer = AudioSampleConversion.convertToBuffer(
                inBuffer, using: converter, to: targetFormat
            ) else { return }
            let samples = AudioSampleConversion.samples(from: outBuffer)
            guard !samples.isEmpty else { return }
            onSamples(samples, Date())
        }
    }

    private let lock = NSLock()
    private let ioQueue = DispatchQueue(
        label: "com.yosukeiida.sokki.SystemAudioTap.io",
        qos: .userInitiated
    )

    // 以下は lock で保護する解放対象のハンドル群。
    private var tapID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var deviceProcID: AudioDeviceIOProcID?
    private var ioContext: IOContext?

    init() {}

    deinit {
        stop()
    }

    // MARK: - SystemAudioTapping

    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        // 1. tap 記述（全プロセスのステレオグローバルタップ。除外プロセスは無し）
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.name = "sokki System Audio Tap"

        // 2. process tap 生成
        var newTapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr else {
            throw SystemAudioTapError.processTapCreationFailed(status)
        }

        do {
            // 3. 既定システム出力デバイスの UID を読み取る（aggregate の main sub-device 用）
            let outputUID = try Self.readDefaultSystemOutputDeviceUID()

            // 4. aggregate device 記述辞書を構築（tap の UUID 文字列を使う。tapID 整数ではない）
            let aggregateUID = UUID().uuidString
            let description = Self.makeAggregateDeviceDescription(
                tapUUID: tapDescription.uuid,
                outputDeviceUID: outputUID,
                aggregateUID: aggregateUID
            )

            // 5. tap のストリームフォーマットを読む（辞書構築の後・aggregate 生成の前）
            let tapFormat = try Self.readTapStreamFormat(tapID: newTapID)

            // 6. aggregate device 生成
            var newAggregateID = AudioObjectID(kAudioObjectUnknown)
            status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateID)
            guard status == noErr else {
                throw SystemAudioTapError.aggregateDeviceCreationFailed(status)
            }

            // 7. 変換器（tapFormat → 16kHz mono）と IO コンテキスト
            let targetFormat = AudioSampleConversion.makeTargetFormat()
            guard let converter = AVAudioConverter(from: tapFormat, to: targetFormat) else {
                AudioHardwareDestroyAggregateDevice(newAggregateID)
                throw SystemAudioTapError.converterUnavailable
            }
            let context = IOContext(
                converter: converter,
                tapFormat: tapFormat,
                targetFormat: targetFormat,
                onSamples: onSamples
            )

            // 8. IOProc 登録（専用 IO キュー）
            var newProcID: AudioDeviceIOProcID?
            status = AudioDeviceCreateIOProcIDWithBlock(
                &newProcID, newAggregateID, ioQueue
            ) { _, inInputData, _, _, _ in
                context.process(inInputData)
            }
            guard status == noErr, let procID = newProcID else {
                AudioHardwareDestroyAggregateDevice(newAggregateID)
                throw SystemAudioTapError.ioProcCreationFailed(status)
            }

            // 9. 開始
            status = AudioDeviceStart(newAggregateID, procID)
            guard status == noErr else {
                AudioDeviceDestroyIOProcID(newAggregateID, procID)
                AudioHardwareDestroyAggregateDevice(newAggregateID)
                throw SystemAudioTapError.deviceStartFailed(status)
            }

            // 成功: ハンドルを保持
            tapID = newTapID
            aggregateDeviceID = newAggregateID
            deviceProcID = procID
            ioContext = context
        } catch {
            // tap 以降で失敗した場合は tap を解放して巻き戻す
            AudioHardwareDestroyProcessTap(newTapID)
            throw error
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        // 解放は生成の逆順: Stop → DestroyIOProcID → DestroyAggregateDevice → DestroyProcessTap
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown), let procID = deviceProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        deviceProcID = nil
        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        ioContext = nil
    }

    // MARK: - Aggregate device description (pure / testable)

    /// aggregate device 記述辞書を組み立てる純粋関数。単体テスト対象。
    ///
    /// - `kAudioSubTapUIDKey` には tap 記述の `uuid.uuidString`（tapID 整数ではない）。
    /// - 出力デバイス UID は `MainSubDevice` と `SubDeviceList[0]` の**両方**に設定する。
    /// - `TapAutoStart` / `IsPrivate` / drift 補償を有効化する。
    static func makeAggregateDeviceDescription(
        tapUUID: UUID,
        outputDeviceUID: String,
        aggregateUID: String
    ) -> [String: Any] {
        [
            kAudioAggregateDeviceNameKey as String: "sokki System Capture",
            kAudioAggregateDeviceUIDKey as String: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey as String: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey as String: true,
            kAudioAggregateDeviceIsStackedKey as String: false,
            kAudioAggregateDeviceTapAutoStartKey as String: true,
            kAudioAggregateDeviceSubDeviceListKey as String: [
                [kAudioSubDeviceUIDKey as String: outputDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey as String: [
                [
                    kAudioSubTapDriftCompensationKey as String: true,
                    kAudioSubTapUIDKey as String: tapUUID.uuidString,
                ]
            ],
        ]
    }

    // MARK: - Core Audio property helpers

    /// 既定のシステム出力デバイスの UID を読む。
    private static func readDefaultSystemOutputDeviceUID() throws -> String {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var deviceSize = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &deviceAddress, 0, nil, &deviceSize, &deviceID
        )
        guard status == noErr, deviceID != AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTapError.defaultOutputDeviceUnavailable(status)
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, ptr)
        }
        guard status == noErr else {
            throw SystemAudioTapError.outputDeviceUIDUnavailable(status)
        }
        return uid as String
    }

    /// tap のストリームフォーマット（`kAudioTapPropertyFormat`）を `AVAudioFormat` として読む。
    private static func readTapStreamFormat(tapID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else {
            throw SystemAudioTapError.tapStreamFormatUnavailable(status)
        }
        guard let format = AVAudioFormat(streamDescription: &asbd) else {
            throw SystemAudioTapError.tapStreamFormatInvalid
        }
        return format
    }
}
