import Combine
import SwiftUI

struct ConceptCard: View {
    let concept: Concept
    let relationshipCount: Int
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(concept.name)
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                    Spacer(minLength: 8)
                    Text("\(relationshipCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                if !concept.description.isEmpty {
                    Text(concept.description)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    valuePill(title: "Importance", value: String(format: "%.2f", concept.importanceScore))
                    valuePill(title: "Difficulty", value: String(format: "%.2f", concept.difficultyScore))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.graphSurfaceRaised, Color.accentColor.opacity(0.07)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.graphBorderSoft, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func valuePill(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Text(value)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.graphSurfaceMuted)
        .clipShape(Capsule())
    }
}

struct KnowledgeGraphView: View {
    let noteID: UUID
    let noteTitle: String

    @ObservedObject private var manager = KnowledgeGraphManager.shared
    @State private var selectedConceptID: UUID?

    private var graph: KnowledgeGraph? {
        manager.graphsByNoteID[noteID]
    }

    private var concepts: [Concept] {
        graph?.concepts ?? []
    }

    private var relationships: [ConceptRelationship] {
        graph?.relationships ?? []
    }

    private var selectedConcept: Concept? {
        guard let selectedConceptID else { return concepts.first }
        return concepts.first(where: { $0.id == selectedConceptID }) ?? concepts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Knowledge Graph")
                        .font(.title3.weight(.bold))
                    Text(noteTitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                if manager.generationStateByNoteID[noteID]?.isGenerating == true {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.textSecondary)
                }
            }

            if let message = manager.generationStateByNoteID[noteID]?.message, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            if concepts.isEmpty {
                emptyState
            } else {
                graphCanvas
                    .frame(height: 320)
                    .background(Color.graphSurfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.graphBorderSoft, lineWidth: 1)
                    )

