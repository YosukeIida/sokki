import SwiftUI
import SwiftData

public struct SettingsView: View {
    public init() {}

    @Query private var settingsArray: [AppSettingsModel]
    @Environment(\.modelContext) private var ctx
    @Environment(AppDependencyContainer.self) private var deps
    @AppStorage("sokki.appearance") private var appearance: SokkiAppearance = .system

    // MARK: - 翻訳 API キー入力（TASK-23）
    //
    // キー文字列はここにしか一時滞留しない（保存後・別プロバイダ選択後に必ず空へ戻す）。
    // 保存済みキーは再表示しない — 表示できるのは「設定済みか否か」のみ。
    @State private var apiKeyInput: String = ""
    @State private var apiKeyErrorMessage: String?

    private var settings: AppSettingsModel {
        if let s = settingsArray.first { return s }
        let s = AppSettingsModel()
        ctx.insert(s)
        return s
    }

    private var translationSnapshot: TranslationSettingsSnapshot {
        TranslationSettingsSnapshot(settings)
    }

    public var body: some View {
        TabView {
            transcriptionTab
                .tabItem { Label("文字起こし", systemImage: "waveform") }
            speakerTab
                .tabItem { Label("話者分離", systemImage: "person.2") }
            translationTab
                .tabItem { Label("翻訳", systemImage: "character.bubble") }
            llmTab
                .tabItem { Label("LLM", systemImage: "brain") }
            appearanceTab
                .tabItem { Label("外観", systemImage: "paintpalette") }
        }
        .frame(width: 480, height: 320)
        // 翻訳設定が変わるたびに Coordinator を再評価する（fail-closed に乗る）。
        .onChange(of: translationSnapshot) { _, snapshot in
            Task { await deps.reconcileTranslation(snapshot) }
        }
        // プロバイダ切り替え時、入力途中のキー文字列を別プロバイダの account へ
        // 誤って保存しないよう必ずクリアする。
        .onChange(of: settings.translationProvider) { _, _ in
            apiKeyInput = ""
            apiKeyErrorMessage = nil
        }
    }

