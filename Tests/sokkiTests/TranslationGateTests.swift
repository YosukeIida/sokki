import Testing
@testable import SokkiKit

/// `docs/translation-architecture.md` §5 の真理値表（7 行）を全網羅する。
@Suite("TranslationGate 真理値表")
struct TranslationGateTests {

    private func ctx(
        enabled: Bool = true,
        privacy: Bool = false,
        onDevice: Bool = false,
        explicit: Bool = false,
        key: Bool = false
    ) -> TranslationGateContext {
        TranslationGateContext(
            translationEnabled: enabled,
            privacyModeEnabled: privacy,
            providerIsOnDevice: onDevice,
            isUserExplicitChoice: explicit,
            hasValidApiKey: key
        )
    }

    // 行1: translationEnabled=false → toggleOff（送信なし）
    @Test("行1: トグル OFF は toggleOff")
    func row1_toggleOff() {
        #expect(TranslationGate.evaluate(ctx(enabled: false)) == .denied(.toggleOff))
        // privacy/onDevice/key に依らず toggleOff が最優先。
        #expect(
            TranslationGate.evaluate(ctx(enabled: false, privacy: true, onDevice: true, key: true))
                == .denied(.toggleOff)
        )
    }

    // 行2: enabled=true, isOnDevice=true → allow（オンデバイス・送信なし）
    @Test("行2: オンデバイスは常に allow")
    func row2_onDeviceAllow() {
        #expect(TranslationGate.evaluate(ctx(privacy: true, onDevice: true)) == .allow)
        #expect(TranslationGate.evaluate(ctx(privacy: false, onDevice: true)) == .allow)
    }

    // 行3: privacy ON + BYO + 明示選択 + key あり → allow（オプトイン成立）
    @Test("行3: privacy ON + 明示 BYO + key あり は allow")
    func row3_privacyExplicitAllow() {
        #expect(
            TranslationGate.evaluate(ctx(privacy: true, onDevice: false, explicit: true, key: true))
                == .allow
        )
    }

    // 行4: privacy ON + BYO + 自動FB + key あり → privacyBlocksAutoCloud（越権）
    @Test("行4: privacy ON + 自動FB は privacyBlocksAutoCloud")
    func row4_privacyAutoBlocked() {
        #expect(
            TranslationGate.evaluate(ctx(privacy: true, onDevice: false, explicit: false, key: true))
                == .denied(.privacyBlocksAutoCloud)
        )
    }

    // 行5: privacy ON + BYO + key なし → missingApiKey（明示/自動を問わず key チェックが先）
    @Test("行5: privacy ON + key なし は missingApiKey")
    func row5_privacyMissingKey() {
        #expect(
            TranslationGate.evaluate(ctx(privacy: true, onDevice: false, explicit: true, key: false))
                == .denied(.missingApiKey)
        )
        #expect(
            TranslationGate.evaluate(ctx(privacy: true, onDevice: false, explicit: false, key: false))
                == .denied(.missingApiKey)
        )
    }

    // 行6: privacy OFF + BYO + key あり → allow
    @Test("行6: privacy OFF + key あり は allow")
    func row6_privacyOffAllow() {
        #expect(
            TranslationGate.evaluate(ctx(privacy: false, onDevice: false, explicit: false, key: true))
                == .allow
        )
    }

    // 行7: privacy OFF + BYO + key なし → missingApiKey
    @Test("行7: privacy OFF + key なし は missingApiKey")
    func row7_privacyOffMissingKey() {
        #expect(
            TranslationGate.evaluate(ctx(privacy: false, onDevice: false, explicit: false, key: false))
                == .denied(.missingApiKey)
        )
    }
}
