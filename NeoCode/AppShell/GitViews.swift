import SwiftUI

struct GitCommitSheet: View {
    @Environment(AppStore.self) private var store

    @Binding var isPresented: Bool

    @State private var includeUnstaged = true
    @State private var commitMessage = ""
    @State private var selectedAction: GitCommitSheetAction = .commit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let preview = store.gitCommitPreview {
                summary(preview)
                messageEditor
                actionPicker
                continueButton
            } else if store.isLoadingGitCommitPreview {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            } else {
                Spacer()
                Text("No changes are ready to commit.")
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textSecondary)
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 430, height: 622, alignment: .topLeading)
        .background(NeoCodeTheme.panel)
        .task {
            await store.refreshGitCommitPreview(showLoadingIndicator: store.gitCommitPreview == nil)
            syncWithPreview()
        }
        .onChange(of: store.gitCommitPreview) { _, _ in
            syncWithPreview()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Commit your changes")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(NeoCodeTheme.textPrimary)

            Spacer()

            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.textMuted)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(NeoCodeTheme.panelSoft))
            }
            .buttonStyle(.plain)
        }
    }

    private func summary(_ preview: GitCommitPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GitCommitMetadataRow(label: "Branch") {
                Text(preview.branch)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
            }

            GitCommitMetadataRow(label: "Changes") {
                HStack(spacing: 12) {
                    Text(fileSummary(preview))
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textSecondary)
                    Text("+\(preview.additions(includeUnstaged: includeUnstaged))")
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.success)
                    Text("-\(preview.deletions(includeUnstaged: includeUnstaged))")
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.warning)
                }
            }

            GitCommitMetadataRow(label: "Include unstaged") {
                Toggle("Include unstaged", isOn: $includeUnstaged)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.82)
                    .disabled(!preview.hasUnstagedChanges)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredFiles(preview)) { file in
                        GitCommitFileRow(file: file)
                    }
                }
                .padding(12)
            }
            .frame(height: 104)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NeoCodeTheme.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            )
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Commit message")
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)

            ZStack(alignment: .topLeading) {
                let editorHorizontalInset: CGFloat = 11
                let editorTopInset: CGFloat = 10

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NeoCodeTheme.panelRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )

                TextEditor(text: $commitMessage)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .padding(.leading, editorHorizontalInset - 4)
                    .padding(.trailing, editorHorizontalInset - 4)
                    .padding(.top, editorTopInset - 2)
                    .padding(.bottom, 2)
                    .frame(height: 68)

                if commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Enter a commit message")
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textMuted)
                        .padding(.leading, editorHorizontalInset)
                        .padding(.top, editorTopInset)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 68)
        }
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next steps")
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)

            VStack(spacing: 8) {
                GitCommitActionButton(
                    title: "Commit",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    isSelected: selectedAction == .commit,
                    isDisabled: store.isPerformingGitOperation,
                    action: { selectedAction = .commit }
                )
                GitCommitActionButton(
                    title: "Commit and push",
                    systemImage: "arrow.up.circle",
                    isSelected: selectedAction == .commitAndPush,
                    isDisabled: store.isPerformingGitOperation,
                    action: { selectedAction = .commitAndPush }
                )
                GitCommitActionButton(
                    title: "Commit and create PR",
                    systemImage: "arrow.triangle.pull",
                    isSelected: false,
                    isDisabled: true,
                    action: {}
                )
            }
        }
    }

    private var continueButton: some View {
        Button(action: runPrimaryAction) {
            Text(primaryButtonTitle)
                .font(.neoAction)
                .foregroundStyle(NeoCodeTheme.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canContinue ? NeoCodeTheme.textPrimary : NeoCodeTheme.textMuted)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue || store.isPerformingGitOperation)
    }

    private var primaryButtonTitle: String {
        if let operationState = store.currentGitOperationState {
            return "\(operationState.title)..."
        }

        return "Continue"
    }

    private var canContinue: Bool {
        guard let preview = store.gitCommitPreview,
              commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyTrimmed != nil
        else { return false }
        if includeUnstaged {
            return preview.fileCount > 0
        }
        return preview.hasStagedChanges
    }

    private func filteredFiles(_ preview: GitCommitPreview) -> [GitFileChange] {
        if includeUnstaged {
            return preview.changedFiles
        }

        return preview.changedFiles.filter(\.isStaged)
    }

    private func fileSummary(_ preview: GitCommitPreview) -> String {
        let count = filteredFiles(preview).count
        return "\(count) file\(count == 1 ? "" : "s")"
    }

    private func syncWithPreview() {
        guard let preview = store.gitCommitPreview else { return }
        includeUnstaged = preview.hasUnstagedChanges
        if selectedAction == .commitAndCreatePR {
            selectedAction = .commit
        }
    }

    private func runPrimaryAction() {
        guard canContinue else { return }

        Task {
            let committed = await store.commitChanges(
                message: commitMessage,
                includeUnstaged: includeUnstaged,
                pushAfterCommit: selectedAction == .commitAndPush
            )
            if committed {
                await MainActor.run {
                    isPresented = false
                }
            }
        }
    }
}

private enum GitCommitSheetAction: String, Identifiable {
    case commit
    case commitAndPush
    case commitAndCreatePR

    var id: String { rawValue }
}

private struct GitCommitMetadataRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct GitCommitFileRow: View {
    let file: GitFileChange

    var body: some View {
        HStack(spacing: 10) {
            Text(file.statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(NeoCodeTheme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(NeoCodeTheme.accent.opacity(0.14)))

            Text(file.path)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(fileStateLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(fileStateColor)
        }
    }

    private var fileStateLabel: String {
        switch (file.isStaged, file.isUnstaged) {
        case (true, true):
            return "mixed"
        case (true, false):
            return "staged"
        case (false, true):
            return "unstaged"
        case (false, false):
            return ""
        }
    }

    private var fileStateColor: Color {
        switch fileStateLabel {
        case "staged":
            return NeoCodeTheme.success
        case "mixed":
            return NeoCodeTheme.accent
        default:
            return NeoCodeTheme.warning
        }
    }
}

private struct GitCommitActionButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(foreground)
                    .frame(width: 16, height: 16)

                Text(title)
                    .font(.neoAction)
                    .foregroundStyle(foreground)

                Spacer(minLength: 10)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var foreground: Color {
        isDisabled ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
    }

    private var background: Color {
        isSelected ? NeoCodeTheme.panelSoft : NeoCodeTheme.panelRaised
    }

    private var border: Color {
        isSelected ? NeoCodeTheme.lineStrong : NeoCodeTheme.line
    }
}
