import Foundation

enum StudyResponseParser {
    static func parseUnifiedStudyMaterials(from response: String, source: StudyGenerationSource = .standard) -> StudyGenerationArtifacts {
        if let decoded: StudyGenerationArtifacts = decodeJSON(from: response) {
            var artifacts = decoded
            artifacts.source = source
            return artifacts
        }

        return StudyGenerationArtifacts(
            flashcards: parseStudyFlashcards(from: response),
            quizQuestions: parseStudyQuiz(from: response),
            tutorQuestions: parseTutorQuestions(from: response),
            insights: parseStudyInsights(from: response),
            source: source
        )
    }

    static func parseStudyFlashcards(from response: String) -> [StudyFlashcard] {
        if let decoded: [StudyFlashcard] = decodeJSON(from: response) {
            return decoded
        }
        if let decoded: [StudyFlashcard] = decodeJSON(from: extractSectionPayload(from: response, sectionTitles: ["flashcards", "cards"])) {
            return decoded
        }

        return extractBlocks(from: response).compactMap { block in
            let fields = keyValueFields(from: block)
            let front = fields["front", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let back = fields["back", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { return nil }

            return StudyFlashcard(
                type: parseFlashcardType(from: fields["type", default: ""].lowercased()),
                front: front,
                back: back,
                whyItMatters: fields["why", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func parseStudyQuiz(from response: String) -> [StudyQuizQuestion] {
        if let decoded: [StudyQuizQuestion] = decodeJSON(from: response) {
            return decoded
        }

        let quizPayload = extractSectionPayload(
            from: response,
            sectionTitles: ["mcqs", "multiple choice questions", "multiple choice", "quiz questions", "short answer questions", "short answer", "free response questions"]
        )
        if let decoded: [StudyQuizQuestion] = decodeJSON(from: quizPayload) {
            return decoded
        }

        return extractBlocks(from: response).compactMap { block in
            let fields = keyValueFields(from: block)
            let prompt = fields["prompt", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else { return nil }

            let type = parseQuizQuestionType(from: fields["type", default: ""].lowercased())
            let options = [
                fields["optiona", default: ""],
                fields["optionb", default: ""],
                fields["optionc", default: ""],
                fields["optiond", default: ""]
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

            let rawAnswer = fields["answer", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedAnswer: String
            switch type {
            case .multipleChoice:
                normalizedAnswer = resolveMultipleChoiceAnswer(rawAnswer, options: options)
            case .trueFalse:
                normalizedAnswer = normalizeTrueFalseAnswer(rawAnswer)
            case .shortAnswer:
                normalizedAnswer = rawAnswer
            @unknown default:
                normalizedAnswer = rawAnswer
            }

            guard !normalizedAnswer.isEmpty else { return nil }

            return StudyQuizQuestion(
                type: type,
                prompt: prompt,
                options: type == .trueFalse && options.isEmpty ? ["True", "False"] : options,
                correctAnswer: normalizedAnswer,
                explanation: fields["explanation", default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                keywords: fields["keywords", default: ""]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }
    }

    static func parseTutorQuestions(from response: String) -> [StudyTutorQuestion] {
        if let decoded: [StudyTutorQuestion] = decodeJSON(from: response) {
            return decoded
        }
        if let decoded: [StudyTutorQuestion] = decodeJSON(from: extractSectionPayload(from: response, sectionTitles: ["short answer questions", "short answer", "free response questions"])) {
            return decoded
        }

        return extractBlocks(from: response).compactMap { block in
            let fields = keyValueFields(from: block)
            let prompt = fields["prompt", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            let expectedAnswer = fields["expectedanswer", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, !expectedAnswer.isEmpty else { return nil }

            return StudyTutorQuestion(
                prompt: prompt,
                expectedAnswer: expectedAnswer,
                keyPoints: fields["keypoints", default: ""]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                explanation: fields["explanation", default: ""].trimmingCharacters(in: .whitespacesAndNewlines),
                concept: fields["concept", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func parseStudyInsights(from response: String) -> StudyInsights {
        if let decoded: StudyInsights = decodeJSON(from: response) {
            return decoded
        }

        let payload = extractSectionPayload(from: response, sectionTitles: ["insights", "study insights"])
        if let decoded: StudyInsights = decodeJSON(from: payload) {
            return decoded
        }

        return StudyInsights(
            keyConcepts: parseListSection(title: "key concepts", from: response),
            importantConcepts: parseListSection(title: "important concepts", from: response),
            potentialExamTopics: parseListSection(title: "potential exam topics", from: response),
            knowledgeGaps: parseListSection(title: "knowledge gaps", from: response)
        )
    }

    private static func decodeJSON<T: Decodable>(from response: String) -> T? {
        guard let data = jsonPayloadData(from: response) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func jsonPayloadData(from response: String) -> Data? {
        let normalized = response
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if let fenced = extractFencedJSON(from: normalized) {
            return fenced.data(using: .utf8)
        }

        if let objectRange = balancedJSONRange(in: normalized, opening: "{", closing: "}") {
            return String(normalized[objectRange]).data(using: .utf8)
        }

        if let arrayRange = balancedJSONRange(in: normalized, opening: "[", closing: "]") {
            return String(normalized[arrayRange]).data(using: .utf8)
        }

        return nil
    }

    private static func extractFencedJSON(from response: String) -> String? {
        let lines = response.components(separatedBy: "\n")
        guard let startIndex = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.hasPrefix("```json") || trimmed == "```"
        }) else {
            return nil
        }

        let tail = lines.dropFirst(startIndex + 1)
        guard let endIndex = tail.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "```" }) else {
            return nil
        }
        return tail.prefix(endIndex).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func balancedJSONRange(in response: String, opening: Character, closing: Character) -> Range<String.Index>? {
        guard let start = response.firstIndex(of: opening) else { return nil }
        var depth = 0
        var index = start

        while index < response.endIndex {
            let character = response[index]
            if character == opening {
                depth += 1
            } else if character == closing {
                depth -= 1
                if depth == 0 {
                    return start..<response.index(after: index)
                }
            }
            index = response.index(after: index)
        }

        return nil
    }

    private static func extractBlocks(from response: String) -> [String] {
        let normalized = response
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let separated = normalized
            .components(separatedBy: "---")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if separated.count > 1 {
            return separated
        }

        return normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func keyValueFields(from block: String) -> [String: String] {
        var fields: [String: String] = [:]

        for rawLine in block.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = line.firstIndex(of: ":") else { continue }

            let key = line[..<separator].lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = value
        }

        return fields
    }

    private static func extractSectionPayload(from response: String, sectionTitles: [String]) -> String {
        let lines = response
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        let normalizedTitles = Set(sectionTitles.map { normalizedSectionHeading($0) })
        var isCapturing = false
        var captured: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedLine = normalizedSectionHeading(line)

            if normalizedTitles.contains(normalizedLine) {
                isCapturing = true
                continue
            }

            if isCapturing {
                let headerCandidate = normalizedLine.hasSuffix(":") && !normalizedLine.hasPrefix("-")
                if headerCandidate && !normalizedLine.hasPrefix("type:")
                    && !normalizedLine.hasPrefix("prompt:")
                    && !normalizedLine.hasPrefix("option")
                    && !normalizedLine.hasPrefix("answer:")
                    && !normalizedLine.hasPrefix("explanation:")
                    && !normalizedLine.hasPrefix("keywords:")
                    && !normalizedLine.hasPrefix("front:")
                    && !normalizedLine.hasPrefix("back:")
                    && !normalizedLine.hasPrefix("why:")
                    && !normalizedLine.hasPrefix("expectedanswer:")
                    && !normalizedLine.hasPrefix("keypoints:")
                    && !normalizedLine.hasPrefix("concept:") {
                    break
                }
                captured.append(rawLine)
            }
        }

        return captured.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedSectionHeading(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[#>\\-\\s]+", with: "", options: .regularExpression)
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
    }

    private static func parseListSection(title: String, from response: String) -> [String] {
        let lines = response
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var isCapturing = false
        var items: [String] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line
                .replacingOccurrences(of: "^[#>\\-\\s]+", with: "", options: .regularExpression)
                .lowercased()

            if lowercased.hasPrefix(title) {
                isCapturing = true
                continue
            }

            if isCapturing && lowercased.hasSuffix(":") && !lowercased.hasPrefix("-") {
                break
            }

            guard isCapturing else { continue }
            guard line.hasPrefix("-") else { continue }

            let item = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty {
                items.append(item)
            }
        }

        return items
    }

    private static func parseFlashcardType(from value: String) -> StudyCardType {
        if value.contains("definition") { return .definition }
        if value.contains("cloze") { return .cloze }
        if value.contains("concept") { return .concept }
        return .questionAnswer
    }

    private static func parseQuizQuestionType(from value: String) -> StudyQuizQuestionType {
        if value.contains("multiple") || value.contains("choice") || value.contains("mcq") {
            return .multipleChoice
        }
        if value.contains("true") || value.contains("false") {
            return .trueFalse
        }
        return .shortAnswer
    }

    private static func normalizeTrueFalseAnswer(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("true") {
            return "True"
        }
        if normalized.contains("false") {
            return "False"
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveMultipleChoiceAnswer(_ rawAnswer: String, options: [String]) -> String {
        let trimmed = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if options.contains(trimmed) {
            return trimmed
        }

        if let scalar = trimmed.uppercased().unicodeScalars.first,
           scalar.value >= UnicodeScalar("A").value,
           scalar.value <= UnicodeScalar("Z").value {
            let index = Int(scalar.value - UnicodeScalar("A").value)
            if options.indices.contains(index) {
                return options[index]
            }
        }

        if let matched = options.first(where: { normalizeResponseText($0) == normalizeResponseText(trimmed) }) {
            return matched
        }

        return trimmed
    }
}

private func normalizeResponseText(_ text: String) -> String {
    text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
