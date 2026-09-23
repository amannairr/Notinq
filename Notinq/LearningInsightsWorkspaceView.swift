import SwiftUI

struct LearningInsightsWorkspaceView: View {
    let noteTitle: String
    let studentNotes: String
    let initialAnalysis: LectureCompletenessAnalysis?
    let onSaveAnalysis: (LectureCompletenessAnalysis) -> Void
    let onInsertIntoNote: (String) -> Void
    let onClose: () -> Void

    @StateObject private var controller: LearningInsightsWorkspaceModel
    @State private var lectureTranscript: String = ""
    @State private var lectureSlides: String = ""

    private let railWidth: CGFloat = 286

    init(
        noteTitle: String,
        studentNotes: String,
        initialAnalysis: LectureCompletenessAnalysis?,
        onSaveAnalysis: @escaping (LectureCompletenessAnalysis) -> Void,
        onInsertIntoNote: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteTitle = noteTitle
        self.studentNotes = studentNotes
        self.initialAnalysis = initialAnalysis
        self.onSaveAnalysis = onSaveAnalysis
        self.onInsertIntoNote = onInsertIntoNote
        self.onClose = onClose
        _controller = StateObject(
            wrappedValue: LearningInsightsWorkspaceModel(
                noteTitle: noteTitle,
                studentNotes: studentNotes,
                initialAnalysis: initialAnalysis,
                onSaveAnalysis: onSaveAnalysis,
                onInsertIntoNote: onInsertIntoNote
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width >= 940
            let currentAnalysis = resolvedAnalysis

            VStack(spacing: 0) {
                headerCard(analysis: currentAnalysis)

                Divider()
                    .overlay(Color.studyBorderSoft)

                ScrollViewReader { _ in
                    ScrollView {
                        VStack(spacing: 16) {
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
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                            footerBar(analysis: currentAnalysis)
                                .padding(.top, 4)
                        }
                        .padding(16)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .background(backgroundLayer)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.studyBorderSoft, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 36, x: 0, y: 20)
            .onAppear {
                controller.updateInitialAnalysis(initialAnalysis)
            }
            .onChange(of: initialAnalysisFingerprint) { _, _ in
                controller.updateInitialAnalysis(initialAnalysis)
            }
        }
    }

    private var resolvedAnalysis: LectureCompletenessAnalysis? {
        controller.resolvedAnalysis ?? initialAnalysis
    }

    private var analysis: LectureCompletenessAnalysis? {
        get { controller.analysis ?? initialAnalysis }
        set { controller.analysis = newValue }
    }

    private var isAnalyzing: Bool {
        controller.isAnalyzing
    }

    private var selectedConcept: LectureCoverageItem? {
        get { controller.selectedConcept }
        set { controller.selectedConcept = newValue }
    }

    private var previewMode: LearningInsightsPreviewMode {
        get { controller.previewMode }
        set { controller.previewMode = newValue }
    }

    private var generatedPreview: String {
        get { controller.generatedPreview }
        set { controller.generatedPreview = newValue }
    }

    private var statusMessage: String {
        get { controller.statusMessage }
        set { controller.statusMessage = newValue }
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

    private var analysisPrimaryButtonTitle: String {
        switch controller.phase {
        case .loading:
            return "Analyzing..."
        case .failure:
            return "Retry Analysis"
        case .ready, .empty:
            return "Refresh Analysis"
        case .idle:
            return "Analyze Lecture"
        }
    }

    @ViewBuilder
    private var analysisStatusBanner: some View {
        switch controller.phase {
        case .idle:
            emptyCompactState(
                title: "Ready to analyze",
                message: "Paste transcript and slide text, then generate the lecture comparison."
            )
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analyzing lecture sources")
                        .font(.headline)
                    Text("Comparing transcript, slides, and note content now.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.studySurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.studyBorderSoft, lineWidth: 1)
            )
        case .ready:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(red: 0.31, green: 0.58, blue: 0.39))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analysis complete")
                        .font(.headline)
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Refresh") {
                    analyzeLecture()
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.studySurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.studyBorderSoft, lineWidth: 1)
            )
        case .empty:
            emptyCompactState(
                title: "No lecture concepts identified",
                message: statusMessage
            )
        case .failure(let message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color(red: 0.73, green: 0.35, blue: 0.33))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analysis failed")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button("Retry") {
                    analyzeLecture()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.47, blue: 0.59))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.studySurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.studyBorderSoft, lineWidth: 1)
            )
        }
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
            analysisStatusBanner

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
                subtitle: "Paste transcript and slide text here. The current note is used automatically as the student context.",
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
                    Text("Current Note")
                        .font(.headline)
                }

                Text(studentNotes.isEmpty ? "No note content is available yet." : studentNotes)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(studentNotes.isEmpty ? .secondary : Color.textPrimary)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.studySurfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.studyBorderSoft, lineWidth: 1)
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
                        Text(analysisPrimaryButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.23, green: 0.47, blue: 0.59))
                .accessibilityLabel(LearningInsightsAction.analyze.accessibilityLabel)
                .accessibilityHint("Runs the lecture comparison against the current note.")
                .disabled(!LearningInsightsButtonAvailability.canAnalyze(isAnalyzing: isAnalyzing, hasSourceText: canAnalyze))

                if let selectedConcept {
                    Button(action: { generatePreview(for: selectedConcept, mode: .explanation) }) {
                        Text("Generate Explanation")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(LearningInsightsAction.explanation.accessibilityLabel)
                    .disabled(!LearningInsightsButtonAvailability.canGenerate(isAnalyzing: isAnalyzing, hasConceptSelection: true))
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
                        .background(Color.studySurfaceRaised)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.studyBorderSoft, lineWidth: 1)
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

                Picker("", selection: Binding(
                    get: { controller.previewMode },
                    set: { controller.previewMode = $0 }
                )) {
                    ForEach(LearningInsightsPreviewMode.allCases) { mode in
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
                    .background(Color.studySurfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.studyBorderSoft, lineWidth: 1)
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
        .background(Color.studySurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
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
                            if let matching {
                                controller.selectedConcept = matching
                                controller.selectConcept(matching, analysis: analysis)
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
                            .background(Color.studySurfaceRaised)
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
        .background(Color.studySurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
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
            .accessibilityLabel(LearningInsightsAction.explanation.accessibilityLabel)
            .disabled(!LearningInsightsButtonAvailability.canGenerate(isAnalyzing: isAnalyzing, hasConceptSelection: selectedConcept != nil))

            Button {
                if let selectedConcept {
                    generatePreview(for: selectedConcept, mode: .flashcards)
                }
            } label: {
                Label("Create Flashcards", systemImage: "rectangle.stack.badge.plus")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(LearningInsightsAction.flashcards.accessibilityLabel)
            .disabled(!LearningInsightsButtonAvailability.canGenerate(isAnalyzing: isAnalyzing, hasConceptSelection: selectedConcept != nil))

            Button {
                if let selectedConcept {
                    generatePreview(for: selectedConcept, mode: .quiz)
                }
            } label: {
                Label("Create Quiz Questions", systemImage: "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(LearningInsightsAction.quiz.accessibilityLabel)
            .disabled(!LearningInsightsButtonAvailability.canGenerate(isAnalyzing: isAnalyzing, hasConceptSelection: selectedConcept != nil))

            Button {
                if !generatedPreview.isEmpty {
                    controller.insertGeneratedPreview()
                }
            } label: {
                Label("Insert Into Note", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.31, green: 0.58, blue: 0.39))
            .accessibilityLabel(LearningInsightsAction.insert.accessibilityLabel)
            .disabled(!LearningInsightsButtonAvailability.canInsert(isAnalyzing: isAnalyzing, hasGeneratedPreview: generatedPreview.isEmpty == false))

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
        guard canAnalyze else {
            controller.phase = .empty
            controller.statusMessage = "Add a transcript or slide notes, then run the analysis."
            return
        }

        controller.analyzeLecture(transcript: lectureTranscript, slides: lectureSlides)
    }

    private func generatePreview(for concept: LectureCoverageItem, mode: LearningInsightsPreviewMode) {
        controller.generatePreview(for: concept, mode: mode)
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
                            controller.selectedConcept = item
                            controller.selectConcept(item, analysis: resolvedAnalysis)
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
                            .background(selectedConcept?.id == item.id ? Color.studySurfaceRaised : Color.studySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.studyBorderSoft, lineWidth: 1)
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
                controller.insertGeneratedPreview()
            }
        }
    }

    private func actionChip(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 7)
                .padding(.horizontal, 11)
                .background(Color.studySurfaceRaised)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.studyBorderSoft, lineWidth: 1)
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
                .background(Color.studySurfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.studyBorderSoft, lineWidth: 1)
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
        .background(Color.studySurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
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
        .background(Color.studySurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.studyBorderSoft, lineWidth: 1)
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
                Color.studySurfaceRaised,
                Color.studySurface
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var glassCard: some View {
        Color.studySurface
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                Color.studySurfaceRaised,
                Color.studySurface,
                Color.studySurfaceMuted
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

private struct CoverageRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.studyBorderSoft, lineWidth: 10)

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
