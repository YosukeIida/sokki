import SwiftUI

struct LiveTranscriptView: View {
    let segments: [TranscriptSegmentViewModel]
    let hypothesis: String

    @Environment(\.sokkiTokens) private var tokens

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // 確定（Confirmed）: 黒／primary テキスト色
                    ForEach(segments) { seg in
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = seg.speakerName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(tokens.faint)
                            }
                            Text(seg.text)
                                .font(.body)
                                .foregroundStyle(tokens.text)
                                .textSelection(.enabled)
                        }
                        .id(seg.id)
                    }

                    // 未確定（Hypothesis）: 灰／muted テキスト色。まだ揺れる可能性を示す。
                    if !hypothesis.isEmpty {
                        Text(hypothesis)
                            .font(.body)
                            .foregroundStyle(tokens.muted)
                            .id("hypothesis")
                    }
                }
                .padding()
            }
            .onChange(of: segments.count) {
                if let last = segments.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: hypothesis) {
                if !hypothesis.isEmpty {
                    withAnimation { proxy.scrollTo("hypothesis", anchor: .bottom) }
                }
            }
        }
    }
}
