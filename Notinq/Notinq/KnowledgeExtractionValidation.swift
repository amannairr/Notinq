import Foundation

enum KnowledgeValidationSeverity: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct KnowledgeValidationIssue: Codable, Equatable, Sendable {
    var severity: KnowledgeValidationSeverity
    var field: String
    var message: String
}

struct KnowledgeValidationReport: Codable, Equatable, Sendable {
    var isValid: Bool
    var shouldRetry: Bool
    var confidenceFloor: Double
    var duplicateConceptCount: Int
    var duplicateDefinitionCount: Int
    var duplicateAliasCount: Int
    var duplicateRelationshipCount: Int
    var invalidReferenceCount: Int
    var missingIdentifierCount: Int
    var issues: [KnowledgeValidationIssue]
}

enum KnowledgeValidator {
    static func validate(payload: StructuredKnowledge, structure: DocumentStructure? = nil) -> KnowledgeValidationReport {
        var issues: [KnowledgeValidationIssue] = []
        var shouldRetry = false

        if payload.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(severity: .warning, field: "title", message: "Missing title"))
        }

        let normalizedConcepts = payload.concepts.map { normalize($0.name) }
        let duplicateConceptCount = duplicateCount(in: normalizedConcepts)
        if duplicateConceptCount > 0 {
            issues.append(.init(severity: .warning, field: "concepts", message: "Found \(duplicateConceptCount) duplicate concept names"))
        }

        let semanticDuplicateConceptCount = semanticDuplicateCount(in: payload.concepts.map(\.name))
        if semanticDuplicateConceptCount > 0 {
            issues.append(.init(severity: .warning, field: "concepts", message: "Found \(semanticDuplicateConceptCount) near-duplicate concepts"))
        }

        let missingDefinitionCount = payload.concepts.filter { normalize($0.definition).isEmpty }.count
        if missingDefinitionCount > 0 {
            issues.append(.init(severity: .warning, field: "definitions", message: "Found \(missingDefinitionCount) concepts without definitions"))
        }

        let emptyDefinitions = payload.definitions.filter { normalize($0.definition).isEmpty }.count
        if emptyDefinitions > 0 {
            issues.append(.init(severity: .warning, field: "definitions", message: "Found \(emptyDefinitions) empty definitions"))
        }

        let duplicateDefinitionCount = duplicateCount(in: payload.definitions.map { normalize($0.term + " " + $0.definition) })
        if duplicateDefinitionCount > 0 {
            issues.append(.init(severity: .warning, field: "definitions", message: "Found \(duplicateDefinitionCount) duplicate definitions"))
        }

        let duplicateAliasCount = duplicateCount(in: payload.concepts.flatMap { $0.aliases }.map(normalize))
        if duplicateAliasCount > 0 {
            issues.append(.init(severity: .warning, field: "aliases", message: "Found \(duplicateAliasCount) duplicate aliases"))
        }

        let duplicateRelationshipCount = duplicateCount(
            in: payload.relationships.map {
                normalize("\($0.sourceID) \($0.targetID) \($0.relation)")
            }
        )
        if duplicateRelationshipCount > 0 {
            issues.append(.init(severity: .warning, field: "relationships", message: "Found \(duplicateRelationshipCount) duplicate relationships"))
        }

        let missingIdentifierCount = payload.concepts.filter { normalize($0.id).isEmpty || normalize($0.name).isEmpty }.count
            + payload.definitions.filter { normalize($0.id).isEmpty || normalize($0.term).isEmpty }.count
            + payload.examples.filter { normalize($0.id).isEmpty }.count
            + payload.processes.filter { normalize($0.id).isEmpty }.count
            + payload.learningObjectives.filter { normalize($0.id).isEmpty }.count
            + payload.relationships.filter { normalize($0.id).isEmpty }.count
            + payload.actionItems.filter { normalize($0.id).isEmpty }.count
        if missingIdentifierCount > 0 {
            issues.append(.init(severity: .warning, field: "identifiers", message: "Found \(missingIdentifierCount) missing identifiers"))
        }

        let validConceptIDs = Set(payload.concepts.map { normalize($0.id) }.filter { !$0.isEmpty })
        let validSectionIDs = Set(flattenSections(payload.sections).map { normalize($0.id) }.filter { !$0.isEmpty })
        let invalidReferenceCount = payload.relationships.filter { relationship in
            let source = normalize(relationship.sourceID)
            let target = normalize(relationship.targetID)
            guard !source.isEmpty, !target.isEmpty else { return true }
            let sourceIsKnown = validConceptIDs.contains(source) || validSectionIDs.contains(source)
            let targetIsKnown = validConceptIDs.contains(target) || validSectionIDs.contains(target)
            return !(sourceIsKnown && targetIsKnown)
        }.count

        if invalidReferenceCount > 0 {
            issues.append(.init(severity: .error, field: "relationships", message: "Found \(invalidReferenceCount) invalid relationship references"))
            shouldRetry = true
        }

        let confidenceValues = collectConfidenceValues(from: payload)
        let confidenceFloor = confidenceValues.min() ?? payload.confidence
        if confidenceFloor < 0.25 {
            shouldRetry = true
        }

        let invalidConfidenceCount = confidenceValues.filter { $0 < 0 || $0 > 1 }.count
        if invalidConfidenceCount > 0 {
            issues.append(.init(severity: .error, field: "confidence", message: "Found \(invalidConfidenceCount) confidence values outside 0...1"))
            shouldRetry = true
        }

        if payload.concepts.isEmpty {
            issues.append(.init(severity: .error, field: "concepts", message: "No concepts were extracted"))
            shouldRetry = true
        }

        if payload.definitions.contains(where: { normalize($0.definition).isEmpty }) {
            shouldRetry = true
        }

        if let structure, payload.concepts.count < max(1, structure.complexity.headingCount) {
            issues.append(.init(severity: .warning, field: "coverage", message: "Concept coverage appears low for the document structure"))
            shouldRetry = true
        }

        let isValid = !issues.contains(where: { $0.severity == .error })
        return KnowledgeValidationReport(
            isValid: isValid,
            shouldRetry: shouldRetry || !isValid,
            confidenceFloor: confidenceFloor,
            duplicateConceptCount: duplicateConceptCount + semanticDuplicateConceptCount,
            duplicateDefinitionCount: duplicateDefinitionCount,
            duplicateAliasCount: duplicateAliasCount,
            duplicateRelationshipCount: duplicateRelationshipCount,
            invalidReferenceCount: invalidReferenceCount,
            missingIdentifierCount: missingIdentifierCount,
            issues: issues
        )
    }

    static func normalize(payload: StructuredKnowledge) -> StructuredKnowledge {
        var payload = payload
        payload.title = payload.title.trimmingCharacters(in: .whitespacesAndNewlines)
        payload.topics = dedupeStrings(payload.topics)
        payload.sections = dedupe(payload.sections) { normalize($0.title + " " + $0.content) }
        payload.sections = payload.sections.map(normalizeSection(_:))
        payload.concepts = dedupe(payload.concepts) { normalize($0.name) }
            .map(normalizeConcept(_:))
            .filter { isMeaningfulTerm($0.name) }
        payload.definitions = dedupe(payload.definitions) { normalize($0.term + " " + $0.definition) }
            .map(normalizeDefinition(_:))
            .filter { isMeaningfulTerm($0.term) && isMeaningfulTerm($0.definition) }
        payload.examples = dedupe(payload.examples) { normalize($0.conceptID + " " + $0.example) }.map(normalizeExample(_:))
        payload.processes = dedupe(payload.processes) { normalize($0.title + " " + $0.steps.joined(separator: " ")) }.map(normalizeProcess(_:))
        payload.relationships = dedupe(payload.relationships) { normalize("\($0.sourceID) \($0.targetID) \($0.relation)") }
            .map(normalizeRelationship(_:))
            .filter { !$0.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.targetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        payload.learningObjectives = dedupe(payload.learningObjectives) { normalize($0.objective) }.map(normalizeObjective(_:))
        payload.actionItems = dedupe(payload.actionItems) { normalize($0.title + " " + $0.details) }.map(normalizeActionItem(_:))
        payload.keywords = dedupeStrings(payload.keywords).filter { isMeaningfulTerm($0) }
        payload.aliases = dedupeStrings(payload.aliases)
        payload.procedures = dedupeStrings(payload.procedures)
        payload.formulas = dedupeStrings(payload.formulas)
        payload.importantFacts = dedupeStrings(payload.importantFacts)
        payload.keyTerminology = dedupeStrings(payload.keyTerminology)
        payload.misconceptions = dedupeStrings(payload.misconceptions)
        payload.prerequisites = dedupeStrings(payload.prerequisites)
        payload.hierarchy = payload.hierarchy.map(normalizeSection(_:))
        payload.supportingEvidence = dedupeStrings(payload.supportingEvidence)
        payload.summaryHighlights = dedupeStrings(payload.summaryHighlights)
        payload.examFocus = dedupeStrings(payload.examFocus)
        payload.sourceLocations = dedupe(payload.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        payload.metadata.sectionCount = payload.sections.count
        if payload.metadata.title.isEmpty {
            payload.metadata.title = payload.title
        }
        if payload.title.isEmpty {
            payload.title = payload.metadata.title
        }
        return payload
    }

    static func buildRetryPrompt(for report: KnowledgeValidationReport) -> String {
        let issues = report.issues.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
        return "The previous extraction was incomplete or invalid. Fix the following issues and return only valid JSON: \(issues)"
    }

    private static func normalizeConcept(_ concept: KnowledgeConcept) -> KnowledgeConcept {
        var concept = concept
        concept.name = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
        concept.definition = concept.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        concept.aliases = dedupeStrings(concept.aliases)
        concept.relationships = dedupeStrings(concept.relationships)
        concept.examples = dedupeStrings(concept.examples)
        concept.learningObjective = concept.learningObjective.trimmingCharacters(in: .whitespacesAndNewlines)
        concept.sourceLocations = dedupe(concept.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        concept.importance = clamp(concept.importance)
        concept.difficulty = clamp(concept.difficulty)
        concept.confidence = clamp(concept.confidence)
        if concept.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            concept.id = UUID().uuidString
        }
        return concept
    }

    private static func normalizeDefinition(_ definition: KnowledgeDefinition) -> KnowledgeDefinition {
        var definition = definition
        definition.term = definition.term.trimmingCharacters(in: .whitespacesAndNewlines)
        definition.definition = definition.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        definition.aliases = dedupeStrings(definition.aliases)
        definition.sourceLocations = dedupe(definition.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        definition.confidence = clamp(definition.confidence)
        if definition.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            definition.id = UUID().uuidString
        }
        return definition
    }

    private static func normalizeExample(_ example: KnowledgeExample) -> KnowledgeExample {
        var example = example
        example.conceptID = example.conceptID.trimmingCharacters(in: .whitespacesAndNewlines)
        example.example = example.example.trimmingCharacters(in: .whitespacesAndNewlines)
        example.sourceLocations = dedupe(example.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        example.confidence = clamp(example.confidence)
        if example.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            example.id = UUID().uuidString
        }
        return example
    }

    private static func normalizeProcess(_ process: KnowledgeProcess) -> KnowledgeProcess {
        var process = process
        process.title = process.title.trimmingCharacters(in: .whitespacesAndNewlines)
        process.steps = dedupeStrings(process.steps)
        process.sourceLocations = dedupe(process.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        process.confidence = clamp(process.confidence)
        if process.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            process.id = UUID().uuidString
        }
        return process
    }

    private static func normalizeObjective(_ objective: KnowledgeObjective) -> KnowledgeObjective {
        var objective = objective
        objective.objective = objective.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        objective.relatedConceptIDs = dedupeStrings(objective.relatedConceptIDs)
        objective.sourceLocations = dedupe(objective.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        objective.confidence = clamp(objective.confidence)
        if objective.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            objective.id = UUID().uuidString
        }
        return objective
    }

    private static func normalizeRelationship(_ relationship: KnowledgeRelationship) -> KnowledgeRelationship {
        var relationship = relationship
        relationship.sourceID = relationship.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        relationship.targetID = relationship.targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidateRelation = relationship.relationKind == .relatedTo && !relationship.relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? relationship.relation
            : relationship.relationKind.rawValue
        relationship.relationKind = canonicalRelationshipKind(from: candidateRelation)
        relationship.relation = relationship.relationKind.rawValue
        relationship.sourceLocations = dedupe(relationship.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        relationship.confidence = clamp(relationship.confidence)
        if relationship.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            relationship.id = UUID().uuidString
        }
        return relationship
    }

    private static func normalizeActionItem(_ item: KnowledgeActionItem) -> KnowledgeActionItem {
        var item = item
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.details = item.details.trimmingCharacters(in: .whitespacesAndNewlines)
        item.priority = item.priority.trimmingCharacters(in: .whitespacesAndNewlines)
        item.sourceLocations = dedupe(item.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        item.confidence = clamp(item.confidence)
        if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item.id = UUID().uuidString
        }
        return item
    }

    private static func normalizeSection(_ section: KnowledgeSection) -> KnowledgeSection {
        var section = section
        section.title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
        section.content = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        section.children = section.children.map(normalizeSection(_:))
        section.sourceLocations = dedupe(section.sourceLocations) { normalize("\($0.sectionID) \($0.sectionTitle) \($0.lineStart) \($0.lineEnd) \($0.snippet)") }
        if section.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section.id = UUID().uuidString
        }
        return section
    }

    private static func collectConfidenceValues(from payload: StructuredKnowledge) -> [Double] {
        var values: [Double] = [payload.confidence]
        values += payload.concepts.map(\.confidence)
        values += payload.definitions.map(\.confidence)
        values += payload.examples.map(\.confidence)
        values += payload.processes.map(\.confidence)
        values += payload.learningObjectives.map(\.confidence)
        values += payload.relationships.map(\.confidence)
        values += payload.actionItems.map(\.confidence)
        return values
    }

    private static func canonicalRelationshipKind(from value: String) -> KnowledgeRelationshipKind {
        let normalized = normalize(value).lowercased()
        switch normalized {
        case "requires", "required", "requires to", "depends on", "depends upon":
            return .requires
        case "causes", "cause", "leads to", "results in", "triggers":
            return .causes
        case "part of", "part_of":
            return .partOf
        case "contains", "contain", "includes", "include":
            return .contains
        case "example of", "example_of":
            return .exampleOf
        case "compares to", "compared to", "versus":
            return .comparesTo
        case "uses", "utilizes", "utilises":
            return .uses
        case "produces", "generates", "creates":
            return .produces
        default:
            return .relatedTo
        }
    }

    private static func duplicateCount(in values: [String]) -> Int {
        var seen = Set<String>()
        var duplicates = 0
        for value in values {
            guard !value.isEmpty else { continue }
            if !seen.insert(value).inserted {
                duplicates += 1
            }
        }
        return duplicates
    }

    private static func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(cleaned)
            guard !cleaned.isEmpty, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return cleaned
        }
    }

    private static func dedupe<T>(_ values: [T], key: (T) -> String) -> [T] {
        var seen = Set<String>()
        return values.compactMap { value in
            let normalized = key(value)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return value
        }
    }

    private static func flattenSections(_ sections: [KnowledgeSection]) -> [KnowledgeSection] {
        sections + sections.flatMap { flattenSections($0.children) }
    }

    private static func semanticDuplicateCount(in values: [String]) -> Int {
        guard values.count > 1 else { return 0 }
        var duplicates = 0
        for index in values.indices {
            for candidateIndex in values.indices where candidateIndex > index {
                let lhs = values[index]
                let rhs = values[candidateIndex]
                let similarity = EmbeddingService.shared.similarity(between: lhs, and: rhs)
                if similarity >= 0.93 {
                    duplicates += 1
                }
            }
        }
        return duplicates
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMeaningfulTerm(_ value: String) -> Bool {
        let normalized = normalize(value)
        guard !normalized.isEmpty else { return false }
        let noise: Set<String> = [
            "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "good", "hello", "hi",
            "how", "i", "if", "in", "is", "it", "let", "like", "me", "morning", "note", "notes", "now",
            "okay", "of", "on", "or", "our", "specifically", "study", "thanks", "the", "this", "to",
            "today", "we", "welcome", "what", "with", "you", "your", "everyone", "afternoon", "evening",
            "thing", "things", "stuff", "maybe", "really", "basically", "actually", "simply", "important",
            "useful", "general", "common", "section", "lecture", "class", "topic", "content"
        ]
        let tokens = normalized.split(separator: " ")
        return tokens.contains(where: { !noise.contains(String($0)) && !$0.allSatisfy(\.isNumber) })
    }
}

