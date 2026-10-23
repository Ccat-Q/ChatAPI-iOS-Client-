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
            }.onDelete { offsets in let ids = offsets.map { rules[$0].id }; Task { await delete(ids) } }
        }
        .overlay { if rules.isEmpty { ContentUnavailableView(localized("No automation rules", "暂无自动化规则"), systemImage: "wand.and.stars") } }
        .navigationTitle(localized("Automation Rules", "自动化规则"))
        .toolbar { Button { creating = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $creating) { NavigationStack { AutomationRuleEditor(rule: .empty, onSaved: { await load(); creating = false }) } }
        .task { await load() }.refreshable { await load() }
        .alert(localized("Automation Failed", "自动化操作失败"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func load() async { guard let client = store.client() else { return }; do { let response: AutomationRuleListResponse = try await client.get("/api/automation/rules"); rules = response.rules } catch { self.error = error.localizedDescription } }
    private func delete(_ ids: [String]) async { guard let client = store.client() else { return }; for id in ids { guard !id.isEmpty else { continue }; do { let _: SuccessResponse = try await client.delete("/api/automation/rules/\(id)") } catch { self.error = error.localizedDescription; return } }; await load() }
}

private struct AutomationRuleEditor: View {
    @Environment(InstanceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutomationRule
    let onSaved: () async -> Void
    @State private var error: String?
    @State private var saving = false

    private var supported: Bool { rule.schemaVersion == 3 && ["recorded", "fixed"].contains(rule.playback.mode) && rule.steps.allSatisfy { ["stream_complete", "stream_delta"].contains($0.action.kind) && ["", "assistant_message", "tool_call", "tool_result"].contains($0.action.mode) } }

    var body: some View {
        Form {
            if !supported { Text(localized("This rule uses advanced actions. Edit it in the server Web console.", "此规则包含高级动作，请在服务器 Web 控制台中编辑。")).foregroundStyle(.secondary) }
            Section(localized("Rule", "规则")) { TextField(localized("Name", "名称"), text: $rule.name); Toggle(localized("Enabled", "启用"), isOn: $rule.enabled); Stepper("\(localized("Priority", "优先级")): \(rule.priority)", value: $rule.priority) }
            Section(localized("Match", "匹配条件")) { TextField(localized("Request text pattern", "请求文本模式"), text: $rule.match.pattern); TextField(localized("Model pattern", "模型模式"), text: $rule.match.modelPattern); TextField(localized("Model key ID", "模型密钥 ID"), text: $rule.match.modelKeyID) }
            Section(localized("Playback", "播放")) { Picker(localized("Mode", "模式"), selection: $rule.playback.mode) { Text(localized("Recorded timing", "记录的时序")).tag("recorded"); Text(localized("Fixed interval", "固定间隔")).tag("fixed") }; Toggle(localized("Loop", "循环"), isOn: $rule.playback.loop); if rule.playback.mode == "fixed" { Stepper("\(localized("Fixed interval", "固定间隔")): \(rule.playback.fixedIntervalMS) ms", value: $rule.playback.fixedIntervalMS, in: 0...60_000, step: 100) }; if rule.playback.loop { Stepper("\(localized("Loop interval", "循环间隔")): \(rule.playback.loopIntervalMS) ms", value: $rule.playback.loopIntervalMS, in: 0...60_000, step: 100) }; Stepper("\(localized("Initial delay", "初始延迟")): \(rule.playback.initialDelayMS) ms", value: $rule.playback.initialDelayMS, in: 0...60_000, step: 100) }
            Section(localized("Steps", "步骤")) { ForEach($rule.steps) { $step in AutomationStepEditor(step: $step) }.onDelete { rule.steps.remove(atOffsets: $0) }; Button(localized("Add Step", "添加步骤")) { rule.steps.insert(.init(id: UUID().uuidString, delayBeforeMS: 0, action: .init(kind: "stream_delta", text: "", mode: "assistant_message", toolName: "", toolCallID: "", output: "")), at: max(0, rule.steps.count - 1)) } }
        }
        .disabled(saving || !supported)
        .navigationTitle(rule.id.isEmpty ? localized("New Rule", "新建规则") : localized("Edit Rule", "编辑规则"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(saving ? localized("Saving…", "正在保存…") : localized("Save", "保存")) { Task { await save() } }.disabled(saving || !supported || (rule.enabled && (rule.match.pattern.isEmpty || rule.match.modelPattern.isEmpty || rule.match.modelKeyID.isEmpty)) || rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.steps.isEmpty) } }
        .alert(localized("Could Not Save Rule", "无法保存规则"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(localized("OK", "好"), role: .cancel) {} } message: { Text(error ?? "") }
    }

    private func save() async { guard !saving, supported, let client = store.client() else { return }; saving = true; defer { saving = false }; do { let path = rule.id.isEmpty ? "/api/automation/rules" : "/api/automation/rules/\(rule.id)"; let _: AutomationRuleSaveResponse = rule.id.isEmpty ? try await client.post(path, body: rule) : try await client.put(path, body: rule); await onSaved(); dismiss() } catch { self.error = error.localizedDescription } }
}

private struct AutomationStepEditor: View {
    @Binding var step: AutomationStep
    var body: some View {
        Picker(localized("Action", "动作"), selection: Binding(get: { step.action.kind == "stream_delta" ? "stream_delta" : (step.action.mode.isEmpty ? "assistant_message" : step.action.mode) }, set: { step.action.kind = $0 == "stream_delta" ? "stream_delta" : "stream_complete"; step.action.mode = $0 == "stream_delta" ? "assistant_message" : $0 })) { Text(localized("Streaming text", "流式文本")).tag("stream_delta"); Text(localized("Assistant response", "助手回复")).tag("assistant_message"); Text(localized("Tool call", "工具调用")).tag("tool_call"); Text(localized("Tool output", "工具输出")).tag("tool_result") }
        Stepper("\(localized("Delay", "延迟")): \(step.delayBeforeMS) ms", value: $step.delayBeforeMS, in: 0...60_000, step: 100)
        if step.action.mode == "tool_call" { TextField(localized("Tool name", "工具名称"), text: $step.action.toolName); TextField(localized("Tool call ID", "工具调用 ID"), text: $step.action.toolCallID); TextField(localized("Arguments / text", "参数 / 文本"), text: $step.action.text) }
        else if step.action.mode == "tool_result" { TextField(localized("Tool call ID", "工具调用 ID"), text: $step.action.toolCallID); TextField(localized("Tool output", "工具输出"), text: $step.action.output) }
        else { TextField(localized("Response", "回复内容"), text: $step.action.text, axis: .vertical).lineLimit(2...6) }
    }
}
