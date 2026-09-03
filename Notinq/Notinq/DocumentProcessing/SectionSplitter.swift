import Foundation

struct DocumentSectionSplitResult: Sendable, Equatable {
    var blocks: [DocumentBlock]
    var sections: [DocumentSection]
}

protocol SectionSplitting {
    func split(title: String, blocks: [DocumentBlock]) -> DocumentSectionSplitResult
}

final class SectionSplitter: SectionSplitting {
    static let shared = SectionSplitter()

    private init() {}

    func split(title: String, blocks: [DocumentBlock]) -> DocumentSectionSplitResult {
        guard !blocks.isEmpty else {
            return DocumentSectionSplitResult(blocks: [], sections: [])
        }

        var mutableBlocks = blocks
        var sections: [DocumentSection] = []
        var headingStack: [DocumentSection] = []
        var preambleSectionID: String?
        var sawHeading = false

        func makeSection(
            title: String,
            level: Int,
            kind: DocumentSectionKind,
            parentID: String?,
            startLine: Int
        ) -> DocumentSection {
            let order = sections.count
            let section = DocumentSection(
                id: sectionID(level: level, order: order, title: title),
                kind: kind,
                title: title,
                content: "",
                level: level,
                parentID: parentID,
                childIDs: [],
                blockIDs: [],
                order: order,
                startLine: startLine,
                endLine: startLine
            )
            return section
        }

        func appendSection(_ section: DocumentSection, pushToHeadingStack: Bool) {
            if let parentID = section.parentID, let parentIndex = sections.firstIndex(where: { $0.id == parentID }) {
                sections[parentIndex].childIDs.append(section.id)
            }
            sections.append(section)
            if pushToHeadingStack {
                headingStack.append(section)
            }
        }

        func assign(blockIndex: Int, to sectionID: String) {
            mutableBlocks[blockIndex].sectionID = sectionID
            if let index = sections.firstIndex(where: { $0.id == sectionID }) {
                sections[index].blockIDs.append(mutableBlocks[blockIndex].id)
                sections[index].startLine = min(sections[index].startLine, mutableBlocks[blockIndex].startLine)
                sections[index].endLine = max(sections[index].endLine, mutableBlocks[blockIndex].endLine)
                sections[index].content = sections[index].blockIDs.compactMap { blockID in
                    mutableBlocks.first(where: { $0.id == blockID })?.content
                }.joined(separator: "\n\n")
            }
        }

        for (index, block) in blocks.enumerated() {
            if block.kind == .heading {
                sawHeading = true
                let headingLevel = max(1, block.headingLevel ?? 1)
                while let last = headingStack.last, last.level >= headingLevel {
                    headingStack.removeLast()
                }

                let parentID = headingStack.last?.id
                let section = makeSection(
                    title: block.normalizedContent.isEmpty ? block.content : block.normalizedContent,
                    level: headingLevel,
                    kind: .heading,
                    parentID: parentID,
                    startLine: block.startLine
                )
                appendSection(section, pushToHeadingStack: true)
                assign(blockIndex: index, to: section.id)
                continue
            }

            if headingStack.isEmpty, preambleSectionID == nil {
                let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                let rootTitle = sawHeading ? "Preamble" : (trimmedTitle.isEmpty ? "Untitled Note" : trimmedTitle)
                let rootSection = makeSection(
                    title: rootTitle,
                    level: 0,
                    kind: sawHeading ? .paragraph : .root,
                    parentID: nil,
                    startLine: block.startLine
                )
                appendSection(rootSection, pushToHeadingStack: false)
                preambleSectionID = rootSection.id
            }

            if let sectionID = headingStack.last?.id ?? preambleSectionID {
                assign(blockIndex: index, to: sectionID)
                continue
            }
        }

        sections = sections.enumerated().map { index, section in
            var section = section
            section.order = index
            return section
        }

        return DocumentSectionSplitResult(blocks: mutableBlocks, sections: sections)
    }

    private func sectionID(level: Int, order: Int, title: String) -> String {
        let normalizedTitle = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
        return "section-\(level)-\(order)-\(normalizedTitle)"
    }
}
