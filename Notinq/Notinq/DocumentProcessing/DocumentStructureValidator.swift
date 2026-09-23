import Foundation

enum DocumentStructureValidationError: LocalizedError, Equatable {
    case missingRequiredField(String)
    case invalidBlockOrdering(previousLine: Int, currentLine: Int)
    case invalidSectionHierarchy(sectionID: String, reason: String)
    case invalidSectionReference(sectionID: String, blockID: String)
    case invalidChunkBoundary(String)
    case inconsistentStatistics(String)
    case negativeStatistics(String)

    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidBlockOrdering(let previousLine, let currentLine):
            return "Invalid block ordering: line \(currentLine) follows line \(previousLine)"
        case .invalidSectionHierarchy(let sectionID, let reason):
            return "Invalid section hierarchy for \(sectionID): \(reason)"
        case .invalidSectionReference(let sectionID, let blockID):
            return "Invalid section reference: section \(sectionID) references unknown block \(blockID)"
        case .invalidChunkBoundary(let reason):
            return "Invalid chunk boundary: \(reason)"
        case .inconsistentStatistics(let reason):
            return "Inconsistent document statistics: \(reason)"
        case .negativeStatistics(let reason):
            return "Negative document statistics: \(reason)"
        }
    }
}

enum DocumentStructureValidator {
    static func validate(_ structure: DocumentStructure) throws {
        if structure.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentStructureValidationError.missingRequiredField("title")
        }
        if structure.sourceSignature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentStructureValidationError.missingRequiredField("sourceSignature")
        }
        if structure.metadata.contentHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentStructureValidationError.missingRequiredField("metadata.contentHash")
        }
        if structure.metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DocumentStructureValidationError.missingRequiredField("metadata.title")
        }

        try validateBlocks(structure.blocks)
        try validateSections(structure.sections, blocks: structure.blocks)
        try validateStatistics(structure.statistics, blocks: structure.blocks, sections: structure.sections)
        try validateComplexity(structure.complexity, sections: structure.sections)
        try validateTokenEstimate(structure.tokenEstimate, blocks: structure.blocks, sections: structure.sections)
    }

    private static func validateBlocks(_ blocks: [DocumentBlock]) throws {
        var lastLine = -1
        var seenIDs = Set<String>()
        for block in blocks {
            guard seenIDs.insert(block.id).inserted else {
                throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: block.id, reason: "Duplicate block identifier")
            }
            guard block.startLine >= 0, block.endLine >= block.startLine else {
                throw DocumentStructureValidationError.invalidChunkBoundary("Block \(block.id) has invalid line range")
            }
            guard block.startLine >= lastLine else {
                throw DocumentStructureValidationError.invalidBlockOrdering(previousLine: lastLine, currentLine: block.startLine)
            }
            lastLine = block.startLine
        }
    }

    private static func validateSections(_ sections: [DocumentSection], blocks: [DocumentBlock]) throws {
        let blockIDs = Set(blocks.map(\.id))
        var seenIDs = Set<String>()
        var sectionsByID: [String: DocumentSection] = [:]
        for section in sections {
            sectionsByID[section.id] = section
        }

        for section in sections {
            guard seenIDs.insert(section.id).inserted else {
                throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: section.id, reason: "Duplicate section identifier")
            }
            for blockID in section.blockIDs {
                guard blockIDs.contains(blockID) else {
                    throw DocumentStructureValidationError.invalidSectionReference(sectionID: section.id, blockID: blockID)
                }
            }
            if let parentID = section.parentID {
                guard let parent = sectionsByID[parentID] else {
                    throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: section.id, reason: "Missing parent section \(parentID)")
                }
                guard parent.level < section.level else {
                    throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: section.id, reason: "Parent level must be lower than child level")
                }
            }
            for childID in section.childIDs {
                guard let child = sectionsByID[childID] else {
                    throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: section.id, reason: "Missing child section \(childID)")
                }
                guard child.parentID == section.id else {
                    throw DocumentStructureValidationError.invalidSectionHierarchy(sectionID: section.id, reason: "Child \(childID) does not point back to its parent")
                }
            }
        }

        for block in blocks {
            if let sectionID = block.sectionID {
                guard sectionsByID[sectionID] != nil else {
                    throw DocumentStructureValidationError.invalidSectionReference(sectionID: sectionID, blockID: block.id)
                }
            }
        }
    }

    private static func validateStatistics(_ statistics: DocumentStatistics, blocks: [DocumentBlock], sections: [DocumentSection]) throws {
        let numericValues = [
            statistics.characterCount,
            statistics.normalizedCharacterCount,
            statistics.wordCount,
            statistics.sentenceCount,
            statistics.lineCount,
            statistics.blankLineCount,
            statistics.blockCount,
            statistics.sectionCount,
            statistics.headingCount,
            statistics.paragraphCount,
            statistics.bulletedListCount,
            statistics.numberedListCount,
            statistics.tableCount,
            statistics.codeBlockCount,
            statistics.equationCount,
            statistics.quoteCount
        ]

        if numericValues.contains(where: { $0 < 0 }) {
            throw DocumentStructureValidationError.negativeStatistics("Statistics cannot be negative")
        }

        guard statistics.blockCount == blocks.count else {
            throw DocumentStructureValidationError.inconsistentStatistics("blockCount does not match detected blocks")
        }
        guard statistics.sectionCount == sections.count else {
            throw DocumentStructureValidationError.inconsistentStatistics("sectionCount does not match detected sections")
        }
    }

    private static func validateComplexity(_ complexity: DocumentComplexityEstimate, sections: [DocumentSection]) throws {
        if complexity.tokenEstimate < 0 || complexity.estimatedStudyMinutes < 0 || complexity.conceptDensity < 0 || complexity.structuralDensity < 0 {
            throw DocumentStructureValidationError.negativeStatistics("Complexity values cannot be negative")
        }

        guard complexity.sectionCount == sections.count else {
            throw DocumentStructureValidationError.inconsistentStatistics("Complexity sectionCount does not match sections")
        }

        for metric in complexity.sectionMetrics {
            guard sections.contains(where: { $0.id == metric.sectionID }) else {
                throw DocumentStructureValidationError.invalidSectionReference(sectionID: metric.sectionID, blockID: "section-metric")
            }
            guard metric.estimatedStudyMinutes >= 0, metric.tokenEstimate >= 0, metric.blockCount >= 0 else {
                throw DocumentStructureValidationError.negativeStatistics("Section complexity metrics cannot be negative")
            }
        }
    }

    private static func validateTokenEstimate(_ tokenEstimate: DocumentTokenEstimate, blocks: [DocumentBlock], sections: [DocumentSection]) throws {
        guard tokenEstimate.estimatedTotalTokens >= 0 else {
            throw DocumentStructureValidationError.negativeStatistics("Estimated token total cannot be negative")
        }

        guard tokenEstimate.blockEstimates.count == blocks.count else {
            throw DocumentStructureValidationError.inconsistentStatistics("Block token estimate count does not match blocks")
        }

        guard tokenEstimate.sectionEstimates.count == sections.count else {
            throw DocumentStructureValidationError.inconsistentStatistics("Section token estimate count does not match sections")
        }

        for (index, estimate) in tokenEstimate.blockEstimates.enumerated() {
            guard estimate.blockIndex == index, blocks.indices.contains(index), estimate.blockID == blocks[index].id else {
                throw DocumentStructureValidationError.invalidChunkBoundary("Block token estimate is not aligned with block ordering")
            }
        }

        for (index, estimate) in tokenEstimate.sectionEstimates.enumerated() {
            guard estimate.sectionIndex == index, sections.indices.contains(index), estimate.sectionID == sections[index].id else {
                throw DocumentStructureValidationError.invalidChunkBoundary("Section token estimate is not aligned with section ordering")
            }
            guard estimate.startBlockIndex >= 0, estimate.endBlockIndex >= estimate.startBlockIndex, estimate.endBlockIndex < max(1, blocks.count) else {
                throw DocumentStructureValidationError.invalidChunkBoundary("Section token estimate has invalid block bounds")
            }
        }

        let blockTokenSum = tokenEstimate.blockEstimates.reduce(0) { $0 + $1.estimatedTokens }
        guard blockTokenSum == tokenEstimate.estimatedTotalTokens else {
            throw DocumentStructureValidationError.inconsistentStatistics("Token total does not match block estimates")
        }

        guard tokenEstimate.sectionEstimates.allSatisfy({ $0.estimatedTokens >= 0 }) else {
            throw DocumentStructureValidationError.negativeStatistics("Section token estimates cannot be negative")
        }

        guard tokenEstimate.suggestedChunkBoundaries.allSatisfy({ $0.startBlockIndex >= 0 && $0.endBlockIndex >= $0.startBlockIndex && $0.endBlockIndex < blocks.count }) else {
            throw DocumentStructureValidationError.invalidChunkBoundary("Chunk boundaries must stay within block bounds")
        }

        var expectedStart = 0
        for boundary in tokenEstimate.suggestedChunkBoundaries {
            guard boundary.startBlockIndex == expectedStart else {
                throw DocumentStructureValidationError.invalidChunkBoundary("Chunk boundaries must be contiguous")
            }
            expectedStart = boundary.endBlockIndex + 1
        }

        if !blocks.isEmpty, expectedStart != blocks.count {
            throw DocumentStructureValidationError.invalidChunkBoundary("Chunk boundaries must cover every block")
        }

        for section in sections {
            if let boundarySectionID = tokenEstimate.suggestedChunkBoundaries.first(where: { $0.sectionID == section.id })?.sectionID {
                guard sections.contains(where: { $0.id == boundarySectionID }) else {
                    throw DocumentStructureValidationError.invalidChunkBoundary("Chunk boundary references an unknown section")
                }
            }
        }
    }
}
