import Foundation
import Observation

@MainActor @Observable final class AIComposerController {
    private(set) var configuration: AIAssistConfiguration?
    private(set) var suggestion: AICompletionSuggestion?
    private(set) var isGenerating = false
    var error: String?
    @ObservationIgnored private var generation: Task<Void, Never>?
    private var generationID = UUID()
    private var instanceID: UUID?
    private var userID: String?
    private var sourceInput: AICompletionInput?
    private let complete: @Sendable (AIAssistConfiguration, AICompletionInput, URL) async throws -> AICompletionSuggestion

    init(complete: @escaping @Sendable (AIAssistConfiguration, AICompletionInput, URL) async throws -> AICompletionSuggestion = { configuration, input, server in
        try await AIAssistClient().complete(configuration: configuration, input: input, currentServer: server)
    }) {
        self.complete = complete
    }

    func reload(instance: Instance, userID: String) {
        cancel()
        self.instanceID = instance.id
        self.userID = userID
        do { configuration = try AIAssistConfigurationStore.load(instanceID: instance.id, userID: userID) }
        catch { configuration = nil; self.error = error.localizedDescription }
    }

    func setAutomatic(_ automatic: Bool) {
        guard var configuration, let instanceID, let userID else { return }
        configuration.automatic = automatic
        do {
            try AIAssistConfigurationStore.save(configuration, instanceID: instanceID, userID: userID)
            self.configuration = configuration
            if !automatic { cancel() }
        } catch { self.error = error.localizedDescription }
    }

    func schedule(_ input: AICompletionInput, instance: Instance, automatically: Bool) {
        cancel()
        guard instanceID == instance.id, let configuration, !automatically || configuration.automatic else { return }
        guard input.hasContext else {
            if !automatically { error = localized("Enter a draft or completion instructions first.", "请先输入草稿或补全要求。") }
            return
        }
        let id = UUID()
        generationID = id
        sourceInput = input
        isGenerating = true
        error = nil
        let complete = complete
        generation = Task { [weak self] in
            do {
                if automatically { try await Task.sleep(for: .milliseconds(1200)) }
                let result = try await complete(configuration, input, instance.baseURL)
                try Task.checkCancellation()
                guard let self, self.generationID == id else { return }
                self.suggestion = result
                self.isGenerating = false
                self.generation = nil
            } catch {
                guard let self, self.generationID == id, !Task.isCancelled else { return }
                self.isGenerating = false
                self.generation = nil
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }

    func takeSuggestion(for input: AICompletionInput) -> AICompletionSuggestion? {
        guard sourceInput == input, let suggestion else { cancel(); return nil }
        cancel()
        return suggestion
    }

    func cancel() {
        generationID = UUID()
        generation?.cancel()
        generation = nil
        sourceInput = nil
        suggestion = nil
        isGenerating = false
        error = nil
    }
}
