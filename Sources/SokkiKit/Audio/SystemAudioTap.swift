import AVFoundation
import CoreAudio

/// システム音声キャプチャ（Core Audio Process Tap / macOS 14.2+）の生成失敗を表すエラー。
/// 失敗した Core Audio API の `OSStatus` を保持し、呼び出し元がログ・利用者通知に使えるようにする。
enum SystemAudioTapError: Error, Equatable {
    case alreadyStarted
    case processTapCreationFailed(OSStatus)
    /// 既定システム出力デバイスの解決（デバイス取得または UID 読取）に失敗。
    /// `defaultSystemOutputDeviceUID()` が両ステップを 1 メソッドに集約するため、
    /// デバイス未検出と UID 読取失敗はこの 1 ケースに統合している。
    case defaultOutputDeviceUnavailable(OSStatus)
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

/// 生の Core Audio C API を注入可能にする薄いラッパー。実装（`DefaultCoreAudioTapSystem`）は
/// C API へ委譲し、テストは呼び出し順序と各段階の失敗を制御するフェイクを注入する。
/// これにより `SystemAudioTap` の生成／解放シーケンスを Core Audio 実機なしで検証できる。
protocol CoreAudioTapSystem: Sendable {
    func createProcessTap(_ description: CATapDescription) -> (status: OSStatus, tapID: AudioObjectID)
    func defaultSystemOutputDeviceUID() -> (status: OSStatus, uid: String?)
    func tapStreamFormat(tapID: AudioObjectID) -> (status: OSStatus, format: AVAudioFormat?)
    func createAggregateDevice(_ description: CFDictionary) -> (status: OSStatus, deviceID: AudioObjectID)
    func createIOProcID(
        deviceID: AudioObjectID,
        queue: DispatchQueue,
        ioBlock: @escaping AudioDeviceIOBlock
    ) -> (status: OSStatus, procID: AudioDeviceIOProcID?)
    func startDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) -> OSStatus
    func stopDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID)
    func destroyIOProcID(deviceID: AudioObjectID, procID: AudioDeviceIOProcID)
    func destroyAggregateDevice(deviceID: AudioObjectID)
    func destroyProcessTap(tapID: AudioObjectID)
}

/// Core Audio Process Tap によるシステム音声キャプチャの実プラミング。
///
/// tap 生成 → aggregate device 生成 → IOProc 起動 → 解放（逆順）の全ライフサイクルを担う。
/// 生の Core Audio 呼び出しは `CoreAudioTapSystem` に委譲する（テスト注入のため）。
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

    private let coreAudio: CoreAudioTapSystem
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

    init(coreAudio: CoreAudioTapSystem = DefaultCoreAudioTapSystem()) {
        self.coreAudio = coreAudio
    }

    deinit {
        stop()
    }

    // MARK: - SystemAudioTapping

    func start(onSamples: @escaping @Sendable ([Float], Date) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }

        // 二重 start はリソースリークになるため拒否する（呼び出し側は stop してから start する契約）。
        guard ioContext == nil,
              aggregateDeviceID == AudioObjectID(kAudioObjectUnknown),
              tapID == AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTapError.alreadyStarted
        }

        // 1. tap 記述（全プロセスのステレオグローバルタップ。除外プロセスは無し）
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true
        tapDescription.name = "sokki System Audio Tap"

        // 2. process tap 生成
        let (tapStatus, newTapID) = coreAudio.createProcessTap(tapDescription)
        guard tapStatus == noErr, newTapID != AudioObjectID(kAudioObjectUnknown) else {
            throw SystemAudioTapError.processTapCreationFailed(tapStatus)
        }

        do {
            // 3. 既定システム出力デバイスの UID を読み取る（aggregate の main sub-device 用）
            let (uidStatus, outputUID) = coreAudio.defaultSystemOutputDeviceUID()
            guard uidStatus == noErr, let outputUID else {
                throw SystemAudioTapError.defaultOutputDeviceUnavailable(uidStatus)
            }

            // 4. aggregate device 記述辞書を構築（tap の UUID 文字列を使う。tapID 整数ではない）
            let aggregateUID = UUID().uuidString
            let description = Self.makeAggregateDeviceDescription(
                tapUUID: tapDescription.uuid,
                outputDeviceUID: outputUID,
                aggregateUID: aggregateUID
            )

            // 5. tap のストリームフォーマットを読む（辞書構築の後・aggregate 生成の前）
            let (formatStatus, tapFormat) = coreAudio.tapStreamFormat(tapID: newTapID)
            guard formatStatus == noErr else {
                throw SystemAudioTapError.tapStreamFormatUnavailable(formatStatus)
            }
            guard let tapFormat else {
                throw SystemAudioTapError.tapStreamFormatInvalid
            }

            // 6. aggregate device 生成
            let (aggStatus, newAggregateID) = coreAudio.createAggregateDevice(description as CFDictionary)
            guard aggStatus == noErr, newAggregateID != AudioObjectID(kAudioObjectUnknown) else {
                throw SystemAudioTapError.aggregateDeviceCreationFailed(aggStatus)
            }

            do {
                // 7. 変換器（tapFormat → 16kHz mono）と IO コンテキスト
                let targetFormat = AudioSampleConversion.makeTargetFormat()
                guard let converter = AVAudioConverter(from: tapFormat, to: targetFormat) else {
                    throw SystemAudioTapError.converterUnavailable
                }
                let context = IOContext(
                    converter: converter,
                    tapFormat: tapFormat,
                    targetFormat: targetFormat,
                    onSamples: onSamples
                )

                // 8. IOProc 登録（専用 IO キュー）
                let (procStatus, newProcID) = coreAudio.createIOProcID(
                    deviceID: newAggregateID,
                    queue: ioQueue
                ) { _, inInputData, _, _, _ in
                    context.process(inInputData)
                }
                guard procStatus == noErr, let procID = newProcID else {
                    throw SystemAudioTapError.ioProcCreationFailed(procStatus)
                }

                do {
                    // 9. 開始
                    let startStatus = coreAudio.startDevice(deviceID: newAggregateID, procID: procID)
                    guard startStatus == noErr else {
                        throw SystemAudioTapError.deviceStartFailed(startStatus)
                    }

                    // 成功: ハンドルを保持
                    tapID = newTapID
                    aggregateDeviceID = newAggregateID
                    deviceProcID = procID
                    ioContext = context
                } catch {
                    coreAudio.destroyIOProcID(deviceID: newAggregateID, procID: procID)
                    throw error
                }
            } catch {
                coreAudio.destroyAggregateDevice(deviceID: newAggregateID)
                throw error
            }
        } catch {
            // tap 以降で失敗した場合は tap を解放して巻き戻す
            coreAudio.destroyProcessTap(tapID: newTapID)
            throw error
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }

        // 解放は生成の逆順: Stop → DestroyIOProcID → DestroyAggregateDevice → DestroyProcessTap
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown), let procID = deviceProcID {
            coreAudio.stopDevice(deviceID: aggregateDeviceID, procID: procID)
            coreAudio.destroyIOProcID(deviceID: aggregateDeviceID, procID: procID)
        }
        if aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) {
            coreAudio.destroyAggregateDevice(deviceID: aggregateDeviceID)
        }
        if tapID != AudioObjectID(kAudioObjectUnknown) {
            coreAudio.destroyProcessTap(tapID: tapID)
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
}

