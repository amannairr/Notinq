import Foundation
import AppKit

struct AIModelDefinition: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileName: String
    let tier: AICapabilityTier
    let summary: String
    let downloadURL: URL?
    let bundledSubdirectory: String?

    var suggestedFileURL: URL {
        AIModelLibrary.modelsDirectoryURL().appendingPathComponent(fileName)
    }

    var bundledResourceURL: URL? {
        let resourceName = (fileName as NSString).deletingPathExtension
        let resourceExtension = (fileName as NSString).pathExtension
        if let subdirectory = bundledSubdirectory,
           let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        return nil
    }

    var sourceStatusTitle: String {
        if bundledResourceURL != nil {
            return "Bundled"
        }
        if downloadURL != nil {
            return "Downloadable"
        }
        return "Unavailable"
    }
}

struct AIInstalledModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let fileURL: URL
    let fileSizeBytes: Int64
    let tierHint: AICapabilityTier?
    let sourceDefinitionID: String?

    var isCatalogMatched: Bool {
        sourceDefinitionID != nil
    }
}

struct AIModelLibrarySnapshot: Sendable {
    let capability: AICapabilitySnapshot
    let catalog: [AIModelDefinition]
    let installedModels: [AIInstalledModel]
    let preferredModelID: String?
    let storageUsageBytes: Int64
}

enum AIModelLibraryError: LocalizedError {
    case downloadUnavailable
    case sourceMissing
    case deleteFailed
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .downloadUnavailable:
            return "A download URL is not configured for this model."
        case .sourceMissing:
            return "The selected model file could not be found."
        case .deleteFailed:
            return "The model could not be deleted."
        case .modelNotFound:
            return "The model could not be found."
        }
    }
}

final class AIModelLibrary {
    static let shared = AIModelLibrary()

    private let defaults = UserDefaults.standard
    private let preferredModelKey = "notinq.preferredAIModelID"
    private let catalog: [AIModelDefinition] = [
        AIModelDefinition(
            id: "qwen-2.5-1.5b",
            displayName: "Qwen 2.5 1.5B Instruct",
            fileName: "Qwen2.5-1.5B-Instruct-Q4_K_M.gguf",
            tier: .standard,
            summary: "Default low-RAM local generation model.",
            downloadURL: nil,
            bundledSubdirectory: nil
        ),
        AIModelDefinition(
            id: "qwen-2.5-3b",
            displayName: "Qwen 2.5 3B Instruct",
            fileName: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            tier: .advanced,
            summary: "Optional higher-quality local generation model.",
            downloadURL: nil,
            bundledSubdirectory: "Models"
        )
    ]

    private init() {
        _ = ensureModelsDirectoryExists()
        if defaults.string(forKey: preferredModelKey) == nil {
            defaults.set("qwen-2.5-1.5b", forKey: preferredModelKey)
        }
    }

