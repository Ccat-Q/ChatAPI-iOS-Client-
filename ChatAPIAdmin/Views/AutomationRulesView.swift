import SwiftUI

struct AutomationRulesView: View {
    @Environment(InstanceStore.self) private var store
    @State private var rules: [AutomationRule] = []
    @State private var error: String?
    @State private var creating = false

    var body: some View {
        List {
            ForEach(rules) { rule in
                NavigationLink { AutomationRuleEditor(rule: rule, onSaved: { await load() }) } label: {
                    VStack(alignment: .leading) {
                        Text(rule.name.isEmpty ? localized("Untitled rule", "未命名规则") : rule.name)
                        Text(rule.enabled ? localized("Enabled", "已启用") : localized("Disabled", "已停用")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { offsets in Task { await delete(offsets) } }
        }
        .overlay { if rules.isEmpty { ContentUnavailableView(localized("No automation rules", "暂无自动化规则"), systemImage: "wand.and.stars") } }
        .navigationTitle(localized("Automation Rules", "自动化规则"))
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $creating) { NavigationStack { AutomationRuleEditor(rule: .empty, onSaved: { await load(); creating = false }) } }
        .task { await load() }.refreshable { await load() }
        .alert(localized("Automation Failed", "自动化操作失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func load() async { guard let client = store.client() else { return }; do { let response: AutomationRuleListResponse = try await client.get("/api/automation/rules"); rules = response.rules } catch { self.error = error.localizedDescription } }
    private func delete(_ offsets: IndexSet) async { guard let client = store.client() else { return }; for index in offsets { let rule = rules[index]; guard !rule.id.isEmpty else { continue }; do { let _: SuccessResponse = try await client.delete("/api/automation/rules/\(rule.id)") } catch { self.error = error.localizedDescription; return } }; await load() }
}

private struct AutomationRuleEditor: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutomationRule
    let onSaved: () async -> Void
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form {
            Section(localized("Rule", "规则")) { TextField(localized("Name", "名称"), text: $rule.name); Toggle(localized("Enabled", "启用"), isOn: $rule.enabled); Stepper("\(localized("Priority", "优先级")): \(rule.priority)", value: $rule.priority) }
            Section(localized("Match", "匹配条件")) { TextField(localized("Request text pattern", "请求文本模式"), text: $rule.match.pattern); TextField(localized("Model pattern", "模型模式"), text: $rule.match.modelPattern); TextField(localized("Model key ID", "模型密钥 ID"), text: $rule.match.modelKeyID) }
            Section(localized("Playback", "播放")) { Picker(localized("Mode", "模式"), selection: $rule.playback.mode) { Text(localized("Once", "一次")).tag("once"); Text(localized("Fixed interval", "固定间隔")).tag("fixed_interval") }; Toggle(localized("Loop", "循环"), isOn: $rule.playback.loop); Stepper("\(localized("Initial delay", "初始延迟")): \(rule.playback.initialDelayMS) ms", value: $rule.playback.initialDelayMS, in: 0...60_000, step: 100) }
            Section(localized("Steps", "步骤")) { ForEach($rule.steps) { $step in AutomationStepEditor(step: $step) }.onDelete { rule.steps.remove(atOffsets: $0) }; Button(localized("Add Step", "添加步骤")) { rule.steps.append(.init(id: UUID().uuidString, delayBeforeMS: 0, action: .init(kind: "stream_complete", text: "", mode: "assistant_message", toolName: "", toolCallID: "", output: ""))) } }
        }
        .navigationTitle(rule.id.isEmpty ? localized("New Rule", "新建规则") : localized("Edit Rule", "编辑规则"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(saving ? localized("Saving…", "正在保存…") : localized("Save", "保存")) { Task { await save() } }.disabled(saving || rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.steps.isEmpty) } }
        .alert(localized("Could Not Save Rule", "无法保存规则"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func save() async { guard let client = store.client() else { return }; saving = true; defer { saving = false }; do { let path = rule.id.isEmpty ? "/api/automation/rules" : "/api/automation/rules/\(rule.id)"; let _: AutomationRuleSaveResponse = rule.id.isEmpty ? try await client.post(path, body: rule) : try await client.put(path, body: rule); await onSaved(); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct AutomationStepEditor: View {
    @Binding var step: AutomationStep
    var body: some View {
        Picker(localized("Action", "动作"), selection: $step.action.kind) { Text(localized("Assistant response", "助手回复")).tag("stream_complete"); Text(localized("Tool call", "工具调用")).tag("tool_call"); Text(localized("Tool output", "工具输出")).tag("tool_output") }
        Stepper("\(localized("Delay", "延迟")): \(step.delayBeforeMS) ms", value: $step.delayBeforeMS, in: 0...60_000, step: 100)
        if step.action.kind == "tool_call" { TextField(localized("Tool name", "工具名称"), text: $step.action.toolName); TextField(localized("Tool call ID", "工具调用 ID"), text: $step.action.toolCallID); TextField(localized("Arguments / text", "参数 / 文本"), text: $step.action.text) }
        else if step.action.kind == "tool_output" { TextField(localized("Tool call ID", "工具调用 ID"), text: $step.action.toolCallID); TextField(localized("Tool output", "工具输出"), text: $step.action.output) }
        else { TextField(localized("Response", "回复内容"), text: $step.action.text, axis: .vertical).lineLimit(2...6) }
    }
}
