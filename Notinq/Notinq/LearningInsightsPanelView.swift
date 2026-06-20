import SwiftUI

struct LearningInsightsPanelView: View {
    let noteTitle: String
    let studentNotes: String
    let initialAnalysis: LectureCompletenessAnalysis?
    let onSaveAnalysis: (LectureCompletenessAnalysis) -> Void

    @State private var lectureTranscript: String = ""
    @State private var lectureSlides: String = ""
    @State private var analysis: LectureCompletenessAnalysis?
    @State private var isAnalyzing = false

    private var resolvedAnalysis: LectureCompletenessAnalysis? {
        analysis ?? initialAnalysis
    }

    private var canAnalyze: Bool {
        !lectureTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !lectureSlides.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                sourceInputsCard

                Button(action: analyzeLecture) {
                    HStack(spacing: 10) {
                        if isAnalyzing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isAnalyzing ? "Analyzing Lecture..." : "Analyze Lecture")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.20, green: 0.40, blue: 0.56))
                .disabled(!canAnalyze || isAnalyzing)

                if let analysis = resolvedAnalysis {
                    resultsView(analysis: analysis)
                } else {
                    emptyStateCard
                }
            }
            .padding(24)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .onAppear {
            if analysis == nil {
                analysis = initialAnalysis
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Learning Insights")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Compare the lecture transcript and slide text against your notes to see what is missing, partially captured, or well covered.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                labelChip(text: noteTitle.isEmpty ? "Untitled Note" : noteTitle, tint: Color(red: 0.16, green: 0.36, blue: 0.47))
                labelChip(text: "Transcript + Slides", tint: Color(red: 0.46, green: 0.30, blue: 0.18))
                labelChip(text: "Completeness Review", tint: Color(red: 0.26, green: 0.45, blue: 0.28))
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color(red: 0.96, green: 0.94, blue: 0.89).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 8)
    }

    private var sourceInputsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("Lecture Sources")

            HStack(alignment: .top, spacing: 14) {
                sourceEditor(
                    title: "Transcript",
                    placeholder: "Paste lecture transcript here...",
                    text: $lectureTranscript,
                    symbol: "waveform"
                )

                sourceEditor(
                    title: "Slides",
                    placeholder: "Paste slide text, figure captions, or bullet notes here...",
                    text: $lectureSlides,
                    symbol: "rectangle.on.rectangle"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Student Notes")
                    .font(.headline)
                Text(studentNotes.isEmpty ? "No note content available for this note yet." : studentNotes)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(studentNotes.isEmpty ? .secondary : .primary)
                    .lineSpacing(3)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ready to analyze")
                .font(.headline)
            Text("Add transcript or slide text, then run the analysis to see missed concepts, partial coverage, and a review order.")
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func resultsView(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            scoreCard(analysis: analysis)

            conceptSection(
                title: "Missing Concepts",
                subtitle: "Discussed in the lecture but absent from the notes.",
                tint: Color(red: 0.72, green: 0.31, blue: 0.28),
                items: analysis.missingConcepts
            )

            conceptSection(
                title: "Partially Captured",
                subtitle: "Mentioned in the notes, but the lecture explained more.",
                tint: Color(red: 0.77, green: 0.56, blue: 0.21),
                items: analysis.partiallyCapturedConcepts
            )

            conceptSection(
                title: "Well Covered",
                subtitle: "Sufficiently documented to reconstruct the lecture point.",
                tint: Color(red: 0.26, green: 0.55, blue: 0.36),
                items: analysis.wellCoveredConcepts,
                showDetail: false
            )

            visualSection(analysis: analysis)
            reviewPrioritySection(analysis: analysis)
        }
    }

    private func scoreCard(analysis: LectureCompletenessAnalysis) -> some View {
        HStack(alignment: .center, spacing: 18) {
            completenessGauge(score: analysis.completenessScore)

            VStack(alignment: .leading, spacing: 8) {
                Text("Lecture Completeness")
                    .font(.headline)

                Text("\(analysis.scorePercent)%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.35, blue: 0.47))

                ProgressView(value: analysis.completenessScore)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.23, green: 0.47, blue: 0.59))

                Text(analysis.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Color.white.opacity(0.80))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func completenessGauge(score: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(from: 0, to: score.clamped(to: 0...1))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(red: 0.22, green: 0.50, blue: 0.62),
                            Color(red: 0.35, green: 0.68, blue: 0.47)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 2) {
                Text("Score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int((score.clamped(to: 0...1) * 100).rounded()))")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 112, height: 112)
    }

    private func conceptSection(
        title: String,
        subtitle: String,
        tint: Color,
        items: [LectureCoverageItem],
        showDetail: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, subtitle: subtitle, tint: tint)

            if items.isEmpty {
                emptySectionState(text: "No items in this category.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items) { item in
                        coverageCard(item: item, tint: tint, showDetail: showDetail)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func coverageCard(item: LectureCoverageItem, tint: Color, showDetail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(tint)
                    .frame(width: 10, height: 10)
                Text(item.title)
                    .font(.headline)
                Spacer(minLength: 0)
                Text(item.state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(tint.opacity(0.12))
                    .clipShape(Capsule())
            }

            if showDetail {
                coverageDetail(label: "What was missed", value: item.whatWasMissed)
                coverageDetail(label: "Why it matters", value: item.whyItMatters)
                coverageDetail(label: "Short explanation", value: item.shortExplanation)
                coverageDetail(label: "Suggested addition", value: item.suggestedAddition)
            } else {
                Text(item.shortExplanation)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func visualSection(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Missing Visual Content",
                subtitle: "Diagrams, workflows, and figures likely discussed but not captured in text.",
                tint: Color(red: 0.44, green: 0.30, blue: 0.58)
            )

            if analysis.missingVisualContent.isEmpty {
                emptySectionState(text: "No obvious visual gaps were detected.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(analysis.missingVisualContent) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.headline)
                            coverageDetail(label: "What was missed", value: item.whatWasMissed)
                            coverageDetail(label: "Why it matters", value: item.whyItMatters)
                            coverageDetail(label: "Short explanation", value: item.shortExplanation)
                            coverageDetail(label: "Suggested addition", value: item.suggestedAddition)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func reviewPrioritySection(analysis: LectureCompletenessAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(
                title: "Review Priority",
                subtitle: "Start with the concepts that appear most important and least covered.",
                tint: Color(red: 0.28, green: 0.43, blue: 0.66)
            )

            if analysis.reviewPriority.isEmpty {
                emptySectionState(text: "No review order is available yet.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(analysis.reviewPriority) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(item.rank)")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.20, green: 0.38, blue: 0.52))
                                .frame(width: 28, height: 28)
                                .background(Color(red: 0.82, green: 0.90, blue: 0.95))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private func sourceEditor(
        title: String,
        placeholder: String,
        text: Binding<String>,
        symbol: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.headline)
            }

            TextEditor(text: text)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 180)
                .background(Color.white.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(placeholder)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 22)
                            .padding(.leading, 18)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(1.0)
    }

    private func sectionHeader(title: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
        .overlay(alignment: .trailing) {
            Circle()
                .fill(tint.opacity(0.14))
                .frame(width: 16, height: 16)
        }
    }

    private func emptySectionState(text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func coverageDetail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labelChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func analyzeLecture() {
        guard !isAnalyzing else { return }
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
                self.analysis = result
                self.isAnalyzing = false
                self.onSaveAnalysis(result)
            }
        }
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.91, green: 0.93, blue: 0.95),
                Color(red: 0.97, green: 0.94, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
