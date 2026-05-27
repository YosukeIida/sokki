import SwiftUI

struct LiveTranscriptView: View {
    let segments: [TranscriptSegmentViewModel]
    let hypothesis: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(segments) { seg in
                        VStack(alignment: .leading, spacing: 2) {
                            if let name = seg.speakerName {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(seg.text)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                        .id(seg.id)
                    }

                    if !hypothesis.isEmpty {
                        Text(hypothesis)
                            .font(.body)
                            .foregroundStyle(.tertiary)
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