typealias StructuredKnowledgeValidationSeverity = KnowledgeValidationSeverity
typealias StructuredKnowledgeValidationIssue = KnowledgeValidationIssue
typealias StructuredKnowledgeValidationReport = KnowledgeValidationReport

enum KnowledgeExtractionValidator {
    static func validate(payload: StructuredKnowledge, structure: DocumentStructure) -> StructuredKnowledgeValidationReport {
        KnowledgeValidator.validate(payload: payload, structure: structure)
    }

    static func normalize(payload: StructuredKnowledge) -> StructuredKnowledge {
        KnowledgeValidator.normalize(payload: payload)
    }

    static func buildRetryPrompt(for issues: StructuredKnowledgeValidationReport) -> String {
        KnowledgeValidator.buildRetryPrompt(for: issues)
    }
}

struct ExtractionValidationIssue: Codable, Equatable, Sendable {
    var field: String
    var message: String
    var severity: KnowledgeValidationSeverity
}

struct ExtractionValidationReport: Codable, Equatable, Sendable {
    var isValid: Bool
    var issues: [ExtractionValidationIssue]
    var discardedConceptCount: Int
    var discardedRelationshipCount: Int
    var discardedFactCount: Int
    var sourceReferenceCount: Int

    static let valid = ExtractionValidationReport(
        isValid: true,
        issues: [],
        discardedConceptCount: 0,
        discardedRelationshipCount: 0,
        discardedFactCount: 0,
        sourceReferenceCount: 0
    )
}

