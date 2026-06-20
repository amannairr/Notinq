import Foundation
import NaturalLanguage

protocol EmbeddingBackend {
    func embedding(for text: String) -> [Float]?
}

enum SemanticGrade: String, Codable {
    case correct
    case mostlyCorrect
    case partialUnderstanding
    case incorrect

    var title: String {
        switch self {
        case .correct:
            return "Correct"
        case .mostlyCorrect:
            return "Mostly Correct"
        case .partialUnderstanding:
            return "Partial Understanding"
        case .incorrect:
            return "Incorrect"
        }
    }
}

struct SemanticEvaluation: Codable, Equatable {
    var grade: SemanticGrade
    var score: Double
    var similarity: Double
    var keywordOverlap: Double
    var feedback: String
}

final class EmbeddingService: EmbeddingProvider {
    static let shared = EmbeddingService()

    private let backend: any EmbeddingBackend
    private let cacheQueue = DispatchQueue(label: "notinq.embedding.cache", qos: .userInitiated)
    private var cache: [String: [Float]] = [:]

    private init(backend: (any EmbeddingBackend)? = nil) {
        self.backend = backend ?? MiniLMEmbeddingBackend()
    }

    func embedding(for text: String) -> [Float]? {
        let key = Self.cacheKey(for: text)

        if let cached = cacheQueue.sync(execute: { cache[key] }) {
            return cached
        }

        guard let vector = backend.embedding(for: text), !vector.isEmpty else {
            return nil
        }

        cacheQueue.sync {
            cache[key] = vector
        }

        return vector
    }

    func similarity(between first: String, and second: String) -> Float {
        guard let firstVector = embedding(for: first),
              let secondVector = embedding(for: second) else {
            return 0
        }
        return cosineSimilarity(firstVector, secondVector)
    }

    func similarity(between first: [String], and second: [String]) -> Float {
        let lhs = first.joined(separator: " ")
        let rhs = second.joined(separator: " ")
        return similarity(between: lhs, and: rhs)
    }

    func evaluate(userAnswer: String, correctAnswer: String, keywords: [String] = []) -> SemanticEvaluation {
        let normalizedUser = Self.normalize(userAnswer)
        let normalizedCorrect = Self.normalize(correctAnswer)

        if !normalizedUser.isEmpty, normalizedUser == normalizedCorrect {
            return SemanticEvaluation(
                grade: .correct,
                score: 1.0,
                similarity: 1.0,
                keywordOverlap: 1.0,
                feedback: "Exact match."
            )
        }

        let similarityScore = Double(similarity(between: normalizedUser, and: normalizedCorrect))
        let keywordOverlap = keywordOverlapScore(answer: normalizedUser, keywords: keywords)
        let blendedScore = max(similarityScore, keywordOverlap)

        switch blendedScore {
        case 0.90...:
            return SemanticEvaluation(
                grade: .correct,
                score: 1.0,
                similarity: similarityScore,
                keywordOverlap: keywordOverlap,
                feedback: "The answer is conceptually equivalent."
            )
        case 0.75..<0.90:
            return SemanticEvaluation(
                grade: .mostlyCorrect,
                score: 0.85,
                similarity: similarityScore,
                keywordOverlap: keywordOverlap,
                feedback: "Mostly correct. The concept is right, but the wording or one detail is different."
            )
        case 0.60..<0.75:
            return SemanticEvaluation(
                grade: .partialUnderstanding,
                score: 0.70,
                similarity: similarityScore,
                keywordOverlap: keywordOverlap,
                feedback: "Partial understanding. The answer overlaps with the expected concept, but misses a key piece."
            )
        default:
            if keywordOverlap >= 0.50 {
                return SemanticEvaluation(
                    grade: .partialUnderstanding,
                    score: 0.60,
                    similarity: similarityScore,
                    keywordOverlap: keywordOverlap,
                    feedback: "The answer uses relevant keywords, but the concept is incomplete."
                )
            }

            return SemanticEvaluation(
                grade: .incorrect,
                score: 0.0,
                similarity: similarityScore,
                keywordOverlap: keywordOverlap,
                feedback: "The answer does not match the expected concept closely enough."
            )
        }
    }

    private func keywordOverlapScore(answer: String, keywords: [String]) -> Double {
        let normalizedKeywords = keywords.map { Self.normalize($0) }.filter { !$0.isEmpty }
        guard !normalizedKeywords.isEmpty else { return 0 }

        let matched = normalizedKeywords.filter { answer.contains($0) }
        return Double(matched.count) / Double(normalizedKeywords.count)
    }

    private static func cacheKey(for text: String) -> String {
        normalize(text)
    }

    static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class MiniLMEmbeddingBackend: EmbeddingBackend {
    private let naturalLanguageEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
    private let fallbackDimension = 384

    func embedding(for text: String) -> [Float]? {
        let normalized = EmbeddingService.normalize(text)
        guard !normalized.isEmpty else { return nil }

        if let naturalLanguageEmbedding,
           let vector = naturalLanguageEmbedding.vector(for: normalized) {
            return vector.map { Float($0) }
        }

        return hashedEmbedding(for: normalized)
    }

    private func hashedEmbedding(for text: String) -> [Float] {
        var vector = Array(repeating: Float(0), count: fallbackDimension)
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return vector }

        for (index, token) in tokens.enumerated() {
            let bucket = abs(token.hashValue) % fallbackDimension
            vector[bucket] += 1

            if index > 0 {
                let bigram = "\(tokens[index - 1]) \(token)"
                let bigramBucket = abs(bigram.hashValue) % fallbackDimension
                vector[bigramBucket] += 0.75
            }
        }

        let norm = sqrt(vector.map { $0 * $0 }.reduce(0, +))
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }
}
