import SwiftUI
import SwiftData

// Phase 3 で実装予定 — 声紋プロファイル一覧・名前編集 UI
struct SpeakerProfileView: View {
    @Query(sort: \SpeakerProfileModel.lastSeenAt, order: .reverse)
    private var profiles: [SpeakerProfileModel]

    @Environment(AppDependencyContainer.self) private var deps
    @State private var editingProfile: SpeakerProfileModel?
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(profiles) { profile in
                SpeakerProfileRow(profile: profile) {
                    editingProfile = profile
                    newName = profile.displayName
                }
            }
        }
        .navigationTitle("話者プロファイル")
        .overlay {
            if profiles.isEmpty {
                ContentUnavailableView(
                    "プロファイルなし",
                    systemImage: "person.2",
                    description: Text("話者分離を実行すると自動的に追加されます")
                )
            }
        }
        .sheet(item: $editingProfile) { profile in
            renameSheet(profile: profile)
        }
    }

    private func renameSheet(profile: SpeakerProfileModel) -> some View {
        NavigationStack {
            Form {
                TextField("名前", text: $newName)
            }
            .navigationTitle("話者名を変更")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { editingProfile = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            try await deps.speakerProfileStore.rename(
                                profileID: profile.id, to: newName
                            )
                            editingProfile = nil
                        }
                    }
                    .disabled(newName.isEmpty)
                }
            }
        }
        .frame(minWidth: 300)
    }
}

struct SpeakerProfileRow: View {
    let profile: SpeakerProfileModel
    let onEdit: () -> Void

    var body: some View {
        HStack {
            if let color = Color(hex: profile.colorHex) {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                HStack {
                    Text("最終検出: ")
                    Text(profile.lastSeenAt, style: .relative) + Text("前")
                    Text("·")
                    Text("\(profile.segments.count) 発話")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("名前変更", action: onEdit)
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
}
