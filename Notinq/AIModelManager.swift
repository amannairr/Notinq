import Foundation
import AppKit

final class AIModelManager {
    static let shared = AIModelManager()

    private let queue = DispatchQueue(label: "notinq.ai.model.manager", qos: .userInitiated)
    private var llamaContext: LlamaContext?
    private var activeModelURL: URL?
    private var activeModelID: String?
    private var isAccessingSecurityScopedResource = false
    private var idleUnloadWorkItem: DispatchWorkItem?
    private var isInferencing = false

    private init() {}

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

    func currentModelPathDescription() -> String {
        queue.sync {
            activeModelURL?.path ?? AIModelLibrary.shared.activeModelDescription(for: AICapabilityManager.shared.currentTier)
        }
    }

    func selectPreferredModel(id: String) {
        AIModelLibrary.shared.selectPreferredModel(id: id)
        unloadLlama(reason: "model changed")
        NotificationCenter.default.post(name: .notinqLocalModelDidChange, object: nil)
    }

    func chooseLocalModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a local GGUF model"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["gguf"]

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
        }
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
        let tier = AICapabilityManager.shared.currentTier
        let library = AIModelLibrary.shared

        if let preferredID = library.preferredModelID,
           let preferred = library.installedModel(for: preferredID) {
            return (preferred.fileURL, preferred.id)
        }

        if let installedDefault = library.installedModel(for: "qwen-2.5-1.5b") {
            return (installedDefault.fileURL, installedDefault.id)
        }

        if let defaultDefinition = library.catalogDefinition(for: "qwen-2.5-1.5b"),
           let sourceURL = defaultDefinition.bundledResourceURL {
            do {
                let installed = try library.installModel(from: sourceURL, preferred: true)
                return (installed.fileURL, installed.id)
            } catch {
                AIPerfLog.debug("failed installing default Qwen 1.5B: \(error.localizedDescription)")
            }
        }

        if let preferredURL = library.preferredModelURL(for: tier) {
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
            AIPerfLog.debug("llama model missing (install Qwen 2.5 1.5B or 3B in Settings → AI Models)")
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
}
