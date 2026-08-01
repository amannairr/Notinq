import Foundation
import AppKit
import UniformTypeIdentifiers

struct AIModelRecommendation: Codable, Equatable, Sendable {
    var title: String
    var reasoning: String
    var modelIDs: [String]
}

struct AIModelDiagnostics: Codable, Equatable, Sendable {
    var activeModelID: String?
    var activeModelPath: String?
    var providerKind: AIProviderKind
    var quantization: String
    var contextLength: Int
    var loadedMemoryBytes: UInt64
    var hardware: HardwareProfile
    var recommendations: [AIModelRecommendation]
    var storageUsageBytes: Int64
    var cacheEntryCount: Int
}

final class ModelManager {
    static let shared = ModelManager()

    private let queue = DispatchQueue(label: "notinq.ai.model.manager", qos: .userInitiated)
    private let library = AIModelLibrary.shared
    private let defaults = UserDefaults.standard
    private let preferredProviderKey = "notinq.preferredAIProvider"
    private var llamaContext: LlamaContext?
    private var activeModelURL: URL?
    private var activeModelID: String?
    private var isAccessingSecurityScopedResource = false
    private var idleUnloadWorkItem: DispatchWorkItem?
    private var isInferencing = false
    private var cachedDiagnostics: AIModelDiagnostics?
    private var cachedHardware = HardwareDetector.detect()

    private init() {
        _ = cachedHardware
        if defaults.string(forKey: preferredProviderKey) == nil {
            defaults.set(AIProviderKind.localLlama.rawValue, forKey: preferredProviderKey)
        }
    }

    var activeProviderKind: AIProviderKind {
        AIProviderKind(rawValue: defaults.string(forKey: preferredProviderKey) ?? AIProviderKind.localLlama.rawValue) ?? .localLlama
    }

    func selectProvider(_ kind: AIProviderKind) {
        defaults.set(kind.rawValue, forKey: preferredProviderKey)
        NotificationCenter.default.post(name: .notinqProviderSelectionDidChange, object: nil)
    }

    func currentHardwareProfile() -> HardwareProfile {
        cachedHardware
    }

    func refreshHardwareProfile() {
        cachedHardware = HardwareDetector.detect()
        cachedDiagnostics = nil
        NotificationCenter.default.post(name: .notinqHardwareDidChange, object: nil)
    }

    func availableModels() -> [AIModelDefinition] {
        library.refreshSnapshot().catalog
    }

    func installedModels() -> [AIInstalledModel] {
        library.installedModels()
    }

    func storageUsageBytes() -> Int64 {
        library.storageUsageBytes()
    }

    func hardwareRecommendations() -> [AIModelRecommendation] {
        let profile = currentHardwareProfile()
        return [
            AIModelRecommendation(
                title: "8 GB",
                reasoning: "Default local recommendation for lower-memory systems.",
                modelIDs: ["qwen-3-4b"]
            ),
            AIModelRecommendation(
                title: "16 GB+",
                reasoning: "Can run higher quality local models comfortably.",
                modelIDs: ["qwen-3-4b"]
            ),
            AIModelRecommendation(
                title: "24 GB+",
                reasoning: "Supports more capable local models and larger contexts.",
                modelIDs: ["qwen-3-4b"]
            )
        ]
        .filter { recommendation in
            switch recommendation.title {
            case "8 GB":
                return profile.totalMemoryGB < 16
            case "16 GB+":
                return profile.totalMemoryGB >= 16
            case "24 GB+":
                return profile.totalMemoryGB >= 24
            default:
                return true
            }
        }
    }

    func refreshSnapshot() -> AIModelLibrarySnapshot {
        library.refreshSnapshot()
    }

    func currentModelPathDescription() -> String {
        queue.sync {
            if let activeModelURL {
                return activeModelURL.path
            }
            if let preferredID = library.preferredModelID,
               let installed = library.installedModel(for: preferredID) {
                return installed.fileURL.path
            }
            return library.activeModelDescription(for: .basic)
        }
    }