                if let selectedConcept {
                    detailCard(for: selectedConcept)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(concepts) { concept in
                        ConceptCard(
                            concept: concept,
                            relationshipCount: RelationshipBuilder.relationshipCount(for: concept.id, in: relationships)
                        ) {
                            selectedConceptID = concept.id
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedConceptID == nil {
                selectedConceptID = concepts.first?.id
            }
        }
        .onChange(of: graph?.lastUpdated) { _, _ in
            if let selectedConceptID, !concepts.contains(where: { $0.id == selectedConceptID }) {
                self.selectedConceptID = concepts.first?.id
            } else if selectedConceptID == nil {
                self.selectedConceptID = concepts.first?.id
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No graph yet")
                .font(.headline)
            Text("Edit the note or use Update Knowledge Graph to extract concepts and relationships.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.graphSurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var graphCanvas: some View {
        GeometryReader { proxy in
            let positions = KnowledgeGraphLayout.positions(
                for: concepts,
                relationships: relationships,
                size: proxy.size
            )

            ZStack {
                Canvas { context, _ in
                    for relationship in relationships {
                        guard
                            let source = positions[relationship.sourceConceptID],
                            let destination = positions[relationship.destinationConceptID]
                        else { continue }

                        var path = Path()
                        path.move(to: source)
                        path.addLine(to: destination)
                        context.stroke(path, with: .color(Color.accentColor.opacity(0.22)), lineWidth: 1.4)
                    }
                }

                ForEach(concepts) { concept in
                    if let point = positions[concept.id] {
                        let selected = selectedConceptID == concept.id
                        Button {
                            selectedConceptID = concept.id
                        } label: {
                            Text(shortLabel(for: concept.name))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(selected ? .white : Color.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected ? Color.accentColor : Color.graphSurfaceRaised)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.graphBorderSoft, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .position(point)
                    }
                }
            }
            .padding(16)
        }
    }

    private func detailCard(for concept: Concept) -> some View {
        let related = manager.relatedConcepts(of: concept)
        let prerequisites = manager.prerequisites(of: concept)
        let dependents = manager.dependentConcepts(of: concept)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(concept.name)
                        .font(.headline)
                    Text(concept.description)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                detailPill("Related", "\(related.count)")
                detailPill("Prereqs", "\(prerequisites.count)")
                detailPill("Dependents", "\(dependents.count)")
                detailPill("Mastery", "Pending")
            }

            if !related.isEmpty {
                detailList(title: "Connected concepts", items: related.map(\.name))
            }
            if !prerequisites.isEmpty {
                detailList(title: "Prerequisites", items: prerequisites.map(\.name))
            }
            if !dependents.isEmpty {
                detailList(title: "Dependent concepts", items: dependents.map(\.name))
            }
        }
        .padding(16)
        .background(Color.graphSurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.graphBorderSoft, lineWidth: 1)
        )
    }

    private func detailPill(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.graphSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(items.joined(separator: "  •  "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func shortLabel(for text: String) -> String {
        let words = text.split(separator: " ")
        if words.count == 1 {
            return String(text.prefix(18))
        }
        return words.prefix(2).joined(separator: " ")
    }
}

enum KnowledgeGraphLayout {
    static func positions(for concepts: [Concept], relationships: [ConceptRelationship], size: CGSize) -> [UUID: CGPoint] {
        guard !concepts.isEmpty else { return [:] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(60, min(size.width, size.height) * 0.28)
        var positions = concepts.enumerated().reduce(into: [UUID: CGPoint]()) { result, element in
            let index = element.offset
            let concept = element.element
            let angle = (Double(index) / Double(max(concepts.count, 1))) * Double.pi * 2
            result[concept.id] = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }

        let iterations = 36
        let repulsionStrength: CGFloat = 1_200
        let attractionStrength: CGFloat = 0.018
        let damping: CGFloat = 0.8

        for _ in 0..<iterations {
            var forces: [UUID: CGVector] = concepts.reduce(into: [UUID: CGVector]()) { result, concept in
                result[concept.id] = .zero
            }

            for i in concepts.indices {
                for j in concepts.indices where i != j {
                    let left = concepts[i].id
                    let right = concepts[j].id
                    let delta = vector(from: positions[left] ?? center, to: positions[right] ?? center)
                    let distance = max(24, magnitude(delta))
                    let force = repulsionStrength / (distance * distance)
                    forces[left, default: .zero].dx -= (delta.dx / distance) * force
                    forces[left, default: .zero].dy -= (delta.dy / distance) * force
                }
            }

            for relationship in relationships {
                guard
                    let source = positions[relationship.sourceConceptID],
                    let destination = positions[relationship.destinationConceptID]
                else { continue }
                let delta = vector(from: source, to: destination)
                let distance = max(24, magnitude(delta))
                let force = (distance - 120) * attractionStrength
                let unit = normalized(delta)
                forces[relationship.sourceConceptID, default: .zero].dx += unit.dx * force
                forces[relationship.sourceConceptID, default: .zero].dy += unit.dy * force
                forces[relationship.destinationConceptID, default: .zero].dx -= unit.dx * force
                forces[relationship.destinationConceptID, default: .zero].dy -= unit.dy * force
            }

            for concept in concepts {
                var point = positions[concept.id] ?? center
                let force = forces[concept.id] ?? .zero
                point.x += force.dx * damping
                point.y += force.dy * damping
                point.x = min(max(24, point.x), max(24, size.width - 24))
                point.y = min(max(24, point.y), max(24, size.height - 24))
                positions[concept.id] = point
            }
        }

        return positions
    }

    private static func vector(from: CGPoint, to: CGPoint) -> CGVector {
        CGVector(dx: to.x - from.x, dy: to.y - from.y)
    }

    private static func magnitude(_ vector: CGVector) -> CGFloat {
        sqrt(vector.dx * vector.dx + vector.dy * vector.dy)
    }

    private static func normalized(_ vector: CGVector) -> CGVector {
        let length = max(0.0001, magnitude(vector))
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}
