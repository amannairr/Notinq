import SwiftUI

struct LearningInsightsWorkspaceView: View {
    let noteTitle: String
    let studentNotes: String
    let initialAnalysis: LectureCompletenessAnalysis?
    let onSaveAnalysis: (LectureCompletenessAnalysis) -> Void
    let onInsertIntoNote: (String) -> Void
    let onClose: () -> Void

    @State private var lectureTranscript: String = ""
    @State private var lectureSlides: String = ""
    @State private var analysis: LectureCompletenessAnalysis?
    @State private var isAnalyzing = false
    @State private var selectedConcept: LectureCoverageItem?
    @State private var previewMode: InsightPreviewMode = .explanation
    @State private var generatedPreview: String = ""
    @State private var statusMessage: String = "Add a transcript or slide notes, then run the analysis."

    private let railWidth: CGFloat = 286

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 940
            let currentAnalysis = resolvedAnalysis

            VStack(spacing: 0) {
                headerCard(analysis: currentAnalysis)

                Divider()
                    .overlay(Color.black.opacity(0.06))

                ScrollView {
                    Group {
                        if isWide {
                            HStack(alignment: .top, spacing: 16) {
                                mainColumn(analysis: currentAnalysis, isWide: isWide)
                                insightsRail(analysis: currentAnalysis)
                                    .frame(width: railWidth)
                            }
                        } else {
                            VStack(spacing: 16) {
                                mainColumn(analysis: currentAnalysis, isWide: isWide)
                                insightsRail(analysis: currentAnalysis)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.hidden)

                Divider()
                    .overlay(Color.black.opacity(0.06))

                footerBar(analysis: currentAnalysis)
            }
            .background(backgroundLayer)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 36, x: 0, y: 20)
            .onAppear {
                seedInitialAnalysisIfNeeded()
                syncSelectionIfNeeded(using: currentAnalysis)
            }
            .onChange(of: initialAnalysisFingerprint) { _, _ in
                seedInitialAnalysisIfNeeded()
            }
            .onChange(of: analysisFingerprint(for: currentAnalysis)) { _, _ in
                syncSelectionIfNeeded(using: currentAnalysis)
            }
        }
    }

    private var resolvedAnalysis: LectureCompletenessAnalysis? {
        analysis ?? initialAnalysis
    }

    private var initialAnalysisFingerprint: String {
        analysisFingerprint(for: initialAnalysis)
    }

    private func analysisFingerprint(for analysis: LectureCompletenessAnalysis?) -> String {
        guard let analysis else { return "empty" }
        return [
            String(analysis.scorePercent),
            String(analysis.lectureConceptCount),
            String(analysis.noteConceptCount),
            String(analysis.missingConcepts.count),
            String(analysis.partiallyCapturedConcepts.count),
            String(analysis.wellCoveredConcepts.count),
            String(analysis.missingVisualContent.count),
            analysis.summary
        ]
        .joined(separator: "|")
    }

    private func syncSelectionIfNeeded(using analysis: LectureCompletenessAnalysis?) {
        guard let analysis else {
            selectedConcept = nil
            generatedPreview = ""
            return
        }

        let allItems = analysis.missingConcepts + analysis.partiallyCapturedConcepts + analysis.wellCoveredConcepts
        guard !allItems.isEmpty else {
            selectedConcept = nil
            generatedPreview = ""
            return
        }

        if let selectedConcept,
           allItems.contains(where: { $0.id == selectedConcept.id }) {
            return
        }

        selectedConcept = allItems.first
        updatePreview(for: selectedConcept, in: analysis)
    }

    private func seedInitialAnalysisIfNeeded() {
        guard analysis == nil, let initialAnalysis else { return }
        analysis = initialAnalysis
    }

