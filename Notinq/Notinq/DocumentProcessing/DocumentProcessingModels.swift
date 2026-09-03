import Foundation
import CryptoKit

enum DocumentBlockKind: String, Codable, CaseIterable, Sendable {
    case heading
    case paragraph
    case bulletedList
    case numberedList
    case table
    case codeBlock
    case equation
    case quote
}

enum DocumentListStyle: String, Codable, CaseIterable, Sendable {
    case bullet
    case numbered
}

enum DocumentReadingDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case moderate
    case challenging
    case advanced
}

enum TokenEstimationMethod: String, Codable, CaseIterable, Sendable {
    case approximateWordRatio
    case approximateCharacterRatio
}

struct DocumentMetadata: Codable, Equatable, Sendable {
    var documentID: String = ""
    var title: String = ""
    var sourceKind: String = "note"
    var contentHash: String = ""
    var normalizedCharacterCount: Int = 0
    var lineCount: Int = 0
    var processedAt: Date = Date()
    var processingVersion: String = "v2"
}

struct DocumentBlock: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var kind: DocumentBlockKind
    var content: String
    var normalizedContent: String
    var startLine: Int
    var endLine: Int
    var headingLevel: Int?
    var listStyle: DocumentListStyle?
    var listItems: [String] = []
    var tableRows: [[String]] = []
    var codeLanguage: String?
    var equation: String?
    var quoteLevel: Int = 0
    var sectionID: String?
}

struct DocumentSectionComplexity: Codable, Equatable, Sendable {
    var sectionID: String
    var readingDifficulty: DocumentReadingDifficulty
    var conceptDensity: Double
    var estimatedStudyMinutes: Int
    var tokenEstimate: Int
    var blockCount: Int
}

struct DocumentStatistics: Codable, Equatable, Sendable {
    var characterCount: Int = 0
    var normalizedCharacterCount: Int = 0
    var wordCount: Int = 0
    var sentenceCount: Int = 0
    var lineCount: Int = 0
    var blankLineCount: Int = 0
    var blockCount: Int = 0
    var sectionCount: Int = 0
    var headingCount: Int = 0
    var paragraphCount: Int = 0
    var bulletedListCount: Int = 0
    var numberedListCount: Int = 0
    var tableCount: Int = 0
    var codeBlockCount: Int = 0
    var equationCount: Int = 0
    var quoteCount: Int = 0
}

struct DocumentBlockTokenEstimate: Codable, Equatable, Sendable {
    var blockID: String
    var blockIndex: Int
    var kind: DocumentBlockKind
    var estimatedTokens: Int
}

struct DocumentSectionTokenEstimate: Codable, Equatable, Sendable {
    var sectionID: String
    var sectionIndex: Int
    var estimatedTokens: Int
    var startBlockIndex: Int
    var endBlockIndex: Int
}

struct DocumentChunkBoundary: Codable, Equatable, Sendable {
    var startBlockIndex: Int
    var endBlockIndex: Int
    var estimatedTokens: Int
    var sectionID: String?
    var isHardBoundary: Bool
}

struct DocumentTokenEstimate: Codable, Equatable, Sendable {
    var estimatedTotalTokens: Int = 0
    var blockEstimates: [DocumentBlockTokenEstimate] = []
    var sectionEstimates: [DocumentSectionTokenEstimate] = []
    var suggestedChunkBoundaries: [DocumentChunkBoundary] = []
    var method: TokenEstimationMethod = .approximateWordRatio
    var targetChunkSize: Int = 320
}

struct DocumentComplexityEstimate: Codable, Equatable, Sendable {
    var readingDifficulty: DocumentReadingDifficulty = .moderate
    var conceptDensity: Double = 0
    var estimatedStudyMinutes: Int = 0
    var structuralDensity: Double = 0
    var tokenEstimate: Int = 0
    var headingCount: Int = 0
    var listCount: Int = 0
    var codeBlockCount: Int = 0
    var equationCount: Int = 0
    var tableCount: Int = 0
    var sentenceCount: Int = 0
    var averageSentenceLength: Double = 0
    var complexityScore: Double = 0
    var sectionCount: Int = 0
    var sectionMetrics: [DocumentSectionComplexity] = []
}

struct DocumentStructure: Codable, Equatable, Sendable {
    var title: String
    var originalText: String
    var normalizedText: String
    var cleanedText: String
    var sourceSignature: String
    var metadata: DocumentMetadata = DocumentMetadata()
    var blocks: [DocumentBlock] = []
    var sections: [DocumentSection]
    var headings: [String]
    var lists: [DocumentListItem]
    var codeBlocks: [DocumentCodeBlock]
    var equations: [String]
    var tables: [DocumentTable]
    var statistics: DocumentStatistics = DocumentStatistics()
    var complexity: DocumentComplexityEstimate
    var tokenEstimate: DocumentTokenEstimate = DocumentTokenEstimate()

    var chunkBoundaries: [DocumentChunkBoundary] {
        tokenEstimate.suggestedChunkBoundaries
    }
}

struct ProcessedDocument: Codable, Equatable, Sendable {
    var title: String
    var originalText: String
    var normalizedText: String
    var lines: [String]
    var contentHash: String
}

extension ProcessedDocument {
    static func contentHash(for title: String, text: String) -> String {
        let payload = [title.trimmingCharacters(in: .whitespacesAndNewlines), text].joined(separator: "\u{241E}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
