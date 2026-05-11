import Foundation

@_silgen_name("PLLlamaBackendAvailable")
private func PLLlamaBackendAvailable() -> Bool

@_silgen_name("PLLlamaCreate")
private func PLLlamaCreate(_ modelPath: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?

@_silgen_name("PLLamaGenerate")
private func PLLamaGenerate(_ handle: UnsafeMutableRawPointer?, _ prompt: UnsafePointer<CChar>?, _ maxTokens: Int32) -> UnsafeMutablePointer<CChar>?

private typealias LlamaTokenCallback = @convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void

@_silgen_name("PLLamaGenerateStream")
private func PLLamaGenerateStream(
    _ handle: UnsafeMutableRawPointer?,
    _ prompt: UnsafePointer<CChar>?,
    _ maxTokens: Int32,
    _ callback: LlamaTokenCallback?,
    _ userData: UnsafeMutableRawPointer?
) -> Bool

@_silgen_name("PLLlamaDestroy")
private func PLLlamaDestroy(_ handle: UnsafeMutableRawPointer?)

@_silgen_name("PLLlamaFreeCString")
private func PLLlamaFreeCString(_ ptr: UnsafeMutablePointer<CChar>?)

final class LlamaContext {
    static func sanitizeOutputText(_ raw: String) -> String {
        var output = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        var deduped: [String] = []
        var previous = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if previous.isEmpty { continue }
                deduped.append("")
                previous = ""
                continue
            }
            if trimmed == previous { continue }
            deduped.append(trimmed)
            previous = trimmed
        }

        output = deduped.joined(separator: "\n")
        output = trimRepetitiveTail(output)
        output = trimDanglingEnding(output)
        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimRepetitiveTail(_ text: String) -> String {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        guard sentences.count > 4 else { return text }

        var seen = Set<String>()
        var kept: [String] = []
        for sentence in sentences {
            let normalized = sentence
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if seen.contains(normalized) { continue }
            seen.insert(normalized)
            kept.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard !kept.isEmpty else { return text }
        return kept.joined(separator: ". ") + "."
    }

    private static func trimDanglingEnding(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let danglingWords = ["and", "or", "but", "so", "because", "with", "for", "to", "of", "in", "on", "at", "as", "by", "from"]
        let words = trimmed.split(separator: " ")
        if let last = words.last?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")),
           danglingWords.contains(last) {
            return words.dropLast().joined(separator: " ")
        }

        if trimmed.range(of: #"[.!?]["')\]]?$"#, options: .regularExpression) != nil {
            return trimmed
        }

        let sentenceEndings = [".", "!", "?"]
        let endIndexes = sentenceEndings.compactMap { trimmed.lastIndex(of: Character($0)) }
        guard let lastEnd = endIndexes.max() else { return trimmed }
        return String(trimmed[...lastEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class StreamingCallbackBox {
        let onToken: (String) -> Void
        var generatedLength: Int = 0

        init(onToken: @escaping (String) -> Void) {
            self.onToken = onToken
        }
    }

    private var handle: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "llama.serial.queue", qos: .userInitiated)

    init?(modelPath: String) {
        let created: UnsafeMutableRawPointer? = modelPath.withCString { cString in
            PLLlamaCreate(cString)
        }
        guard let created else {
            return nil
        }
        self.handle = created
    }

    func generate(prompt: String, maxTokens: Int32 = 300) -> String {
        var collected = ""
        let completed = generateStreaming(prompt: prompt, maxTokens: maxTokens) { token in
            collected += token
        }
        let cleaned = Self.sanitizeOutputText(collected)
        return completed && !cleaned.isEmpty ? cleaned : "Unable to generate response."
    }

    func generateStreaming(prompt: String, maxTokens: Int32 = 300, onToken: @escaping (String) -> Void) -> Bool {
        queue.sync {
            guard let handle else {
                return false
            }

            let wrappedPrompt = "You are a concise and helpful writing assistant. Complete your final sentence naturally. Avoid repetition.\n\n\(prompt)"
            print("[Llama] prompt received (\(wrappedPrompt.count) chars)")
            print("[Llama] inference started")

            let callbackBox = StreamingCallbackBox(onToken: onToken)
            let callbackPointer = Unmanaged.passRetained(callbackBox).toOpaque()
            defer { Unmanaged<StreamingCallbackBox>.fromOpaque(callbackPointer).release() }

            let callback: LlamaTokenCallback = { tokenPtr, userData in
                guard let userData, let tokenPtr else { return }
                let box = Unmanaged<StreamingCallbackBox>.fromOpaque(userData).takeUnretainedValue()
                let token = String(cString: tokenPtr)
                box.generatedLength += token.count
                box.onToken(token)
            }

            let completed: Bool = wrappedPrompt.withCString { promptCString in
                PLLamaGenerateStream(handle, promptCString, maxTokens, callback, callbackPointer)
            }

            print("[Llama] generated text length: \(callbackBox.generatedLength)")
            print("[Llama] inference completed")
            return completed
        }
    }

    func shutdown() {
        queue.sync {
            if let handle {
                PLLlamaDestroy(handle)
                self.handle = nil
            }
        }
    }

    deinit {
        shutdown()
    }
}

final class LlamaProvider: AIProvider {
    static let shared = LlamaProvider()

    private var context: LlamaContext?

    private init() {
        loadModel()
    }

    private func loadModel() {
        guard PLLlamaBackendAvailable() else {
            print("[Llama] backend unavailable")
            context = nil
            return
        }

        let path = Bundle.main.path(forResource: "Qwen2.5-3B-Instruct-Q4_K_M", ofType: "gguf")

        guard let path else {
            print("[Llama] model not found in bundle")
            context = nil
            return
        }

        context = LlamaContext(modelPath: path)
        if context != nil {
            print("[Llama] model loaded successfully: \(path)")
        } else {
            print("[Llama] failed to initialize model context")
        }
    }

    func run(prompt: String, completion: @escaping (String) -> Void) {
        run(prompt: prompt, maxTokens: 300, completion: completion)
    }

    func run(prompt: String, maxTokens: Int32, completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let ctx = self.context else {
                DispatchQueue.main.async {
                    completion("Unable to generate response.")
                }
                return
            }

            let result = ctx.generate(prompt: prompt, maxTokens: maxTokens)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func runStreaming(
        prompt: String,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        runStreaming(prompt: prompt, maxTokens: 300, onToken: onToken, completion: completion)
    }

    func runStreaming(
        prompt: String,
        maxTokens: Int32,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let ctx = self.context else {
                DispatchQueue.main.async {
                    onToken("Unable to generate response.")
                    completion()
                }
                return
            }

            let success = ctx.generateStreaming(prompt: prompt, maxTokens: maxTokens) { token in
                DispatchQueue.main.async {
                    let cleanedToken = token.replacingOccurrences(of: "\r", with: "")
                    if !cleanedToken.contains("<|") && !cleanedToken.contains("|>") {
                        onToken(cleanedToken)
                    }
                }
            }

            DispatchQueue.main.async {
                if !success {
                    onToken("Unable to generate response.")
                }
                completion()
            }
        }
    }
}
