import SwiftUI
import SwiftData

public struct SettingsView: View {
    public init() {}

    @Query private var settingsArray: [AppSettingsModel]
    @Environment(\.modelContext) private var ctx
    @AppStorage("sokki.appearance") private var appearance: SokkiAppearance = .system

    private var settings: AppSettingsModel {
        if let s = settingsArray.first { return s }
        let s = AppSettingsModel()
        ctx.insert(s)
        return s
    }

    public var body: some View {
        TabView {
            transcriptionTab
                .tabItem { Label("文字起こし", systemImage: "waveform") }
            speakerTab
                .tabItem { Label("話者分離", systemImage: "person.2") }
            llmTab
                .tabItem { Label("LLM", systemImage: "brain") }
            appearanceTab
                .tabItem { Label("外観", systemImage: "paintpalette") }
        }
        .frame(width: 480, height: 320)
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

    /// SpeechAnalyzer（macOS 26+ の Speech 新 API）が利用可能か。
    private var isSpeechAnalyzerAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private var transcriptionTab: some View {
        Form {
            Section("エンジン") {
                Picker("文字起こしエンジン", selection: Binding(
                    get: { settings.transcriptionEngine },
                    set: { settings.transcriptionEngine = $0 }
                )) {
                    Text("WhisperKit").tag("whisperkit")
                    Text("Apple SpeechAnalyzer").tag("speechAnalyzer")
                }
                .disabled(!isSpeechAnalyzerAvailable)
                if !isSpeechAnalyzerAvailable {
                    Text("Apple SpeechAnalyzer は macOS 26 以降で利用できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("エンジンの切り替えはアプリの再起動後に反映されます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Whisper モデル") {
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