/// `CoreAudioTapSystem` の実装。生の Core Audio C API へ委譲するだけの薄い層。
/// 状態を持たない値型なので `Sendable`。
struct DefaultCoreAudioTapSystem: CoreAudioTapSystem {

    func createProcessTap(_ description: CATapDescription) -> (status: OSStatus, tapID: AudioObjectID) {
        var tapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        return (status, tapID)
    }

    func defaultSystemOutputDeviceUID() -> (status: OSStatus, uid: String?) {
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
            return (status == noErr ? OSStatus(kAudioHardwareBadDeviceError) : status, nil)
        }

        var uidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString = "" as CFString
        var uidSize = UInt32(MemoryLayout<CFString>.size)
        status = withUnsafeMutablePointer(to: &uid) { pointer in
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, pointer)
        }
        guard status == noErr else { return (status, nil) }
        return (noErr, uid as String)
    }

    func tapStreamFormat(tapID: AudioObjectID) -> (status: OSStatus, format: AVAudioFormat?) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr else { return (status, nil) }
        return (noErr, AVAudioFormat(streamDescription: &asbd))
    }

    func createAggregateDevice(_ description: CFDictionary) -> (status: OSStatus, deviceID: AudioObjectID) {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description, &deviceID)
        return (status, deviceID)
    }

    func createIOProcID(
        deviceID: AudioObjectID,
        queue: DispatchQueue,
        ioBlock: @escaping AudioDeviceIOBlock
    ) -> (status: OSStatus, procID: AudioDeviceIOProcID?) {
        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue, ioBlock)
        return (status, procID)
    }

    func startDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) -> OSStatus {
        AudioDeviceStart(deviceID, procID)
    }

    func stopDevice(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) {
        AudioDeviceStop(deviceID, procID)
    }

    func destroyIOProcID(deviceID: AudioObjectID, procID: AudioDeviceIOProcID) {
        AudioDeviceDestroyIOProcID(deviceID, procID)
    }

    func destroyAggregateDevice(deviceID: AudioObjectID) {
        AudioHardwareDestroyAggregateDevice(deviceID)
    }

    func destroyProcessTap(tapID: AudioObjectID) {
        AudioHardwareDestroyProcessTap(tapID)
    }
}
