import SwiftUI

enum SessionPromptSurface: Equatable {
    case composer
    case loading(String?)
    case permission(OpenCodePermissionRequest)
    case question(OpenCodeQuestionRequest)

    var id: String {
        switch self {
        case .composer:
            return "composer"
        case .loading(let text):
            return "loading-\(text ?? "empty")"
        case .permission(let request):
            return "permission-\(request.id)"
        case .question(let request):
            return "question-\(request.id)"
        }
    }

    var isComposer: Bool {
        if case .composer = self {
            return true
        }

        return false
    }
}

struct SessionPromptAreaView: View {
    let surface: SessionPromptSurface
    @Binding var draftText: String
    @Binding var selectionRequest: ComposerTextSelectionRequest?
    @FocusState.Binding var composerFocused: Bool
    @Binding var textInputHeight: CGFloat
    let onConfirmAuxiliarySelection: () -> Bool
    let onMoveAuxiliarySelection: (Int) -> Bool
    let onCancelAuxiliaryUI: () -> Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        Group {
            switch surface {
            case .composer:
                ComposerView(
                    text: $draftText,
                    selectionRequest: $selectionRequest,
                    onConfirmAuxiliarySelection: onConfirmAuxiliarySelection,
                    onMoveAuxiliarySelection: onMoveAuxiliarySelection,
                    onCancelAuxiliaryUI: onCancelAuxiliaryUI,
                    onSend: onSend,
                    onStop: onStop
                )
                    .textInputHeight($textInputHeight)
                    .focused($composerFocused)
            case .loading(let text):
                PromptLoadingSurfaceView(text: text)
            case .permission(let request):
                PermissionPromptSurfaceView(request: request)
            case .question(let request):
                QuestionPromptSurfaceView(request: request)
            }
        }
        .id(surface.id)
    }
}

private struct PromptLoadingSurfaceView: View {
    let text: String?

    private let contentWidth: CGFloat = 760

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prompt")
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textMuted)

            Text(displayText)
                .font(.neoBody)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeoCodeTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private var displayText: String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false ? trimmed : nil) ?? "Loading prompt..."
    }
}

