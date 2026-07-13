import Foundation
@testable import SokkiKit

/// テスト用の話者分離エンジン。実 embedding 付きの `DiarizationResult` を返せる。
/// 実 FluidAudio モデルを必要とせず、パイプライン結合テストで差し替えて使う。
actor MockDiarizationEngine: DiarizationEngine {
    private(set) var isReady: Bool
    private var result: DiarizationResult
    private let errorToThrow: (any Error)?

    private(set) var prepareCallCount = 0
    private(set) var diarizeCallCount = 0

    init(
        result: DiarizationResult = DiarizationResult(segments: [], numberOfSpeakers: 0),
        isReady: Bool = true,
        errorToThrow: (any Error)? = nil
    ) {
        self.result = result
        self.isReady = isReady
        self.errorToThrow = errorToThrow
    }

    func setResult(_ result: DiarizationResult) {
        self.result = result
    }

    func prepare() async throws {
        prepareCallCount += 1
        if let errorToThrow { throw errorToThrow }
        isReady = true
    }

    func diarize(audioArray: [Float]) async throws -> DiarizationResult {
        diarizeCallCount += 1
        if let errorToThrow { throw errorToThrow }
        return result
    }
}

enum MockDiarizationError: Error {
    case forced
}

/// 256 次元の L2 正規化 embedding を生成するテストヘルパー。
/// `seed` を変えると別方向のベクトルになり、別話者として扱える。
func makeNormalizedEmbedding(seed: Float, dimension: Int = 256) -> [Float] {
    let raw = (0..<dimension).map { i in sin(seed + Float(i) * 0.01) }
    return l2Normalize(raw)
}