    func currentModelDiagnostics() -> AIModelDiagnostics {
        return queue.sync { () -> AIModelDiagnostics in
            if let cachedDiagnostics {
                return cachedDiagnostics
            }
            let diagnostics = AIModelDiagnostics(
                activeModelID: activeModelID ?? library.preferredModelID,
                activeModelPath: activeModelURL?.path,
                providerKind: activeProviderKind,
                quantization: activeModelURL?.lastPathComponent.contains("Q4") == true ? "Q4_K_M" : "Unknown",
                contextLength: Int(AIRuntimeConfig.current.llama.contextSize),
                loadedMemoryBytes: activeModelURL == nil ? 0 : cachedHardware.physicalMemoryBytes / 4,
                hardware: cachedHardware,
                recommendations: hardwareRecommendations(),
                storageUsageBytes: storageUsageBytes(),
                cacheEntryCount: 0
            )
            cachedDiagnostics = diagnostics
            return diagnostics
        }
    }

    func beginInference() -> Bool {
        queue.sync {
            if isInferencing { return false }
            isInferencing = true
            cancelIdleUnload()
            loadLlamaIfNeeded()
            return true
        }
    }

    func endInference() {
        queue.async {
            self.isInferencing = false
            self.scheduleIdleUnload()
        }
    }

    func currentLlamaContext() -> LlamaContext? {
        queue.sync { llamaContext }
    }

    func selectPreferredModel(id: String) {
        library.selectPreferredModel(id: id)
        unloadLlama(reason: "model changed")
        NotificationCenter.default.post(name: .notinqLocalModelDidChange, object: nil)
    }

