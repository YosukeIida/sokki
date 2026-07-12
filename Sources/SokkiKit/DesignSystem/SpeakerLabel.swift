import Foundation

/// 話者ラベルのロケール追従表示名。
///
/// 設計判断: String Catalog / `Localizable.strings` などのリソースは使わず、コード内の
/// ロケール判定で日本語／英語を出し分ける。SPM と xcodegen の二重リソースパイプラインを
/// 避けるためのメイン設計判断であり、本格的なローカライズを行う段階でこの実装を
/// リソースベース（String Catalog 等）へ置き換える。
enum SpeakerLabel {
    /// 話者インデックス（0 始まり）からロケール追従の表示名を返す。
    /// - 日本語（language code `"ja"`）: 「話者A」「話者B」…
    /// - それ以外: 「Speaker A」「Speaker B」…
    ///
    /// - Parameters:
    ///   - index: 0 始まりの話者番号。
    ///   - locale: 判定に用いるロケール。既定は `.current`。テストではここへ明示注入して
    ///     グローバル状態に依存しない検証を行う。
    static func displayName(index: Int, locale: Locale = .current) -> String {
        let letters = letterCode(for: index)
        if locale.language.languageCode?.identifier == "ja" {
            return "話者\(letters)"
        }
        return "Speaker \(letters)"
    }

    /// インデックスを A〜Z の英大文字コードへ変換する。
    /// 0→"A"、25→"Z"、26→"AA"、27→"AB"… の Excel 列名方式（bijective base-26）。
    /// 負値は "A" にフォールバックする（`index` は 0 以上を想定）。
    private static func letterCode(for index: Int) -> String {
        guard index >= 0 else { return "A" }
        var n = index
        var result = ""
        repeat {
            let remainder = n % 26
            let scalar = UnicodeScalar(UInt8(65 + remainder))   // 65 = "A"
            result = String(Character(scalar)) + result
            n = n / 26 - 1
        } while n >= 0
        return result
    }
}