    static func modelsDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support").expandingTildeInPath, isDirectory: true)
        return baseDirectory.appendingPathComponent("Notinq", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    var preferredModelID: String? {
        defaults.string(forKey: preferredModelKey)
    }

    func refreshSnapshot() -> AIModelLibrarySnapshot {
        AIModelLibrarySnapshot(
            capability: AICapabilityManager.shared.snapshot,
            catalog: catalog,
            installedModels: installedModels(),
            preferredModelID: preferredModelID,
            storageUsageBytes: storageUsageBytes()
        )
    }

    func installedModels() -> [AIInstalledModel] {
        let directory = Self.modelsDirectoryURL()
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .compactMap { url in
                let size = fileSize(at: url)
                let filename = url.deletingPathExtension().lastPathComponent
                let definition = definition(matching: url)
                return AIInstalledModel(
                    id: installedIdentifier(for: url, definition: definition),
                    displayName: definition?.displayName ?? filename.replacingOccurrences(of: "-", with: " "),
                    fileURL: url,
                    fileSizeBytes: size,
                    tierHint: definition?.tier,
                    sourceDefinitionID: definition?.id
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func storageUsageBytes() -> Int64 {
        installedModels().reduce(0) { $0 + $1.fileSizeBytes }
    }

    func verifyModelExists(id: String) -> Bool {
        installedModels().contains(where: { $0.id == id })
    }

    func installedModel(for id: String) -> AIInstalledModel? {
        installedModels().first(where: { $0.id == id })
    }

    func selectPreferredModel(id: String?) {
        if let id {
            defaults.set(id, forKey: preferredModelKey)
        } else {
            defaults.removeObject(forKey: preferredModelKey)
        }
        NotificationCenter.default.post(name: .notinqAIModelsDidChange, object: nil)
    }

    func bestInstalledModelURL(for tier: AICapabilityTier) -> URL? {
        if let preferredID = preferredModelID,
           let preferred = installedModel(for: preferredID) {
            return preferred.fileURL
        }

        let installed = installedModels()
        switch tier {
        case .basic, .standard:
            if let exact = installed.first(where: { $0.sourceDefinitionID == "qwen-2.5-1.5b" }) {
                return exact.fileURL
            }
            return installed.first(where: { record in
                record.displayName.localizedCaseInsensitiveContains("1.5b")
                    || record.displayName.localizedCaseInsensitiveContains("1b")
                    || record.fileURL.lastPathComponent.localizedCaseInsensitiveContains("1.5b")
                    || record.fileURL.lastPathComponent.localizedCaseInsensitiveContains("1b")
            })?.fileURL
        case .advanced:
            if let exact = installed.first(where: { $0.sourceDefinitionID == "qwen-2.5-3b" }) {
                return exact.fileURL
            }
            if let fallback = installed.first(where: { record in
                record.displayName.localizedCaseInsensitiveContains("3b")
                    || record.fileURL.lastPathComponent.localizedCaseInsensitiveContains("3b")
            }) {
                return fallback.fileURL
            }
            return installed.first(where: { $0.sourceDefinitionID == "qwen-2.5-1.5b" })?.fileURL
        }
    }

    func activeModelDescription(for tier: AICapabilityTier) -> String {
        if let url = bestInstalledModelURL(for: tier) {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Not installed"
    }

    func installModel(from sourceURL: URL, preferred: Bool = true) throws -> AIInstalledModel {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw AIModelLibraryError.sourceMissing
        }

        let definition = definition(matching: sourceURL)
        let destinationURL = destinationURL(for: sourceURL, definition: definition)
        _ = ensureModelsDirectoryExists()

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let installed = AIInstalledModel(
            id: installedIdentifier(for: destinationURL, definition: definition),
            displayName: definition?.displayName ?? destinationURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "),
            fileURL: destinationURL,
            fileSizeBytes: fileSize(at: destinationURL),
            tierHint: definition?.tier,
            sourceDefinitionID: definition?.id
        )

        if preferred {
            defaults.set(installed.id, forKey: preferredModelKey)
        }
        NotificationCenter.default.post(name: .notinqAIModelsDidChange, object: nil)
        return installed
    }

    func installBundledModel(id: String, preferred: Bool = true) throws -> AIInstalledModel {
        guard let definition = catalogDefinition(for: id) else {
            throw AIModelLibraryError.modelNotFound
        }
        guard let sourceURL = definition.bundledResourceURL else {
            throw AIModelLibraryError.sourceMissing
        }
        return try installModel(from: sourceURL, preferred: preferred)
    }

    func downloadModel(_ definition: AIModelDefinition) async throws -> AIInstalledModel {
        if let remoteURL = definition.downloadURL {
            let (tempURL, _) = try await URLSession.shared.download(from: remoteURL)
            let destinationURL = definition.suggestedFileURL

            _ = ensureModelsDirectoryExists()
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)

            let installed = AIInstalledModel(
                id: definition.id,
                displayName: definition.displayName,
                fileURL: destinationURL,
                fileSizeBytes: fileSize(at: destinationURL),
                tierHint: definition.tier,
                sourceDefinitionID: definition.id
            )

            defaults.set(definition.id, forKey: preferredModelKey)
            NotificationCenter.default.post(name: .notinqAIModelsDidChange, object: nil)
            return installed
        }

        guard let sourceURL = definition.bundledResourceURL else {
            throw AIModelLibraryError.downloadUnavailable
        }
        return try installModel(from: sourceURL, preferred: true)
    }

    func deleteModel(id: String) throws {
        guard let model = installedModel(for: id) else {
            throw AIModelLibraryError.modelNotFound
        }

        do {
            try FileManager.default.removeItem(at: model.fileURL)
            if preferredModelID == id {
                defaults.removeObject(forKey: preferredModelKey)
            }
            NotificationCenter.default.post(name: .notinqAIModelsDidChange, object: nil)
        } catch {
            throw AIModelLibraryError.deleteFailed
        }
    }

    func catalogDefinition(for id: String) -> AIModelDefinition? {
        catalog.first(where: { $0.id == id })
    }

    func preferredModelURL(for tier: AICapabilityTier) -> URL? {
        bestInstalledModelURL(for: tier)
    }

    func preferredCatalogModel(for tier: AICapabilityTier) -> AIModelDefinition? {
        switch tier {
        case .basic, .standard:
            return catalog.first(where: { $0.id == "qwen-2.5-1.5b" })
        case .advanced:
            return catalog.first(where: { $0.id == "qwen-2.5-3b" })
                ?? catalog.first(where: { $0.id == "qwen-2.5-1.5b" })
        }
    }

    private func ensureModelsDirectoryExists() -> Bool {
        let directory = Self.modelsDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    private func definition(matching url: URL) -> AIModelDefinition? {
        let fileName = url.deletingPathExtension().lastPathComponent.lowercased()
        let baseName = url.lastPathComponent.lowercased()

        return catalog.first(where: { definition in
            let candidate = definition.fileName.lowercased().replacingOccurrences(of: ".gguf", with: "")
            return fileName == candidate
                || baseName == definition.fileName.lowercased()
                || baseName.contains(candidate)
                || fileName.contains(definition.id.lowercased())
        })
    }

    private func destinationURL(for sourceURL: URL, definition: AIModelDefinition?) -> URL {
        if let definition {
            return definition.suggestedFileURL
        }
        return Self.modelsDirectoryURL().appendingPathComponent(sourceURL.lastPathComponent)
    }

    private func installedIdentifier(for url: URL, definition: AIModelDefinition?) -> String {
        definition?.id ?? url.deletingPathExtension().lastPathComponent.lowercased()
    }

    private func fileSize(at url: URL) -> Int64 {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }
}

extension Notification.Name {
    static let notinqAIModelsDidChange = Notification.Name("notinq.ai.modelsDidChange")
}