enum ExtractionValidator {
    static func sanitize(payload: CanonicalExtractionPayload) -> (payload: CanonicalExtractionPayload, report: ExtractionValidationReport) {
        let sourceReferences = sanitizeSourceReferences(payload.sourceReferences)
        let sourceIDs = Set(sourceReferences.map(\.chunkID))

        var issues: [ExtractionValidationIssue] = []
        var discardedConceptCount = 0
        var discardedRelationshipCount = 0
        var discardedFactCount = 0

        let resolvedConcepts = ConceptResolver().resolve(payload.concepts)
        let sanitizedConcepts = resolvedConcepts.concepts.compactMap { concept -> ExtractionConcept? in
            let trimmedName = concept.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                discardedConceptCount += 1
                issues.append(.init(field: "concepts.name", message: "Discarded concept with empty name", severity: .warning))
                return nil
            }

            var sanitized = concept
            sanitized.name = trimmedName
            if let description = sanitized.descriptionText?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                sanitized.descriptionText = description
            } else {
                sanitized.descriptionText = nil
            }
            sanitized.importanceScore = clamp(sanitized.importanceScore)
            sanitized.confidenceScore = clamp(sanitized.confidenceScore)
            sanitized.aliases = dedupeStrings(sanitized.aliases)
            sanitized.sourceChunkIDs = dedupeStrings(sanitized.sourceChunkIDs.filter { sourceIDs.isEmpty || sourceIDs.contains($0) })