    private func headerCard(analysis: LectureCompletenessAnalysis?) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Learning Insights")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    if let analysis {
                        statusPill(
                            text: "\(analysis.scorePercent)% coverage",
                            tint: coverageTint(for: analysis.completenessScore)
                        )
                    }
                }

                Text(noteTitle.isEmpty ? "Untitled Note" : noteTitle)
                    .font(.headline)
                    .foregroundStyle(Color.textSecondary)

                Text("Compare the lecture against your notes to see what is missing, partially captured, or already well documented.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 8) {
                    statusPill(text: "Transcript \(sourceWordCount(lectureTranscript))", tint: Color(red: 0.26, green: 0.52, blue: 0.64))
                    statusPill(text: "Slides \(sourceWordCount(lectureSlides))", tint: Color(red: 0.72, green: 0.50, blue: 0.22))
                }

                Button(action: onClose) {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(glassSurface)
    }

    private func mainColumn(analysis: LectureCompletenessAnalysis?, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sourceIntakeCard(isWide: isWide)

            if let analysis {
                coverageDashboardCard(analysis: analysis)
                conceptStatusCard(analysis: analysis)
                visualGapCard(analysis: analysis)
                generatedPreviewCard
            } else {
                emptyStateCard()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 2)
    }

    private func sourceIntakeCard(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Lecture Sources",
                subtitle: "Paste transcript and slide text here. The student notes are taken from the current note.",
                icon: "square.and.pencil",
                tint: Color(red: 0.25, green: 0.48, blue: 0.60)
            )

            if isWide {
                HStack(alignment: .top, spacing: 14) {
                    sourceEditor(
                        title: "Transcript",
                        placeholder: "Paste the lecture transcript here.",
                        text: $lectureTranscript,
                        tint: Color(red: 0.25, green: 0.48, blue: 0.60)
                    )

                    sourceEditor(
                        title: "Slides",
                        placeholder: "Paste slide bullets, captions, or figure labels here.",
                        text: $lectureSlides,
                        tint: Color(red: 0.72, green: 0.50, blue: 0.22)
                    )
                }
            } else {
                VStack(spacing: 14) {
                    sourceEditor(
                        title: "Transcript",
                        placeholder: "Paste the lecture transcript here.",
                        text: $lectureTranscript,
                        tint: Color(red: 0.25, green: 0.48, blue: 0.60)
                    )

                    sourceEditor(
                        title: "Slides",
                        placeholder: "Paste slide bullets, captions, or figure labels here.",
                        text: $lectureSlides,
                        tint: Color(red: 0.72, green: 0.50, blue: 0.22)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Student Notes")
                        .font(.headline)
                }

                Text(studentNotes.isEmpty ? "No note content is available yet." : studentNotes)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(studentNotes.isEmpty ? .secondary : Color.textPrimary)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                Button(action: analyzeLecture) {
                    HStack(spacing: 8) {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isAnalyzing ? "Analyzing..." : "Analyze Lecture")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.47, blue: 0.59))
                .disabled(!canAnalyze || isAnalyzing)

                if let selectedConcept {
                    Button(action: { generatePreview(for: selectedConcept, mode: .explanation) }) {
                        Text("Generate Explanation")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnalyzing)
                }
            }
        }
        .padding(18)
        .background(glassCard)
    }

    private func coverageDashboardCard(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Coverage Dashboard",
                subtitle: "A quick read on what the lecture covered and what should be reviewed first.",
                icon: "gauge.with.dots.needle.50percent",
                tint: coverageTint(for: analysis.completenessScore)
            )

            HStack(alignment: .center, spacing: 16) {
                CoverageRing(score: analysis.scorePercent)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Lecture Completeness")
                        .font(.headline)
                    Text("\(analysis.scorePercent)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)

                    ProgressView(value: analysis.completenessScore, total: 1.0)
                        .tint(coverageTint(for: analysis.completenessScore))

                    Text(analysis.summary)
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                metricPill(title: "Missing", value: analysis.missingConcepts.count, tint: Color(red: 0.73, green: 0.35, blue: 0.33))
                metricPill(title: "Partial", value: analysis.partiallyCapturedConcepts.count, tint: Color(red: 0.77, green: 0.56, blue: 0.21))
                metricPill(title: "Covered", value: analysis.wellCoveredConcepts.count, tint: Color(red: 0.31, green: 0.58, blue: 0.39))
                metricPill(title: "Visual Gaps", value: analysis.missingVisualContent.count, tint: Color(red: 0.54, green: 0.39, blue: 0.67))
            }
        }
        .padding(18)
        .background(glassCard)
    }

    private func conceptStatusCard(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Concept Status List",
                subtitle: "Tap any concept to inspect its definition, note evidence, and suggested next move.",
                icon: "list.bullet.rectangle",
                tint: Color(red: 0.24, green: 0.49, blue: 0.59)
            )

            VStack(alignment: .leading, spacing: 10) {
                conceptGroup(
                    title: "Missing",
                    subtitle: "Discussed in lecture but absent from notes.",
                    tint: Color(red: 0.73, green: 0.35, blue: 0.33),
                    items: analysis.missingConcepts
                )

                conceptGroup(
                    title: "Partially Captured",
                    subtitle: "Mentioned in notes, but missing key detail.",
                    tint: Color(red: 0.77, green: 0.56, blue: 0.21),
                    items: analysis.partiallyCapturedConcepts
                )

                conceptGroup(
                    title: "Well Covered",
                    subtitle: "Enough detail to reconstruct the explanation.",
                    tint: Color(red: 0.31, green: 0.58, blue: 0.39),
                    items: analysis.wellCoveredConcepts
                )
            }
        }
        .padding(18)
        .background(glassCard)
    }

    private func visualGapCard(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Missing Visual Content",
                subtitle: "Look for diagrams, workflows, figures, and board sketches that were likely discussed but not captured in the note.",
                icon: "rectangle.on.rectangle.angled",
                tint: Color(red: 0.54, green: 0.39, blue: 0.67)
            )

            if analysis.missingVisualContent.isEmpty {
                emptyCompactState(
                    title: "No obvious visual gaps detected",
                    message: "The current lecture sources do not strongly suggest a missed diagram or workflow."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(analysis.missingVisualContent.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.shortExplanation)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                            Text(item.suggestedAddition)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(glassCard)
    }

    private var generatedPreviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(previewMode.title)
                        .font(.headline)
                    Text("This preview can be inserted into the note or turned into practice material.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                Picker("", selection: $previewMode) {
                    ForEach(InsightPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            if generatedPreview.isEmpty {
                emptyCompactState(
                    title: "Select a concept",
                    message: "Choose a missing or partially captured concept to generate an explanation, flashcards, or quiz questions."
                )
            } else {
                Text(generatedPreview)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
                    .background(Color.white.opacity(0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.05), lineWidth: 1)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(glassCard)
    }

    private func insightsRail(analysis: LectureCompletenessAnalysis?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedConcept {
                selectedConceptCard(selectedConcept, analysis: analysis)
            } else {
                emptyCompactState(
                    title: "Pick a concept",
                    message: "Select a missing or partial concept to inspect its definition, why it matters, and what to add next."
                )
            }

            reviewPriorityCard(analysis: analysis)

            noteSnapshotCard
        }
        .padding(16)
        .background(glassCard)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func selectedConceptCard(_ concept: LectureCoverageItem, analysis: LectureCompletenessAnalysis?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(concept.title)
                        .font(.headline)
                    Text(statusLabel(for: concept.state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: concept.state))
                }

                Spacer(minLength: 0)

                Button("Generate Explanation") {
                    generatePreview(for: concept, mode: .explanation)
                }
                .buttonStyle(.bordered)
            }

            detailField(title: "Definition", value: concept.shortExplanation)
            detailField(title: "Why it matters", value: concept.whyItMatters)
            detailField(title: "Where it appears in notes", value: noteEvidence(for: concept))
            detailField(title: "Suggested addition", value: concept.suggestedAddition)

            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested actions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                actionChips(for: concept)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func reviewPriorityCard(analysis: LectureCompletenessAnalysis?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Review Priorities",
                subtitle: "Start here to get the biggest return on study time.",
                icon: "1.square",
                tint: Color(red: 0.28, green: 0.43, blue: 0.66)
            )

            if let analysis, !analysis.reviewPriority.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(analysis.reviewPriority.prefix(5)) { item in
                        Button {
                            let matching = matchConcept(named: item.title, in: analysis)
                            selectedConcept = matching ?? selectedConcept
                            if let selectedConcept {
                                updatePreview(for: selectedConcept, in: analysis)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(item.rank)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white)
                                    .frame(width: 26, height: 26)
                                    .background(color(for: item.state))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(item.reason)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.70))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                emptyCompactState(
                    title: "No priorities yet",
                    message: "Run an analysis to get a ranked review list."
                )
            }
        }
    }

    private var noteSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(noteTitle.isEmpty ? "Untitled Note" : noteTitle)
                .font(.headline)
            Text(studentNotes.isEmpty ? "No note content yet." : "\(wordCount(of: studentNotes)) words available for comparison.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(14)
        .background(Color.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func footerBar(analysis: LectureCompletenessAnalysis?) -> some View {
        HStack(spacing: 10) {
            Button {
                if let selectedConcept {
                    generatePreview(for: selectedConcept, mode: .explanation)
                }
            } label: {
                Label("Generate Explanation", systemImage: "text.quote")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.23, green: 0.47, blue: 0.59))
            .disabled(selectedConcept == nil)

            Button {
                if let selectedConcept {
                    generatePreview(for: selectedConcept, mode: .flashcards)
                }
            } label: {
                Label("Create Flashcards", systemImage: "rectangle.stack.badge.plus")
            }
            .buttonStyle(.bordered)
            .disabled(selectedConcept == nil)

            Button {
                if let selectedConcept {
                    generatePreview(for: selectedConcept, mode: .quiz)
                }
            } label: {
                Label("Create Quiz Questions", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .disabled(selectedConcept == nil)

            Button {
                if !generatedPreview.isEmpty {
                    onInsertIntoNote(generatedPreview)
                    statusMessage = "Inserted the generated content into the note."
                }
            } label: {
                Label("Insert Into Note", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.31, green: 0.58, blue: 0.39))
            .disabled(generatedPreview.isEmpty)

            Spacer(minLength: 0)

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(16)
        .background(glassSurface)
    }

    private func analyzeLecture() {
        guard canAnalyze, !isAnalyzing else { return }
        isAnalyzing = true

        let input = LectureAnalysisInput(
            lectureTitle: noteTitle,
            noteTitle: noteTitle,
            studentNotes: studentNotes,
            sources: [
                LectureContentSource(kind: .transcript, title: "Transcript", text: lectureTranscript),
                LectureContentSource(kind: .slides, title: "Slides", text: lectureSlides)
            ]
        )

        DispatchQueue.global(qos: .userInitiated).async {
            let result = LectureCompletenessAnalyzer.shared.analyze(input: input)
            DispatchQueue.main.async {
                analysis = result
                isAnalyzing = false
                statusMessage = "Analysis updated."
                onSaveAnalysis(result)
                syncSelectionIfNeeded(using: result)
            }
        }
    }

    private func generatePreview(for concept: LectureCoverageItem, mode: InsightPreviewMode) {
        previewMode = mode
        generatedPreview = previewText(for: concept, mode: mode)
        statusMessage = "Prepared \(mode.title.lowercased()) for \(concept.title)."
    }

    private func updatePreview(for concept: LectureCoverageItem?, in analysis: LectureCompletenessAnalysis?) {
        guard let concept else {
            generatedPreview = ""
            return
        }
        generatedPreview = previewText(for: concept, mode: previewMode)
        if let analysis, selectedConcept == nil {
            statusMessage = analysis.summary
        }
    }

    private func previewText(for concept: LectureCoverageItem, mode: InsightPreviewMode) -> String {
        switch mode {
        case .explanation:
            return [
                "Definition",
                concept.shortExplanation,
                "",
                "Why it matters",
                concept.whyItMatters,
                "",
                "What to add",
                concept.suggestedAddition,
                "",
                "Where it appears in notes",
                noteEvidence(for: concept)
            ]
            .joined(separator: "\n")
        case .flashcards:
            return [
                "Flashcard 1",
                "Front: What is \(concept.title)?",
                "Back: \(concept.shortExplanation)",
                "",
                "Flashcard 2",
                "Front: Why does \(concept.title) matter?",
                "Back: \(concept.whyItMatters)",
                "",
                "Flashcard 3",
                "Front: What should be added to the note?",
                "Back: \(concept.suggestedAddition)"
            ]
            .joined(separator: "\n")
        case .quiz:
            return [
                "Question 1",
                "Explain \(concept.title) in one or two sentences.",
                "",
                "Question 2",
                "Why is \(concept.title) important in the lecture?",
                "",
                "Question 3",
                "What detail is still missing from the notes?"
            ]
            .joined(separator: "\n")
        }
    }

    private func conceptGroup(title: String, subtitle: String, tint: Color, items: [LectureCoverageItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)

            if items.isEmpty {
                Text("No items here yet.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items.prefix(6)) { item in
                        Button {
                            selectedConcept = item
                            updatePreview(for: item, in: resolvedAnalysis)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: icon(for: item.state))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(tint)
                                    .frame(width: 18, height: 18)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(item.shortExplanation)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Text(statusLabel(for: item.state))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(tint)
                                    .padding(.vertical, 3)
                                    .padding(.horizontal, 8)
                                    .background(tint.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(10)
                            .background(Color.white.opacity(selectedConcept?.id == item.id ? 0.88 : 0.70))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func actionChips(for concept: LectureCoverageItem) -> some View {
        FlowRow(spacing: 8) {
            actionChip(title: "Generate Explanation") {
                generatePreview(for: concept, mode: .explanation)
            }
            actionChip(title: "Create Flashcards") {
                generatePreview(for: concept, mode: .flashcards)
            }
            actionChip(title: "Create Quiz") {
                generatePreview(for: concept, mode: .quiz)
            }
            actionChip(title: "Insert Into Note") {
                generatePreview(for: concept, mode: .explanation)
                if !generatedPreview.isEmpty {
                    onInsertIntoNote(generatedPreview)
                }
            }
        }
    }

    private func actionChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 7)
                .padding(.horizontal, 11)
                .background(Color.white.opacity(0.74))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func sourceEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.headline)
            }

            TextEditor(text: text)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .background(Color.white.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, 20)
                            .padding(.leading, 18)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func statusPill(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func metricPill(title: String, value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func detailField(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Text(value.isEmpty ? "No details available." : value)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyStateCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ready to analyze")
                .font(.headline)
            Text("Paste transcript or slide text to extract lecture concepts, compare them against the note, and generate a review plan.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(glassCard)
    }

    private func emptyCompactState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.70))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func noteEvidence(for concept: LectureCoverageItem) -> String {
        let trimmed = studentNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "No note evidence yet."
        }

        let lines = trimmed.components(separatedBy: .newlines)
        if let match = lines.first(where: { $0.localizedCaseInsensitiveContains(concept.title) }) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sentences = trimmed.split(whereSeparator: { ".!?".contains($0) })
        if let match = sentences.first(where: { $0.localizedCaseInsensitiveContains(concept.title) }) {
            return match.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return concept.noteSummary.isEmpty ? "The note does not directly mention this concept." : concept.noteSummary
    }

    private func matchConcept(named title: String, in analysis: LectureCompletenessAnalysis) -> LectureCoverageItem? {
        let allItems = analysis.missingConcepts + analysis.partiallyCapturedConcepts + analysis.wellCoveredConcepts
        return allItems.first(where: { $0.title.localizedCaseInsensitiveCompare(title) == .orderedSame })
    }

    private func updatePreview(for concept: LectureCoverageItem, in analysis: LectureCompletenessAnalysis?) {
        generatedPreview = previewText(for: concept, mode: previewMode)
        if let analysis, selectedConcept?.id == concept.id {
            statusMessage = analysis.summary
        }
    }

    private func coverageTint(for score: Double) -> Color {
        switch score {
        case ..<0.45:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        case ..<0.75:
            return Color(red: 0.77, green: 0.56, blue: 0.21)
        default:
            return Color(red: 0.31, green: 0.58, blue: 0.39)
        }
    }

    private func statusLabel(for state: LectureCoverageState) -> String {
        switch state {
        case .missing:
            return "Missing"
        case .partial:
            return "Partial"
        case .covered:
            return "Covered"
        }
    }

    private func color(for state: LectureCoverageState) -> Color {
        switch state {
        case .missing:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        case .partial:
            return Color(red: 0.77, green: 0.56, blue: 0.21)
        case .covered:
            return Color(red: 0.31, green: 0.58, blue: 0.39)
        }
    }

    private func icon(for state: LectureCoverageState) -> String {
        switch state {
        case .missing:
            return "xmark"
        case .partial:
            return "exclamationmark.triangle"
        case .covered:
            return "checkmark"
        }
    }

    private var glassSurface: some View {
        LinearGradient(
            colors: [
                Color.white.opacity(0.88),
                Color(red: 0.96, green: 0.94, blue: 0.89).opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassCard: some View {
        Color.white.opacity(0.60)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.91, green: 0.94, blue: 0.96),
                Color(red: 0.97, green: 0.94, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func sourceWordCount(_ text: String) -> String {
        let count = wordCount(of: text)
        return count == 0 ? "0" : "\(count)"
    }

    private func wordCount(of text: String) -> Int {
        text
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }

    private var canAnalyze: Bool {
        !lectureTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !lectureSlides.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum InsightPreviewMode: String, CaseIterable, Identifiable {
    case explanation
    case flashcards
    case quiz

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explanation:
            return "Explanation"
        case .flashcards:
            return "Flashcards"
        case .quiz:
            return "Quiz"
        }
    }
}

private struct CoverageRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.23, green: 0.47, blue: 0.59),
                            Color(red: 0.31, green: 0.58, blue: 0.39)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("Score")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text("\(score)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .frame(width: 112, height: 112)
    }
}

private struct FlowRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: spacing)], alignment: .leading, spacing: spacing) {
            content
        }
    }
}