    func chooseLocalModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a local GGUF model"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]

        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }
            do {
                let installed = try AIModelLibrary.shared.installModel(from: selectedURL, preferred: true)
                self?.selectPreferredModel(id: installed.id)
            } catch {
                AIPerfLog.debug("failed choosing local model: \(error.localizedDescription)")
            }
        }
    }

    func downloadModel(_ definition: AIModelDefinition) async throws -> AIInstalledModel {
        try await library.downloadModel(definition)
    }

    func deleteModel(id: String) throws {
        try library.deleteModel(id: id)
        if activeModelID == id {
            unloadLlama(reason: "deleted model")
        }
    }

    func unloadLlama(reason: String) {
        queue.async {
            guard !self.isInferencing else { return }
            if self.llamaContext != nil {
                AIPerfLog.debug("unloading llama (\(reason))")
            }
            self.llamaContext = nil
            if self.isAccessingSecurityScopedResource {
                self.activeModelURL?.stopAccessingSecurityScopedResource()
                self.isAccessingSecurityScopedResource = false
            }
            self.activeModelURL = nil
            self.activeModelID = nil
            self.cachedDiagnostics = nil
        }
    }

    func fallbackModelID() -> String {
        library.preferredCatalogModel(for: .advanced)?.id ?? "qwen-3-4b"
    }

    func activeModelIDDescription() -> String {
        queue.sync { activeModelID ?? library.preferredModelID ?? fallbackModelID() }
    }

    private func cancelIdleUnload() {
        idleUnloadWorkItem?.cancel()
        idleUnloadWorkItem = nil
    }

    private func scheduleIdleUnload() {
        guard llamaContext != nil else { return }
        let seconds = AIRuntimeConfig.current.idleUnloadSeconds
        let workItem = DispatchWorkItem { [weak self] in
            self?.unloadLlama(reason: "idle")
        }
        idleUnloadWorkItem = workItem
        queue.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }

    private func resolveModelURL() -> (url: URL, modelID: String)? {
        let preferredID = library.preferredModelID ?? fallbackModelID()
        if let preferred = library.installedModel(for: preferredID) {
            return (preferred.fileURL, preferred.id)
        }

        if let installedDefault = library.installedModel(for: fallbackModelID()) {
            return (installedDefault.fileURL, installedDefault.id)
        }

        if let defaultDefinition = library.catalogDefinition(for: fallbackModelID()),
           let sourceURL = defaultDefinition.bundledResourceURL {
            do {
                let installed = try library.installModel(from: sourceURL, preferred: true)
                return (installed.fileURL, installed.id)
            } catch {
                AIPerfLog.debug("failed installing default model: \(error.localizedDescription)")
            }
        }

        if let preferredURL = library.preferredModelURL(for: .advanced) {
            let preferredID = library.installedModel(for: library.preferredModelID ?? "")?.id ?? preferredURL.deletingPathExtension().lastPathComponent
            return (preferredURL, preferredID)
        }

        return nil
    }

    private func loadLlamaIfNeeded() {
        guard llamaContext == nil else { return }
        NotificationCenter.default.post(name: .notinqAIWillUseLlama, object: nil)

        guard PLLlamaBackendAvailable() else {
            AIPerfLog.debug("llama backend unavailable")
            llamaContext = nil
            return
        }

        guard let resolved = resolveModelURL() else {
            AIPerfLog.debug("llama model missing; falling back to bundled recommendation")
            llamaContext = nil
            return
        }

        let didStartAccessing = resolved.url.startAccessingSecurityScopedResource()
        isAccessingSecurityScopedResource = didStartAccessing
        activeModelURL = resolved.url
        activeModelID = resolved.modelID

        let config = AIRuntimeConfig.current.llama
        let started = CFAbsoluteTimeGetCurrent()
        llamaContext = LlamaContext(modelPath: resolved.url.path, config: config)
        let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000

        if llamaContext != nil {
            AIPerfLog.debug("llama loaded (\(Int(elapsed))ms) with model \(resolved.modelID)")
            cachedDiagnostics = nil
        } else {
            AIPerfLog.debug("llama failed to initialize")
            if didStartAccessing {
                resolved.url.stopAccessingSecurityScopedResource()
                isAccessingSecurityScopedResource = false
            }
            activeModelURL = nil
            activeModelID = nil
        }
    }

    func loadModel() async throws {
        queue.sync {
            loadLlamaIfNeeded()
        }
        guard currentLlamaContext() != nil else {
            throw InferenceError.loadFailed
        }
    }

    func unloadModel() {
        unloadLlama(reason: "manual unload")
    }

    func currentModel() -> LocalModel? {
        queue.sync {
            guard let activeModelURL else { return nil }
            let installed = library.installedModel(for: activeModelID ?? "") ?? AIInstalledModel(
                id: activeModelID ?? activeModelURL.deletingPathExtension().lastPathComponent,
                displayName: activeModelURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "),
                fileURL: activeModelURL,
                fileSizeBytes: 0,
                tierHint: nil,
                sourceDefinitionID: nil
            )
            return library.localModels().first(where: { $0.id == installed.id }) ?? LocalModel(
                id: installed.id,
                name: installed.displayName,
                path: installed.fileURL.path,
                size: installed.fileSizeBytes,
                contextLength: Int(AIRuntimeConfig.current.llama.contextSize),
                parameterCount: 0,
                quantization: activeModelURL.lastPathComponent.lowercased().contains("q4") ? "Q4_K_M" : "Unknown"
            )
        }
    }

    var isLoaded: Bool {
        currentLlamaContext() != nil
    }

    func generate(_ request: InferenceRequest) async throws -> InferenceResponse {
        let started = CFAbsoluteTimeGetCurrent()
        try await loadModel()
        guard let ctx = currentLlamaContext() else {
            throw InferenceError.modelNotLoaded
        }
        guard request.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw InferenceError.generationFailed
        }
        let text = ctx.generate(prompt: "\(request.systemPrompt)\n\n\(request.userPrompt)", maxTokens: Int32(request.maxTokens))
        let latency = CFAbsoluteTimeGetCurrent() - started
        return InferenceResponse(
            text: text,
            latency: latency,
            tokensGenerated: max(1, text.split { $0.isWhitespace || $0.isNewline }.count),
            promptTokens: max(1, request.systemPrompt.split { $0.isWhitespace || $0.isNewline }.count + request.userPrompt.split { $0.isWhitespace || $0.isNewline }.count),
            completionTokens: max(1, text.split { $0.isWhitespace || $0.isNewline }.count)
        )
    }

    func generateStream(_ request: InferenceRequest, onToken: @escaping (String) -> Void) async throws -> InferenceResponse {
        let started = CFAbsoluteTimeGetCurrent()
        try await loadModel()
        guard let ctx = currentLlamaContext() else {
            throw InferenceError.modelNotLoaded
        }
        let prompt = "\(request.systemPrompt)\n\n\(request.userPrompt)"
        let success = ctx.generateStreaming(prompt: prompt, maxTokens: Int32(request.maxTokens), onToken: onToken)
        guard success else {
            throw InferenceError.generationFailed
        }
        let latency = CFAbsoluteTimeGetCurrent() - started
        return InferenceResponse(
            text: "",
            latency: latency,
            tokensGenerated: 0,
            promptTokens: max(1, prompt.split { $0.isWhitespace || $0.isNewline }.count),
            completionTokens: 0
        )
    }

    func cancelCurrentGeneration() {
        currentLlamaContext()?.cancelGeneration()
    }
}

typealias AIModelManager = ModelManager
