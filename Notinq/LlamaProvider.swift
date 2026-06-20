import Foundation

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

    init?(modelPath: String, config: AIRuntimeConfig.Llama) {
        let params = PLLlamaParams(
            n_threads: config.threads,
            n_ctx: config.contextSize,
            n_gpu_layers: config.gpuLayers,
            temperature: config.temperature,
            top_p: config.topP,
            repeat_penalty: config.repeatPenalty
        )

        let created: UnsafeMutableRawPointer? = modelPath.withCString { cString in
            PLLlamaCreateWithParams(cString, params)
        }
        guard let created else {
            return nil
        }
        self.handle = created
    }

    func cancelGeneration() {
        guard let handle else { return }
        PLLamaCancelGeneration(handle)
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

            let callback: (@convention(c) (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void) = { tokenPtr, userData in
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

    private let workQueue = DispatchQueue(label: "notinq.llama.provider.work", qos: .userInitiated)

    private init() {}

    private func cappedPrompt(_ prompt: String) -> String {
        let maxChars = max(1_800, Int(AIRuntimeConfig.current.llama.contextSize) * 3)
        guard prompt.count > maxChars else { return prompt }

        let headCount = min(2_000, maxChars / 3)
        let tailCount = maxChars - headCount
        let head = String(prompt.prefix(headCount))
        let tail = String(prompt.suffix(tailCount))
        return head + "\n\n[Context truncated for performance]\n\n" + tail
    }

    func unloadModel() {
        AIModelManager.shared.unloadLlama(reason: "manual")
    }

    func run(prompt: String, completion: @escaping (String) -> Void) {
        run(prompt: prompt, maxTokens: AIRuntimeConfig.current.llama.maxTokens, completion: completion)
    }

    func run(prompt: String, maxTokens: Int32, completion: @escaping (String) -> Void) {
        workQueue.async {
            guard AIModelManager.shared.beginInference() else {
                DispatchQueue.main.async {
                    completion("Busy generating. Try again in a moment.")
                }
                return
            }
            defer { AIModelManager.shared.endInference() }

            guard let ctx = AIModelManager.shared.currentLlamaContext() else {
                DispatchQueue.main.async {
                    completion("Unable to generate response.")
                }
                return
            }

            let started = CFAbsoluteTimeGetCurrent()
            let result = ctx.generate(prompt: self.cappedPrompt(prompt), maxTokens: maxTokens)
            DispatchQueue.main.async {
                let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
                AIPerfLog.debug("inference done (\(Int(elapsed))ms)")
                completion(result)
            }
        }
    }

    func runStreaming(
        prompt: String,
        maxTokens: Int32,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        workQueue.async {
            guard AIModelManager.shared.beginInference() else {
                DispatchQueue.main.async {
                    onToken("Busy generating. Try again in a moment.")
                    completion()
                }
                return
            }
            defer { AIModelManager.shared.endInference() }

            guard let ctx = AIModelManager.shared.currentLlamaContext() else {
                DispatchQueue.main.async {
                    onToken("Unable to generate response.")
                    completion()
                }
                return
            }

            let started = CFAbsoluteTimeGetCurrent()
            let success = ctx.generateStreaming(prompt: self.cappedPrompt(prompt), maxTokens: maxTokens) { token in
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
                let elapsed = (CFAbsoluteTimeGetCurrent() - started) * 1000
                AIPerfLog.debug("streaming inference done (\(Int(elapsed))ms)")
                completion()
            }
        }
    }
}
