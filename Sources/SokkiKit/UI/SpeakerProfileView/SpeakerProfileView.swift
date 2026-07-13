import SwiftUI
import SwiftData

/// 話者プロファイル一覧画面（TASK-30 / P3-7）。
///
/// 名前のインライン編集・出現回数（`embeddingCount`）と最終出現日時の表示・
/// 声紋の削除（確認ダイアログ付き）を提供する。デザイン方針は
/// `docs/design/speaker-profile-v1.html`（TASK-9.3）のインライン編集パターンに準拠する。
///
/// 削除は `SpeakerProfileStore.deleteProfile` を呼ぶだけでよい。
/// `SegmentModel.speakerProfile` ⇄ `SpeakerProfileModel.segments` は
/// `deleteRule: .nullify`（`SpeakerProfileModel.swift` 側で宣言）のため、プロファイル削除時に
/// 紐づく `SegmentModel` は削除されず `speakerProfile` が `nil` に自動更新される
/// （dangling 参照にはならない）。
struct SpeakerProfileView: View {
    @Query(sort: \SpeakerProfileModel.lastSeenAt, order: .reverse)
    private var profiles: [SpeakerProfileModel]

    @Environment(AppDependencyContainer.self) private var deps

    @State private var editingProfileID: UUID?
    @State private var editingName = ""
    @State private var profileToDelete: SpeakerProfileModel?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(profiles) { profile in
                SpeakerProfileRow(
                    profile: profile,
                    isEditing: editingProfileID == profile.id,
                    editingName: $editingName,
                    onStartEdit: { startEditing(profile) },
                    onCommitEdit: { commitEdit(profile) },
                    onCancelEdit: cancelEdit,
                    onDelete: { profileToDelete = profile }
                )
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
        .confirmationDialog(
            "「\(profileToDelete?.displayName ?? "")」を削除しますか？",
            isPresented: isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) {
                if let profile = profileToDelete {
                    delete(profile)
                }
            }
            Button("キャンセル", role: .cancel) {
                profileToDelete = nil
            }
        } message: {
            Text("声紋データが削除されます。この話者に紐づく発話記録は残りますが、話者名は表示されなくなります。")
        }
        .alert(
            "エラー",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in if !isPresented { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isDeleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { profileToDelete != nil },
            set: { isPresented in
                if !isPresented { profileToDelete = nil }
            }
        )
    }

    private func startEditing(_ profile: SpeakerProfileModel) {
        editingName = profile.displayName
        editingProfileID = profile.id
    }

    private func cancelEdit() {
        editingProfileID = nil
        editingName = ""
    }

    // 空名（前後空白のみ含む）は保存を拒否し、編集前の名前に戻す。
    private func commitEdit(_ profile: SpeakerProfileModel) {
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelEdit()
        guard !trimmed.isEmpty else { return }
        let profileID = profile.id
        Task {
            do {
                try await deps.speakerProfileStore.rename(profileID: profileID, to: trimmed)
            } catch {
                errorMessage = "名前の変更に失敗しました: \(error.localizedDescription)"
            }
        }
    }

    private func delete(_ profile: SpeakerProfileModel) {
        profileToDelete = nil
        let profileID = profile.id
        Task {
            do {
                try await deps.speakerProfileStore.deleteProfile(profileID)
            } catch {
                errorMessage = "削除に失敗しました: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Row

private struct SpeakerProfileRow: View {
    let profile: SpeakerProfileModel
    let isEditing: Bool
    @Binding var editingName: String
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SpeakerColorBar(color: Color(hex: profile.colorHex) ?? .secondary)
                .frame(height: 32)

            if isEditing {
                TextField("話者名", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onCommitEdit)
                    .accessibilityIdentifier("speakerProfileNameField")

                Button(action: onCommitEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("保存")

                Button(action: onCancelEdit) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("キャンセル")
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.headline)
                    HStack(spacing: 6) {
                        // embeddingCount は resolveProfiles 呼び出し（= 1 セッション）ごとに 1 回だけ
                        // 加算される（発話セグメント数ではない）。spec.md の「過去セッション出現回数」・
                        // docs/design/speaker-profile-v1.html の「N セッション」表記に合わせる。
                        Text("\(profile.embeddingCount) セッション")
                        Text("·")
                        Text("最終出現: ")
                        Text(profile.lastSeenAt, format: .dateTime.month().day())
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onStartEdit) {
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("名前を変更")
                .accessibilityIdentifier("speakerProfileRenameButton")

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("削除")
                .accessibilityIdentifier("speakerProfileDeleteButton")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("speakerProfileRow")
    }
}
