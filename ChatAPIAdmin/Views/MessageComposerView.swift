import SwiftUI

struct MessageComposerView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Binding var mode: AICompletionMode
    @Binding var text: String
    @Binding var toolName: String
    @Binding var toolCallID: String
    @Binding var instruction: String
    let tools: [AIToolDefinition]
    let canSend: Bool
    let sending: Bool
    let isGenerating: Bool
    let configured: Bool
    let automatic: Bool
    let suggestion: AICompletionSuggestion?
    let aiError: String?
    let requestIsCurrent: Bool
    let onSend: () -> Void
    let onGenerate: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void
    let onConfigure: () -> Void
    let onAutomatic: (Bool) -> Void
    @State private var showInstruction = false

    var body: some View {
        VStack(spacing: 10) {
            if let suggestion { suggestionCard(suggestion) }
            if let aiError {
                Text(aiError).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(4).accessibilityLiveRegion(.polite)
            }
            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 10) {
                    editorSurface
                    HStack(spacing: 10) {
                        Button(action: isGenerating ? onCancel : onGenerate) {
                            HStack(spacing: 6) {
                                if isGenerating { ProgressView().controlSize(.small) }
                                else { Image(systemName: "sparkles") }
                                Text(isGenerating ? localized("Cancel", "取消") : localized("AI Complete", "AI 补全"))
                            }.padding(.vertical, 3)
                        }
                        .buttonStyle(.glass).disabled(sending || !requestIsCurrent)
                        .accessibilityLabel(isGenerating ? localized("Cancel AI completion", "取消 AI 补全") : localized("Generate AI suggestion", "生成 AI 建议"))
                        Menu {
                            Button(localized("Completion Instructions", "补全要求"), systemImage: "text.badge.plus") { showInstruction.toggle() }
                            Toggle(localized("Automatic Suggestions", "自动建议"), isOn: Binding(get: { automatic }, set: onAutomatic)).disabled(!configured)
                            Button(localized("Assistant Model Settings", "辅助模型设置"), systemImage: "slider.horizontal.3", action: onConfigure)
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 26, height: 26)
                        }
                        .buttonStyle(.glass).buttonBorderShape(.circle)
                        .accessibilityLabel(localized("AI options", "AI 选项"))
                        Spacer(minLength: 0)
                        if automatic && configured && !isGenerating {
                            Text(localized("Auto", "自动")).font(.caption2).foregroundStyle(.secondary).accessibilityLabel(localized("Automatic suggestions enabled", "已开启自动建议"))
                        }
                        Button(action: onSend) {
                            Group {
                                if sending { ProgressView().tint(.white) }
                                else { Image(systemName: "arrow.up").font(.title3.weight(.semibold)) }
                            }.frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glassProminent).buttonBorderShape(.circle).tint(.cyan)
                        .disabled(!canSend).accessibilityLabel(sending ? localized("Waiting for server confirmation", "正在等待服务器确认") : localized("Send", "发送"))
                    }.padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
    }

    @ViewBuilder private var editorSurface: some View {
        if reduceTransparency {
            editor.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26))
        } else {
            editor.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 26))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    Picker(localized("Action", "动作"), selection: $mode) {
                        ForEach(AICompletionMode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Label(mode.title, systemImage: mode.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                }.accessibilityLabel(localized("Reply mode: ", "回复模式：") + mode.title)
                Spacer()
                if !requestIsCurrent { Label(localized("Request ended", "请求已结束"), systemImage: "lock").font(.caption).foregroundStyle(.secondary) }
            }
            if mode == .toolCall {
                HStack(spacing: 10) {
                    TextField(localized("Tool name", "工具名称"), text: $toolName)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(localized("Tool name", "工具名称"))
                    if !tools.isEmpty {
                        Menu {
                            ForEach(tools) { tool in Button(tool.name) { toolName = tool.name } }
                        } label: { Image(systemName: "list.bullet").padding(6) }
                        .accessibilityLabel(localized("Choose a declared tool", "选择请求声明的工具"))
                    }
                }
            }
            if mode != .reply {
                TextField(localized("Tool call ID", "工具调用 ID"), text: $toolCallID)
                    .font(.callout.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel(localized("Tool call ID", "工具调用 ID"))
            }
            TextField(mode.placeholder, text: $text, axis: .vertical)
                .font(.body).lineLimit(2...7).frame(minHeight: 48, alignment: .topLeading)
                .textInputAutocapitalization(mode == .reply ? .sentences : .never)
                .autocorrectionDisabled(mode != .reply)
                .privacySensitive()
                .accessibilityLabel(mode.placeholder)
            if showInstruction {
                Divider()
                TextField(localized("Optional instructions for AI", "给 AI 的补全要求（可选）"), text: $instruction, axis: .vertical)
                    .font(.callout).lineLimit(1...3).privacySensitive()
            }
        }.disabled(sending)
    }

    private func suggestionCard(_ suggestion: AICompletionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localized("AI Suggestion", "AI 建议"), systemImage: "sparkles").font(.caption.weight(.semibold))
                Spacer()
                Button(action: onCancel) { Image(systemName: "xmark").padding(4) }
                    .buttonStyle(.plain).accessibilityLabel(localized("Dismiss suggestion", "放弃建议"))
            }
            if mode == .toolCall { Text(suggestion.toolName).font(.callout.monospaced().weight(.semibold)) }
            ScrollView {
                Text(suggestion.text).font(mode == .toolCall ? .callout.monospaced() : .callout)
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).privacySensitive()
            }.frame(maxHeight: 140)
            HStack {
                Text(localized("Review before sending", "请核对后再发送")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(localized("Use Draft", "采纳草稿"), action: onApply).buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(sending || !requestIsCurrent)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
// Fixed sample content for Actions screenshots. This route is absent from Release.
struct ComposerPreviewView: View {
    @State private var draft: WorkspaceComposerDraft
    private let previewMode: AICompletionMode
    init(mode: AICompletionMode) {
        previewMode = mode
        var draft = WorkspaceComposerDraft()
        draft.mode = mode
        draft.reply = "可以先整理你的行程，再根据预算推荐几个合适的方案。"
        draft.toolArguments = "{\n  \"city\": \"上海\",\n  \"unit\": \"celsius\"\n}"
        draft.toolOutput = "上海，晴，24°C。"
        draft.toolName = "get_weather"
        draft.toolCallID = "call_weather_01"
        _draft = State(initialValue: draft)
    }
    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 8) {
                    Text("调用方").font(.caption).foregroundStyle(.secondary)
                    Text(previewMode == .reply ? "周末想去上海玩两天，可以帮我安排一下吗？" : "帮我查询一下上海现在的天气。")
                }.padding().background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 18)).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .navigationTitle(previewMode == .reply ? "周末行程" : "天气查询").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MessageComposerView(mode: $draft.mode, text: Binding(get: { draft.text }, set: { draft.text = $0 }), toolName: $draft.toolName, toolCallID: $draft.toolCallID, instruction: $draft.aiInstruction,
                    tools: [], canSend: true, sending: false, isGenerating: false, configured: true, automatic: true,
                    suggestion: nil, aiError: nil, requestIsCurrent: true, onSend: {}, onGenerate: {}, onCancel: {}, onApply: {}, onConfigure: {}, onAutomatic: { _ in })
            }
        }
    }
}

@MainActor private final class PreviewAuthenticationContext: DeviceAuthenticationContext {
    var method: DeviceAuthenticationMethod { .faceID }
    func evaluate(reason: String) async throws -> Bool { false }
    func invalidate() {}
}

struct LockPreviewView: View {
    @State private var lock = AppLock(makeContext: { PreviewAuthenticationContext() })
    var body: some View { LockView().environment(lock).task { lock.unlockAutomatically() } }
}
#endif