private struct PermissionPromptSurfaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime

    let request: OpenCodePermissionRequest

    private let contentWidth: CGFloat = 760

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.warning)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(NeoCodeTheme.warning.opacity(0.18))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Permission required")
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.textMuted)

                    Text(permissionTitle)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(NeoCodeTheme.textPrimary)

                    if let permissionDescription {
                        Text(permissionDescription)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)
                    }
                }

                Spacer(minLength: 12)

                if store.isRespondingToPrompt {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NeoCodeTheme.warning)
                }
            }

            if !request.patterns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.always.isEmpty ? "Affected patterns" : "Allowed forever if approved")
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.warning)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(displayPatterns, id: \.self) { pattern in
                            Text(pattern)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(NeoCodeTheme.panel)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                                        )
                                )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NeoCodeTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
            }

            HStack(spacing: 10) {
                Button("Deny") {
                    Task {
                        await store.replyToPermission(
                            requestID: request.id,
                            sessionID: request.sessionID,
                            reply: .reject,
                            using: runtime
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NeoCodeTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
                .disabled(store.isRespondingToPrompt)

                Spacer(minLength: 12)

                Button("Allow always") {
                    Task {
                        await store.replyToPermission(
                            requestID: request.id,
                            sessionID: request.sessionID,
                            reply: .always,
                            using: runtime
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NeoCodeTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
                .disabled(store.isRespondingToPrompt)

                Button("Allow once") {
                    Task {
                        await store.replyToPermission(
                            requestID: request.id,
                            sessionID: request.sessionID,
                            reply: .once,
                            using: runtime
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.canvas)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NeoCodeTheme.warning)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
                .disabled(store.isRespondingToPrompt)
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private var displayPatterns: [String] {
        let source = request.always.isEmpty ? request.patterns : request.always
        return Array(source.prefix(4))
    }

    private var permissionTitle: String {
        switch request.permission {
        case "edit":
            return "Allow file edits"
        case "read":
            return "Allow file reads"
        case "bash":
            return "Allow shell command"
        case "glob":
            return "Allow file globbing"
        case "grep":
            return "Allow content search"
        case "list":
            return "Allow directory listing"
        case "task":
            return "Allow subagent task"
        case "webfetch":
            return "Allow web fetch"
        case "websearch":
            return "Allow web search"
        case "external_directory":
            return "Allow external directory access"
        case "doom_loop":
            return "Allow continued execution"
        default:
            return "Allow `\(request.permission)`"
        }
    }

    private var permissionDescription: String? {
        switch request.permission {
        case "bash":
            return metadataString(for: "description") ?? metadataString(for: "command")
        case "edit", "read", "list", "external_directory":
            return metadataString(for: "filepath") ?? metadataString(for: "filePath") ?? metadataString(for: "path") ?? request.patterns.first
        case "task":
            if let subtype = metadataString(for: "subagent_type"), let description = metadataString(for: "description") {
                return "\(subtype.capitalized): \(description)"
            }
            return metadataString(for: "description")
        case "webfetch":
            return metadataString(for: "url") ?? request.patterns.first
        case "websearch", "grep", "glob":
            return metadataString(for: "query") ?? metadataString(for: "pattern") ?? request.patterns.first
        case "doom_loop":
            return "The agent wants to continue after repeated failed attempts."
        default:
            return request.patterns.first
        }
    }

    private func metadataString(for key: String) -> String? {
        guard let value = request.metadata[key] else { return nil }
        switch value {
        case .string(let string):
            return string
        default:
            return value.prettyPrinted
        }
    }
}

private struct QuestionPromptSurfaceView: View {
    @Environment(AppStore.self) private var store
    @Environment(OpenCodeRuntime.self) private var runtime

    let request: OpenCodeQuestionRequest

    @State private var answersByQuestion: [Int: [String]] = [:]
    @State private var customInputByQuestion: [Int: String] = [:]
    @State private var editingCustomQuestionIndex: Int?
    @State private var selectedQuestionIndex = 0

    private let contentWidth: CGFloat = 760

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NeoCodeTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(NeoCodeTheme.accentDim.opacity(0.28))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(isSingleQuestion ? "Question" : "Questions")
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)

                        if let singleQuestion {
                            Text(singleQuestion.header)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.accent)
                        }
                    }

                    Text(promptTitle)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                }

                Spacer(minLength: 12)

                if store.isRespondingToPrompt {
                    ProgressView()
                        .controlSize(.small)
                        .tint(NeoCodeTheme.accent)
                }
            }

            if !isSingleQuestion {
                questionTabs
            }

            if isConfirmStep {
                questionReview
            } else if let activeQuestion, let activeQuestionIndex {
                questionStep(for: activeQuestionIndex, question: activeQuestion)
            }

            HStack(spacing: 10) {
                Button("Dismiss") {
                    Task {
                        await store.rejectQuestion(requestID: request.id, sessionID: request.sessionID, using: runtime)
                    }
                }
                .buttonStyle(.plain)
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(NeoCodeTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(NeoCodeTheme.line, lineWidth: 1)
                        )
                )
                .disabled(store.isRespondingToPrompt)

                Spacer(minLength: 12)

                if isConfirmStep || isSingleQuestion {
                    Button(submitLabel) {
                        Task {
                            await store.replyToQuestion(
                                requestID: request.id,
                                sessionID: request.sessionID,
                                answers: submissionAnswers,
                                using: runtime
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.canvas)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(NeoCodeTheme.accent)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(NeoCodeTheme.line, lineWidth: 1)
                            )
                    )
                    .disabled(store.isRespondingToPrompt || !allQuestionsAnswered)
                } else if activeQuestion?.allowsMultipleSelections == true {
                    Button(nextButtonLabel) {
                        moveToNextQuestion()
                    }
                    .buttonStyle(.plain)
                    .font(.neoMonoSmall)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(NeoCodeTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(NeoCodeTheme.line, lineWidth: 1)
                            )
                    )
                    .disabled(store.isRespondingToPrompt || !activeQuestionHasAnswer)
                }
            }
        }
        .frame(maxWidth: contentWidth, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(NeoCodeTheme.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private var promptTitle: String {
        if let singleQuestion {
            return singleQuestion.question
        }

        return "Answer the questions below to let the agent continue."
    }

    private var isSingleQuestion: Bool {
        request.questions.count == 1
    }

    private var singleQuestion: OpenCodeQuestionInfo? {
        isSingleQuestion ? request.questions.first : nil
    }

    private var confirmQuestionIndex: Int {
        request.questions.count
    }

    private var isConfirmStep: Bool {
        !isSingleQuestion && selectedQuestionIndex == confirmQuestionIndex
    }

    private var activeQuestionIndex: Int? {
        if isSingleQuestion {
            return 0
        }

        return isConfirmStep ? nil : selectedQuestionIndex
    }

    private var activeQuestion: OpenCodeQuestionInfo? {
        guard let activeQuestionIndex, request.questions.indices.contains(activeQuestionIndex) else {
            return nil
        }

        return request.questions[activeQuestionIndex]
    }

    private var submitLabel: String {
        request.questions.count == 1 ? "Send answer" : "Submit answers"
    }

    private var nextButtonLabel: String {
        nextQuestionIndex == confirmQuestionIndex ? "Review answers" : "Next question"
    }

    private var submissionAnswers: [OpenCodeQuestionAnswer] {
        request.questions.enumerated().map { index, _ in
            answersByQuestion[index] ?? []
        }
    }

    private var allQuestionsAnswered: Bool {
        request.questions.indices.allSatisfy { !(answersByQuestion[$0] ?? []).isEmpty }
    }

    private var activeQuestionHasAnswer: Bool {
        guard let activeQuestionIndex else { return false }
        return !(answersByQuestion[activeQuestionIndex] ?? []).isEmpty
    }

    private var nextQuestionIndex: Int {
        guard let activeQuestionIndex else { return confirmQuestionIndex }
        return min(activeQuestionIndex + 1, confirmQuestionIndex)
    }

    @ViewBuilder
    private var questionTabs: some View {
        HStack(spacing: 8) {
            ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                QuestionStepTab(
                    title: question.header,
                    isActive: selectedQuestionIndex == index,
                    isAnswered: !(answersByQuestion[index] ?? []).isEmpty,
                    isDisabled: store.isRespondingToPrompt
                ) {
                    selectQuestionTab(index)
                }
            }

            QuestionStepTab(
                title: "Confirm",
                isActive: isConfirmStep,
                isAnswered: allQuestionsAnswered,
                isDisabled: store.isRespondingToPrompt
            ) {
                selectQuestionTab(confirmQuestionIndex)
            }
        }
    }

    private func questionStep(for index: Int, question: OpenCodeQuestionInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !isSingleQuestion {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(question.header)
                        .font(.neoMonoSmall)
                        .foregroundStyle(NeoCodeTheme.accent)

                    if question.allowsMultipleSelections {
                        Text("Select all that apply")
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)
                    }
                }

                Text(question.question)
                    .font(.neoBody)
                    .foregroundStyle(NeoCodeTheme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(question.options, id: \.label) { option in
                    QuestionOptionButton(
                        label: option.label,
                        description: option.description,
                        isSelected: isAnswerSelected(option.label, for: index),
                        isDisabled: store.isRespondingToPrompt
                    ) {
                        selectOption(option.label, for: index, question: question)
                    }
                }

                if question.allowsCustomAnswer {
                    QuestionOptionButton(
                        label: "Type your own answer",
                        description: customOptionDescription(for: index, question: question),
                        isSelected: hasCustomSelection(for: index, question: question),
                        isDisabled: store.isRespondingToPrompt
                    ) {
                        beginCustomEditing(for: index, question: question)
                    }
                }
            }

            if question.allowsCustomAnswer && editingCustomQuestionIndex == index {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField(
                            "Type your own answer",
                            text: Binding(
                                get: { customInputByQuestion[index] ?? "" },
                                set: { customInputByQuestion[index] = $0 }
                            )
                        )
                        .neoWritingToolsDisabled()
                        .textFieldStyle(.plain)
                        .font(.neoBody)
                        .foregroundStyle(NeoCodeTheme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(NeoCodeTheme.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                        .disabled(store.isRespondingToPrompt)

                        Button(question.allowsMultipleSelections ? "Add" : "Use custom") {
                            applyCustomAnswer(for: index, question: question)
                        }
                        .buttonStyle(.plain)
                        .font(.neoMonoSmall)
                        .foregroundStyle(customActionForeground(for: index))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(customActionBackground(for: index))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                        .disabled(store.isRespondingToPrompt || customInputTrimmed(for: index).isEmpty)

                        Button {
                            cancelCustomEditing()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(NeoCodeTheme.textMuted)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(NeoCodeTheme.panelSoft)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                        .disabled(store.isRespondingToPrompt)
                    }
                }
            }

            let customAnswers = customSelections(for: index, question: question)
            if !customAnswers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(customAnswers, id: \.self) { answer in
                        HStack(spacing: 8) {
                            Text(answer)
                                .font(.neoMonoSmall)
                                .foregroundStyle(NeoCodeTheme.textSecondary)

                            Spacer(minLength: 8)

                            Button {
                                removeAnswer(answer, for: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(NeoCodeTheme.textMuted)
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .disabled(store.isRespondingToPrompt)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(NeoCodeTheme.panel)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                                )
                        )
                    }
                }
            }
        }
        .padding(.horizontal, isSingleQuestion ? 0 : 14)
        .padding(.vertical, isSingleQuestion ? 0 : 14)
        .background {
            if !isSingleQuestion {
                RoundedRectangle(cornerRadius: 16)
                    .fill(NeoCodeTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(NeoCodeTheme.line, lineWidth: 1)
                    )
            }
        }
    }

    private var questionReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review answers")
                .font(.neoMonoSmall)
                .foregroundStyle(NeoCodeTheme.accent)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(question.header)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)

                        Text(question.question)
                            .font(.neoBody)
                            .foregroundStyle(NeoCodeTheme.textPrimary)

                        Text(reviewAnswerText(for: index))
                            .font(.neoMonoSmall)
                            .foregroundStyle(reviewAnswerColor(for: index))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(NeoCodeTheme.panel)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(NeoCodeTheme.line, lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(NeoCodeTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(NeoCodeTheme.line, lineWidth: 1)
                )
        )
    }

    private func isAnswerSelected(_ answer: String, for index: Int) -> Bool {
        (answersByQuestion[index] ?? []).contains(answer)
    }

    private func selectOption(_ answer: String, for index: Int, question: OpenCodeQuestionInfo) {
        editingCustomQuestionIndex = nil

        if question.allowsMultipleSelections {
            var answers = answersByQuestion[index] ?? []
            if let existingIndex = answers.firstIndex(of: answer) {
                answers.remove(at: existingIndex)
            } else {
                answers.append(answer)
            }
            answersByQuestion[index] = answers
            return
        }

        answersByQuestion[index] = [answer]
        if !isSingleQuestion {
            moveToNextQuestion()
        }
    }

    private func selectQuestionTab(_ index: Int) {
        selectedQuestionIndex = index
        editingCustomQuestionIndex = nil
    }

    private func moveToNextQuestion() {
        selectedQuestionIndex = nextQuestionIndex
        editingCustomQuestionIndex = nil
    }

    private func beginCustomEditing(for index: Int, question: OpenCodeQuestionInfo) {
        let existingCustomAnswer = customSelections(for: index, question: question).first
        if let existingCustomAnswer {
            customInputByQuestion[index] = existingCustomAnswer
        }
        editingCustomQuestionIndex = index
    }

    private func cancelCustomEditing() {
        editingCustomQuestionIndex = nil
    }

    private func applyCustomAnswer(for index: Int, question: OpenCodeQuestionInfo) {
        let trimmed = customInputTrimmed(for: index)
        guard !trimmed.isEmpty else { return }

        if question.allowsMultipleSelections {
            var answers = answersByQuestion[index] ?? []
            if !answers.contains(trimmed) {
                answers.append(trimmed)
            }
            answersByQuestion[index] = answers
        } else {
            answersByQuestion[index] = [trimmed]
        }

        customInputByQuestion[index] = ""
        editingCustomQuestionIndex = nil
        if !question.allowsMultipleSelections && !isSingleQuestion {
            moveToNextQuestion()
        }
    }

    private func removeAnswer(_ answer: String, for index: Int) {
        var answers = answersByQuestion[index] ?? []
        answers.removeAll(where: { $0 == answer })
        answersByQuestion[index] = answers

        if customInputTrimmed(for: index) == answer {
            customInputByQuestion[index] = ""
        }
    }

    private func customSelections(for index: Int, question: OpenCodeQuestionInfo) -> [String] {
        let optionLabels = Set(question.options.map(\.label))
        return (answersByQuestion[index] ?? []).filter { !optionLabels.contains($0) }
    }

    private func hasCustomSelection(for index: Int, question: OpenCodeQuestionInfo) -> Bool {
        !customSelections(for: index, question: question).isEmpty
    }

    private func customOptionDescription(for index: Int, question: OpenCodeQuestionInfo) -> String {
        let customAnswers = customSelections(for: index, question: question)
        if !customAnswers.isEmpty {
            return customAnswers.joined(separator: ", ")
        }

        return question.allowsMultipleSelections ? "Add a custom response" : "Write a custom response"
    }

    private func reviewAnswerText(for index: Int) -> String {
        let answers = answersByQuestion[index] ?? []
        return answers.isEmpty ? "Not answered yet" : answers.joined(separator: ", ")
    }

    private func reviewAnswerColor(for index: Int) -> Color {
        let answers = answersByQuestion[index] ?? []
        return answers.isEmpty ? NeoCodeTheme.textMuted : NeoCodeTheme.textSecondary
    }

    private func customInputTrimmed(for index: Int) -> String {
        (customInputByQuestion[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func customActionForeground(for index: Int) -> Color {
        customInputTrimmed(for: index).isEmpty ? NeoCodeTheme.textMuted : NeoCodeTheme.textPrimary
    }

    private func customActionBackground(for index: Int) -> Color {
        customInputTrimmed(for: index).isEmpty ? NeoCodeTheme.panelSoft : NeoCodeTheme.panel
    }
}

private struct QuestionStepTab: View {
    let title: String
    let isActive: Bool
    let isAnswered: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.neoMonoSmall)
                    .foregroundStyle(titleColor)

                if isAnswered {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(titleColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var titleColor: Color {
        if isActive {
            return NeoCodeTheme.canvas
        }

        return isAnswered ? NeoCodeTheme.textPrimary : NeoCodeTheme.textMuted
    }

    private var backgroundColor: Color {
        if isActive {
            return NeoCodeTheme.accent
        }

        return NeoCodeTheme.panel
    }

    private var borderColor: Color {
        if isActive {
            return NeoCodeTheme.accent.opacity(0.65)
        }

        return NeoCodeTheme.line
    }
}

private struct QuestionOptionButton: View {
    let label: String
    let description: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.neoBody)
                        .foregroundStyle(isSelected ? NeoCodeTheme.textPrimary : NeoCodeTheme.textSecondary)

                    if !description.isEmpty {
                        Text(description)
                            .font(.neoMonoSmall)
                            .foregroundStyle(NeoCodeTheme.textMuted)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? NeoCodeTheme.accent : NeoCodeTheme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? NeoCodeTheme.accentDim.opacity(0.22) : NeoCodeTheme.panelSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? NeoCodeTheme.accent.opacity(0.45) : NeoCodeTheme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