    private var appearanceTab: some View {
        Form {
            Section("外観") {
                Picker("テーマ", selection: $appearance) {
                    ForEach(SokkiAppearance.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding()
    }

    private var transcriptionTab: some View {
        Form {
            Section("エンジン") {
                Picker("Whisper モデル", selection: Binding(
                    get: { settings.whisperModelVariant },
                    set: { settings.whisperModelVariant = $0 }
                )) {
                    Text("自動（推奨）").tag("")
                    Text("large-v3-turbo").tag("openai_whisper-large-v3_turbo")
                    Text("large-v3").tag("openai_whisper-large-v3")
                    Text("large-v3-v20240930-turbo").tag("openai_whisper-large-v3-v20240930_turbo")
                    Text("medium").tag("openai_whisper-medium")
                    Text("small").tag("openai_whisper-small")
                }
            }
        }
        .padding()
    }

    private var speakerTab: some View {
        Form {
            Section("話者分離") {
                Toggle("話者分離を有効にする", isOn: Binding(
                    get: { settings.diarizationEnabled },
                    set: { settings.diarizationEnabled = $0 }
                ))
                Stepper("話者数: \(settings.numberOfSpeakers == 0 ? "自動" : "\(settings.numberOfSpeakers)人")",
                        value: Binding(
                            get: { settings.numberOfSpeakers },
                            set: { settings.numberOfSpeakers = $0 }
                        ),
                        in: 0...10
                )
            }
            Section("声紋照合") {
                LabeledContent("照合閾値") {
                    HStack {
                        Slider(value: Binding(
                            get: { Double(settings.embeddingMatchThreshold) },
                            set: { settings.embeddingMatchThreshold = Float($0) }
                        ), in: 0.6...0.95, step: 0.01)
                        Text(String(format: "%.2f", settings.embeddingMatchThreshold))
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }
        }
        .padding()
    }

    private var translationTab: some View {
        Form {
            Section("翻訳") {
                Toggle("翻訳を有効にする", isOn: Binding(
                    get: { settings.translationEnabled },
                    set: { settings.translationEnabled = $0 }
                ))
                Picker("プロバイダ", selection: Binding(
                    get: { TranslationProviderKind(rawValue: settings.translationProvider) ?? .auto },
                    set: { settings.translationProvider = $0.rawValue }
                )) {
                    Text("自動").tag(TranslationProviderKind.auto)
                    Text("Apple（オンデバイス）").tag(TranslationProviderKind.apple)
                    Text("DeepL（BYO・要キー）").tag(TranslationProviderKind.deepL)
                    Text("Gemini Live（BYO・実験的）").tag(TranslationProviderKind.geminiLive)
                }
                .disabled(!settings.translationEnabled)
                Picker("対象言語", selection: Binding(
                    get: { settings.translationTargetLanguage },
                    set: { settings.translationTargetLanguage = $0 }
                )) {
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                    Text("中国語（簡体字）").tag("zh-Hans")
                    Text("韓国語").tag("ko")
                    Text("スペイン語").tag("es")
                    Text("フランス語").tag("fr")
                }
                .disabled(!settings.translationEnabled)

                if let warning = byoWarning {
                    Label(warning, systemImage: "cloud.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if requiresAPIKey {
                Section("API キー（\(byoDisplayName(selectedProviderKind))）") {
                    if hasStoredAPIKey {
                        Label("設定済み", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("API キー（保存後は再表示されません）", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("保存") { saveAPIKey() }
                            .disabled(apiKeyInput.isEmpty)
                        Button("削除", role: .destructive) { deleteAPIKey() }
                            .disabled(!hasStoredAPIKey)
                    }
                    if let apiKeyErrorMessage {
                        Text(apiKeyErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            Section("プライバシー") {
                Toggle("プライバシーモード", isOn: Binding(
                    get: { settings.privacyModeEnabled },
                    set: { settings.privacyModeEnabled = $0 }
                ))
                Text("ON の場合、オンデバイス翻訳（Apple）が対応していない言語ペアでもクラウドへ自動フォールバックしません。BYO プロバイダを明示的に選択した場合のみクラウド送信を許可します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    /// BYO プロバイダを明示選択している場合の注意書き。
    private var byoWarning: String? {
        let kind = TranslationProviderKind(rawValue: settings.translationProvider) ?? .auto
        guard settings.translationEnabled, kind.isOnDeviceImplied == false, kind != .auto else { return nil }
        return "\(byoDisplayName(kind)) は API キーが必要で、音声のテキストがクラウドへ送信されます。"
    }

    private func byoDisplayName(_ kind: TranslationProviderKind) -> String {
        switch kind {
        case .deepL: return "DeepL"
        case .geminiLive: return "Gemini Live"
        case .googleCloudV3: return "Google Cloud Translation"
        case .apple, .auto: return kind.rawValue
        }
    }

    // MARK: - 翻訳 API キー（TASK-23 / Keychain）

    private var selectedProviderKind: TranslationProviderKind {
        TranslationProviderKind(rawValue: settings.translationProvider) ?? .auto
    }

    /// 選択中プロバイダが BYO（クラウド送信・要キー）か。`auto` はここでは対象外
    /// （実際に解決される具体種別は録音時までわからないため、明示選択時のみ UI を出す）。
    private var requiresAPIKey: Bool {
        selectedProviderKind.isOnDeviceImplied == false && selectedProviderKind != .auto
    }

    private var hasStoredAPIKey: Bool {
        deps.keychainService.hasKey(for: selectedProviderKind.rawValue)
    }

    private func saveAPIKey() {
        do {
            try deps.keychainService.store(apiKeyInput, for: selectedProviderKind.rawValue)
            apiKeyInput = ""
            apiKeyErrorMessage = nil
            Task { await deps.reconcileTranslation(translationSnapshot) }
        } catch {
            // キー文字列そのものはエラーメッセージに含めない。
            apiKeyErrorMessage = "保存に失敗しました。もう一度お試しください。"
        }
    }

    private func deleteAPIKey() {
        do {
            try deps.keychainService.delete(for: selectedProviderKind.rawValue)
            apiKeyInput = ""
            apiKeyErrorMessage = nil
            Task { await deps.reconcileTranslation(translationSnapshot) }
        } catch {
            apiKeyErrorMessage = "削除に失敗しました。もう一度お試しください。"
        }
    }

    private var llmTab: some View {
        Form {
            Section("OpenAI 互換エンドポイント") {
                TextField("Base URL", text: Binding(
                    get: { settings.llmBaseURL ?? "" },
                    set: { settings.llmBaseURL = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("API Key（不要な場合は空欄）", text: Binding(
                    get: { settings.llmApiKey ?? "" },
                    set: { settings.llmApiKey = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("モデル名", text: Binding(
                    get: { settings.llmModel ?? "" },
                    set: { settings.llmModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }
}