            if sanitized.sourceChunkIDs.isEmpty && !sourceIDs.isEmpty {
                discardedConceptCount += 1
                issues.append(.init(field: "concepts.source_chunk_ids", message: "Discarded concept without valid source references", severity: .warning))
                return nil
            }

            return sanitized
        }

        let validConceptIDs = Set(sanitizedConcepts.map { $0.id })

        let sanitizedRelationships = payload.relationships.compactMap { relationship -> ExtractionRelationship? in
            guard let normalizedType = ExtractionRelationshipType.normalized(from: relationship.relationshipType.rawValue) else {
                discardedRelationshipCount += 1
                issues.append(.init(field: "relationships.type", message: "Discarded unsupported relationship type: \(relationship.relationshipType.rawValue)", severity: .warning))
                return nil
            }

            let sourceID = relationship.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            let targetID = relationship.targetID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceID.isEmpty, !targetID.isEmpty else {
                discardedRelationshipCount += 1
                issues.append(.init(field: "relationships.endpoints", message: "Discarded empty relationship endpoints", severity: .warning))
                return nil
            }
            guard sourceID != targetID else {
                discardedRelationshipCount += 1
                issues.append(.init(field: "relationships.selfLoop", message: "Discarded self-loop relationship for \(sourceID)", severity: .warning))
                return nil
            }

            let filteredSourceChunkIDs = dedupeStrings(relationship.sourceChunkIDs.filter { sourceIDs.isEmpty || sourceIDs.contains($0) })
            if filteredSourceChunkIDs.isEmpty && !sourceIDs.isEmpty {
                discardedRelationshipCount += 1
                issues.append(.init(field: "relationships.source_chunk_ids", message: "Discarded relationship without valid source references", severity: .warning))
                return nil
            }

            let sourceKnown = validConceptIDs.contains(sourceID)
            let targetKnown = validConceptIDs.contains(targetID)
            if !sourceKnown || !targetKnown {
                discardedRelationshipCount += 1
                issues.append(.init(field: "relationships.endpoints", message: "Discarded relationship referencing unknown concepts", severity: .warning))
                return nil
            }

            return ExtractionRelationship(
                sourceID: sourceID,
                targetID: targetID,
                relationshipType: normalizedType,
                confidenceScore: clamp(relationship.confidenceScore),
                sourceChunkIDs: filteredSourceChunkIDs
            )
        }

        let sanitizedFacts = payload.facts.compactMap { fact -> ExtractionFact? in
            let trimmedStatement = fact.statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedStatement.isEmpty else {
                discardedFactCount += 1
                issues.append(.init(field: "facts.statement", message: "Discarded empty fact statement", severity: .warning))
                return nil
            }

            let filteredConceptIDs = dedupeStrings(fact.conceptIDs.filter { validConceptIDs.contains($0) })
            let filteredSourceChunkIDs = dedupeStrings(fact.sourceChunkIDs.filter { sourceIDs.isEmpty || sourceIDs.contains($0) })
            guard !filteredSourceChunkIDs.isEmpty || sourceIDs.isEmpty else {
                discardedFactCount += 1
                issues.append(.init(field: "facts.source_chunk_ids", message: "Discarded fact without valid source references", severity: .warning))
                return nil
            }

            return ExtractionFact(
                id: fact.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? deterministicFactID(for: trimmedStatement) : fact.id.trimmingCharacters(in: .whitespacesAndNewlines),
                statement: trimmedStatement,
                confidenceScore: clamp(fact.confidenceScore),
                conceptIDs: filteredConceptIDs,
                sourceChunkIDs: filteredSourceChunkIDs
            )
        }

        let sanitizedPayload = CanonicalExtractionPayload(
            concepts: sanitizedConcepts,
            facts: sanitizedFacts,
            relationships: sanitizedRelationships,
            sourceReferences: sourceReferences
        )

        return (
            payload: sanitizedPayload,
            report: ExtractionValidationReport(
                isValid: issues.isEmpty,
                issues: issues,
                discardedConceptCount: discardedConceptCount,
                discardedRelationshipCount: discardedRelationshipCount,
                discardedFactCount: discardedFactCount,
                sourceReferenceCount: sourceReferences.count
            )
        )
    }

    static func validate(payload: CanonicalExtractionPayload) -> ExtractionValidationReport {
        sanitize(payload: payload).report
    }

    static func normalize(payload: CanonicalExtractionPayload) -> CanonicalExtractionPayload {
        sanitize(payload: payload).payload
    }

    static func buildRetryPrompt(for report: ExtractionValidationReport) -> String {
        let issues = report.issues.map { "\($0.field): \($0.message)" }.joined(separator: "; ")
        return "The previous extraction was incomplete or invalid. Fix the following issues and return only valid JSON: \(issues)"
    }

    private static func sanitizeSourceReferences(_ sourceReferences: [ExtractionSourceReference]) -> [ExtractionSourceReference] {
        var seen = Set<String>()
        return sourceReferences.compactMap { reference in
            let chunkID = reference.chunkID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkID.isEmpty, !seen.contains(chunkID) else { return nil }
            seen.insert(chunkID)
            return ExtractionSourceReference(
                chunkID: chunkID,
                documentID: reference.documentID.trimmingCharacters(in: .whitespacesAndNewlines),
                chunkIndex: max(0, reference.chunkIndex),
                startOffset: reference.startOffset.map { max(0, $0) },
                endOffset: reference.endOffset.map { max(0, $0) }
            )
        }
    }

    private static func dedupeStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(for: trimmed)
            guard !trimmed.isEmpty, !key.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private static func deterministicFactID(for statement: String) -> String {
        let normalized = normalizedKey(for: statement)
        guard !normalized.isEmpty else { return UUID().uuidString }
        return "fact-\(normalized.replacingOccurrences(of: " ", with: "-").prefix(48))"
    }

    private static func normalizedKey(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
