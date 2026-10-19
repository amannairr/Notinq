import SwiftUI

struct KnowledgeGraphExplorerView: View {
    @StateObject private var viewModel = KnowledgeGraphExplorerViewModel()
    @State private var dragStartViewport: GraphExplorerViewport?
    @State private var magnificationStartScale: Double?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 300)
                .background(Color.bgSidebar)

            Divider()

            VStack(spacing: 0) {
                graphToolbar
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color.bgEditor)

                Divider()

                HStack(spacing: 0) {
                    graphCanvas
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.bgEditor)

                    Divider()

                    detailPanel
                        .frame(width: 360)
                        .background(Color.bgNotesPane)
                }
            }
        }
        .task {
            viewModel.loadInitialGraph()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Knowledge Graph")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Explore concepts, relationships, mastery, and study dependencies.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Search Concepts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textSecondary)
                    TextField("ATP, Adenosine Triphosphate", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            viewModel.searchConcepts()
                        }
                }
                .padding(10)
                .background(Color.graphSurfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Search") {
                    viewModel.searchConcepts()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityHint("Searches canonical concepts and aliases in the knowledge graph")
            }

            filtersSection

            if viewModel.searchResults.isEmpty == false {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Results")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    ForEach(viewModel.searchResults, id: \.conceptID) { result in
                        Button {
                            viewModel.selectConcept(result.conceptID)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.canonicalName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                if result.aliases.isEmpty == false {
                                    Text(result.aliases.prefix(2).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Most Important Concepts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                ForEach(viewModel.bottlenecks, id: \.conceptID) { item in
                    Button {
                        viewModel.selectConcept(item.conceptID)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.conceptName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text("Centrality \(item.centrality) · Downstream \(item.downstreamCount)")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var graphToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.selectedNode?.name ?? "Knowledge Graph")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("\(viewModel.nodes.count) concepts · \(viewModel.edges.count) relationships")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Toggle("Provenance", isOn: $viewModel.showProvenanceOverlay)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                viewModel.fitToContent()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Fit graph to content")
            .accessibilityLabel("Fit graph to content")

            Picker("Neighborhood", selection: Binding(
                get: { viewModel.radius },
                set: { viewModel.setRadius($0) }
            )) {
                Text("1-hop").tag(1)
                Text("2-hop").tag(2)
                Text("3-hop").tag(3)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
        }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filters")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            TextField("Filter visible graph", text: Binding(
                get: { viewModel.filterState.textQuery },
                set: { viewModel.filterState.textQuery = $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Filter graph by concept title")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                masteryToggle("Mastered", .mastered)
                masteryToggle("Familiar", .familiar)
                masteryToggle("Practice", .needsPractice)
                masteryToggle("Struggling", .struggling)
            }

            Toggle("Active gaps", isOn: gapBinding(.active))
                .controlSize(.small)
            Toggle("Resolved gaps", isOn: gapBinding(.resolved))
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 5) {
                Text("Min confidence \(Int(viewModel.filterState.minimumConfidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Slider(value: Binding(
                    get: { viewModel.filterState.minimumConfidence },
                    set: { viewModel.filterState.minimumConfidence = $0 }
                ), in: 0...1, step: 0.05)
                .accessibilityLabel("Minimum edge confidence")
            }
        }
    }

    private func masteryToggle(_ title: String, _ state: GraphMasteryState) -> some View {
        Toggle(title, isOn: masteryBinding(state))
            .controlSize(.small)
    }

    private func masteryBinding(_ state: GraphMasteryState) -> Binding<Bool> {
        Binding(
            get: { viewModel.filterState.masteryStates.contains(state) },
            set: { isOn in
                if isOn {
                    viewModel.filterState.masteryStates.insert(state)
                } else {
                    viewModel.filterState.masteryStates.remove(state)
                }
            }
        )
    }

    private func gapBinding(_ status: GraphGapStatus) -> Binding<Bool> {
        Binding(
            get: { viewModel.filterState.gapStatuses.contains(status) },
            set: { isOn in
                if isOn {
                    viewModel.filterState.gapStatuses.insert(status)
                } else {
                    viewModel.filterState.gapStatuses.remove(status)
                }
            }
        )
    }

    private var graphCanvas: some View {
        GeometryReader { proxy in
            let positions = explorerPositions(size: proxy.size, nodes: viewModel.filteredNodes)

            ZStack {
                if viewModel.filteredNodes.isEmpty {
                    ContentUnavailableView(
                        "No Graph Data",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Create notes and update the knowledge graph to explore concepts here.")
                    )
                    .accessibilityLabel("No knowledge graph data available")
                } else {
                    Canvas { context, _ in
                        for edge in viewModel.filteredEdges {
                            guard let source = positions[edge.sourceID], let target = positions[edge.targetID] else { continue }
                            var path = Path()
                            path.move(to: source)
                            path.addLine(to: target)
                            context.stroke(path, with: .color(Color.accentColor.opacity(0.18 + edge.confidence * 0.32)), lineWidth: 0.8 + edge.confidence * 2.4)
                        }
                    }
                    .accessibilityHidden(true)

                    ForEach(viewModel.filteredEdges) { edge in
                        if let source = positions[edge.sourceID], let target = positions[edge.targetID] {
                            explorerEdgeHitTarget(edge, source: source, target: target)
                        }
                    }

                    ForEach(viewModel.filteredNodes) { node in
                        if let point = positions[node.id] {
                            explorerNode(node)
                                .position(point)
                        }
                    }
                }
            }
            .padding(20)
            .scaleEffect(viewModel.viewport.scale)
            .offset(x: viewModel.viewport.offsetX, y: viewModel.viewport.offsetY)
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
        }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartViewport == nil {
                    dragStartViewport = viewModel.viewport
                }
                let start = dragStartViewport ?? viewModel.viewport
                viewModel.updateViewport(
                    offsetX: start.offsetX + Double(value.translation.width),
                    offsetY: start.offsetY + Double(value.translation.height)
                )
            }
            .onEnded { _ in
                dragStartViewport = nil
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if magnificationStartScale == nil {
                    magnificationStartScale = viewModel.viewport.scale
                }
                let startScale = magnificationStartScale ?? viewModel.viewport.scale
                viewModel.updateViewport(scale: startScale * value)
            }
            .onEnded { _ in
                magnificationStartScale = nil
            }
    }

    private func explorerEdgeHitTarget(_ edge: KnowledgeGraphExplorerEdge, source: CGPoint, target: CGPoint) -> some View {
        let midpoint = CGPoint(x: (source.x + target.x) / 2, y: (source.y + target.y) / 2)
        return Button {
            viewModel.selectEdge(edge.id)
        } label: {
            Circle()
                .fill(viewModel.selectedEdge?.id == edge.id ? Color.accentColor.opacity(0.30) : Color.clear)
                .frame(width: 26, height: 26)
                .overlay {
                    if viewModel.showProvenanceOverlay {
                        provenanceBadge(sourceCount: edge.provenance.sourceCount, confidence: edge.confidence)
                    }
                }
        }
        .buttonStyle(.plain)
        .position(midpoint)
        .accessibilityLabel("Relationship \(edge.relationshipType), confidence \(Int(edge.confidence * 100)) percent")
        .accessibilityHint("Selects this relationship and shows provenance details")
    }

    private func explorerNode(_ node: KnowledgeGraphExplorerNode) -> some View {
        let isSelected = viewModel.selectedNode?.id == node.id
        let size = min(92, max(46, 42 + CGFloat(node.relationshipCount) * 5 + CGFloat(node.importance) * 18))

        return Button {
            viewModel.selectConcept(node.id)
        } label: {
            VStack(spacing: 4) {
                Text(shortLabel(node.name))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? .white : Color.textPrimary)
                Text("\(Int(node.mastery * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.textSecondary)
            }
            .frame(width: size, height: size)
            .background(isSelected ? Color.accentColor : masteryColor(node.mastery).opacity(0.22))
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isSelected ? Color.accentColor : masteryColor(node.mastery), lineWidth: isSelected ? 3 : 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if viewModel.showProvenanceOverlay {
                    provenanceBadge(sourceCount: node.provenance.sourceCount, confidence: node.provenance.confidence)
                        .offset(x: 10, y: -8)
                }
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0.08), radius: isSelected ? 12 : 5, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .help("\(node.name) · mastery \(Int(node.mastery * 100))%")
        .accessibilityLabel("\(node.name), mastery \(Int(node.mastery * 100)) percent, retention \(Int(node.retention * 100)) percent")
        .accessibilityHint("Selects this concept and shows graph relationships, prerequisites, and study recommendations")
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let node = viewModel.selectedNode {
                    selectedNodeDetails(node)
                    explanationSection
                    studyNextSection
                    pathSection
                } else if let edge = viewModel.selectedEdge {
                    selectedEdgeDetails(edge)
                } else {
                    ContentUnavailableView("No Concept Selected", systemImage: "point.3.connected.trianglepath.dotted")
                }
            }
            .padding(20)
        }
    }

    private func selectedNodeDetails(_ node: KnowledgeGraphExplorerNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(node.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)

            if node.description.isEmpty == false {
                Text(node.description)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricTile("Importance", node.importance)
                metricTile("Difficulty", node.difficulty)
                metricTile("Mastery", node.mastery)
                metricTile("Retention", node.retention)
                metricTile("Relationships", Double(node.relationshipCount), isPercent: false)
            }

            Text("Retention Risk: \(node.retentionRisk)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(node.retention < 0.35 ? Color.red : Color.textSecondary)

            if node.aliases.isEmpty == false {
                detailList(title: "Aliases", items: node.aliases)
            }

            if node.blockedTopics.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Learning Overlay")
                        .font(.subheadline.weight(.semibold))
                    Text("Weak prerequisite blocks: \(node.blockedTopics.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dashboardPanel()
    }

    private func selectedEdgeDetails(_ edge: KnowledgeGraphExplorerEdge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Relationship")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            metricTile("Confidence", edge.confidence)
            detailList(title: "Type", items: [edge.relationshipType])
            provenanceList(edge.provenance)
        }
        .dashboardPanel()
    }

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Graph Navigation")
                .font(.headline)
            detailList(title: "Prerequisites", items: viewModel.explanation.prerequisites)
            detailList(title: "Related Concepts", items: viewModel.explanation.relatedConcepts)
            detailList(title: "Dependent Concepts", items: viewModel.explanation.dependents)
            detailList(title: "Study Recommendations", items: viewModel.studyRecommendations)
        }
        .dashboardPanel()
    }

    private var studyNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Study Next")
                .font(.headline)
            if viewModel.studyNextTasks.isEmpty {
                Text("No study tasks available for this concept.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(viewModel.studyNextTasks.prefix(5)) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(task.concept)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(task.estimatedMinutes) min")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text(task.reasonText)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(10)
                    .background(Color.graphSurfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .dashboardPanel()
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find Connection")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Target concept", text: $viewModel.targetQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.findConnection() }
                Button("Find") {
                    viewModel.findConnection()
                }
                .buttonStyle(.bordered)
            }

            if let path = viewModel.pathResult {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(path.conceptNames.enumerated()), id: \.offset) { index, name in
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                        if index < path.relationshipTypes.count {
                            Text("  \(path.relationshipTypes[index])")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .dashboardPanel()
    }

    private func metricTile(_ title: String, _ value: Double, isPercent: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
            Text(isPercent ? "\(Int(value * 100))%" : "\(Int(value))")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.graphSurfaceMuted)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func detailList(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            if items.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                Text(items.prefix(8).joined(separator: "  •  "))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func provenanceList(_ provenance: GraphProvenanceSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provenance")
                .font(.subheadline.weight(.semibold))
            Text("\(provenance.sourceCount) sources · \(Int(provenance.confidence * 100))% confidence")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            ForEach(provenance.references) { reference in
                VStack(alignment: .leading, spacing: 3) {
                    Text(reference.title)
                        .font(.caption.weight(.semibold))
                    Text(reference.excerpt)
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private func provenanceBadge(sourceCount: Int, confidence: Double) -> some View {
        Text("\(sourceCount) · \(Int(confidence * 100))")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.accentColor)
            .clipShape(Capsule())
            .help("\(sourceCount) sources, \(Int(confidence * 100)) percent confidence")
            .accessibilityLabel("\(sourceCount) sources, \(Int(confidence * 100)) percent confidence")
    }

    private func explorerPositions(size: CGSize, nodes: [KnowledgeGraphExplorerNode]) -> [String: CGPoint] {
        guard nodes.isEmpty == false else { return [:] }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(90, min(size.width, size.height) * 0.34)
        return Dictionary(nodes.enumerated().map { index, node in
            let angle = (Double(index) / Double(max(nodes.count, 1))) * Double.pi * 2
            return (
                node.id,
                CGPoint(
                    x: center.x + CGFloat(cos(angle)) * radius,
                    y: center.y + CGFloat(sin(angle)) * radius
                )
            )
        }, uniquingKeysWith: { first, _ in first })
    }

    private func masteryColor(_ mastery: Double) -> Color {
        if mastery >= 0.8 { return .green }
        if mastery >= 0.5 { return .yellow }
        return .red
    }

    private func shortLabel(_ text: String) -> String {
        let words = text.split(separator: " ")
        if words.count <= 2 { return String(text.prefix(18)) }
        return words.prefix(2).joined(separator: " ")
    }
}

private extension View {
    func dashboardPanel() -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.graphSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.graphBorderSoft, lineWidth: 1)
            )
    }
}
