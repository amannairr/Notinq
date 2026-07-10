import SwiftUI

struct InspectableConcept: Identifiable {
    let value: String
    var id: String { value }
}

struct StudyInspectorView: View {
    let noteTitle: String
    let insights: LectureCompletenessAnalysis
    let knowledgeGaps: [StudyKnowledgeGap]
    let learningMemory: [StudyMemoryEntry]
    let progress: StudyProgress
    let summaryPack: StudySummaryPack
    let examReadiness: ExamReadinessScore
    let onSelectConcept: (String) -> Void
    let onSelectGap: (StudyKnowledgeGap) -> Void
    let onExplainConcept: (String) -> Void
    let onGenerateSection: (String) -> Void
    let onInsertConcept: (String) -> Void
    let onLearnGap: (StudyKnowledgeGap) -> Void
    let onGenerateGapNotes: (StudyKnowledgeGap) -> Void
    let onCreateGapFlashcards: (StudyKnowledgeGap) -> Void
    let onStartReviewSession: () -> Void
    let onOpenFocusWorkspace: (FocusWorkspaceType) -> Void

    @State private var selectedConcept: InspectableConcept?
    @State private var selectedGap: StudyKnowledgeGap?
    @State private var summaryTab: SummaryTab = .thirtySeconds

    private let cardCornerRadius: CGFloat = 19
    private let cardWidth: CGFloat = 440 // max width

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 11) {
                    coverageCard
                    examReadinessCard
                }
                HStack(spacing: 11) {
                    knowledgeGapsCard
                    learningMemoryCard
                }
                HStack(spacing: 11) {
                    quickSummaryCard
                    studyProgressCard
                }
                reviewSuggestionsCard
            }
            .padding(18)
            .frame(maxWidth: cardWidth)
        }
        .background(LinearGradient(
            colors: [Color(red: 0.98, green: 0.98, blue: 0.99), Color(red: 0.95, green: 0.96, blue: 0.98)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
    }

    private var coverageCard: some View {
        Card(
            title: "Learning Insights",
            subtitle: "Coverage Dashboard",
            icon: "chart.bar.fill",
            color: Color(red: 0.24, green: 0.49, blue: 0.59),
            content: {
                coverageDashboard
            }
        )
    }

    private var coverageDashboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("✓ Well Covered")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.green)
                ForEach(insights.wellCoveredConcepts.prefix(3), id: \ .title) { item in
                    conceptPill(item.title, status: .well, action: { selectedConcept = InspectableConcept(value: item.title) })
                }
            }
            HStack(spacing: 10) {
                Text("⚠ Partially Covered")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.yellow)
                ForEach(insights.partiallyCapturedConcepts.prefix(3), id: \ .title) { item in
                    conceptPill(item.title, status: .partial, action: { selectedConcept = InspectableConcept(value: item.title) })
                }
            }
            HStack(spacing: 10) {
                Text("✕ Missing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red)
                ForEach(insights.missingConcepts.prefix(3), id: \ .title) { item in
                    conceptPill(item.title, status: .missing, action: { selectedConcept = InspectableConcept(value: item.title) })
                }
            }
        }
        .sheet(item: $selectedConcept) { concept in
            ConceptDetailSheet(
                concept: concept.value,
                onExplain: { onExplainConcept(concept.value) },
                onGenerate: { onGenerateSection(concept.value) },
                onInsert: { onInsertConcept(concept.value) })
        }
    }

    private func conceptPill(_ text: String, status: ConceptStatus, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(status.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(status.color.opacity(0.10))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var knowledgeGapsCard: some View {
        Card(
            title: "Knowledge Gaps",
            subtitle: "Prerequisites & Weak Links",
            icon: "exclamationmark.triangle.fill",
            color: Color(red: 0.73, green: 0.35, blue: 0.33),
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(knowledgeGaps.prefix(2)) { gap in
                        Button(action: { selectedGap = gap }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(gap.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.red)
                                Text(gap.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Why: \(gap.evidence)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sheet(item: $selectedGap) { gap in
                    GapDetailSheet(gap: gap,
                        onLearn: { onLearnGap(gap) },
                        onGenerateNotes: { onGenerateGapNotes(gap) },
                        onCreateFlashcards: { onCreateGapFlashcards(gap) })
                }
            }
        )
    }

    private var learningMemoryCard: some View {
        Card(
            title: "Learning Memory",
            subtitle: "Personal Mastery",
            icon: "memorychip",
            color: Color(red: 0.54, green: 0.38, blue: 0.61),
            content: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Strong: \(learningMemory.filter { $0.masteryScore >= 0.7 }.count)")
                        .font(.caption)
                    Text("Weak: \(learningMemory.filter { $0.masteryScore < 0.4 }.count)")
                        .font(.caption)
                    Text("Recent Review: \(learningMemory.sorted { $0.lastReviewedAt ?? .distantPast > $1.lastReviewedAt ?? .distantPast }.first?.concept ?? "None")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    private var studyProgressCard: some View {
        Card(
            title: "Study Progress",
            subtitle: "Stats",
            icon: "chart.line.uptrend.xyaxis",
            color: Color(red: 0.32, green: 0.56, blue: 0.38),
            content: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Quizzes: \(progress.quizAttempts.count)")
                        .font(.caption)
                    Text("Cards: \(progress.flashcardsCreated)")
                        .font(.caption)
                    Text("Best Score: \(progress.bestQuizScore)%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Streak: \(progress.quizAttempts.count > 0 ? "\(progress.quizAttempts.count) days" : "Not started")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    private var quickSummaryCard: some View {
        Card(
            title: "Quick Summary",
            subtitle: summaryTab.title,
            icon: "text.alignleft",
            color: Color(red: 0.54, green: 0.38, blue: 0.61),
            content: {
                VStack(spacing: 7) {
                    HStack(spacing: 9) {
                        ForEach(SummaryTab.allCases, id: \ .self) { tab in
                            Button(action: { summaryTab = tab }) {
                                Text(tab.shortTitle)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(summaryTab == tab ? .white : .secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(summaryTab == tab ? Color.accentColor : Color.clear)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(summaryText(for: summaryTab))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        )
    }

    private var examReadinessCard: some View {
        Card(
            title: "Exam Readiness",
            subtitle: "Score & Breakdown",
            icon: "checklist",
            color: Color(red: 0.60, green: 0.45, blue: 0.20),
            content: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Score: \(examReadiness.score)%")
                        .font(.headline)
                    ForEach(examReadiness.breakdown, id: \ .title) { item in
                        HStack {
                            Text(item.title)
                                .font(.caption)
                            Spacer()
                            Text("\(item.value)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        )
    }

    private var reviewSuggestionsCard: some View {
        Card(
            title: "Review Suggestions",
            subtitle: "Personalized",
            icon: "sparkles",
            color: Color(red: 0.26, green: 0.43, blue: 0.59),
            content: {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: onStartReviewSession) {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Start Review Session")
                                .font(.headline)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentColor)

                    HStack(spacing: 16) {
                        Button(action: { onOpenFocusWorkspace(.flashcards) }) {
                            Label("Flashcards", systemImage: "rectangle.stack")
                                .labelStyle(.iconOnly)
                        }
                        Button(action: { onOpenFocusWorkspace(.quiz) }) {
                            Label("Quiz", systemImage: "checklist")
                                .labelStyle(.iconOnly)
                        }
                        Button(action: { onOpenFocusWorkspace(.activeRecall) }) {
                            Label("Recall", systemImage: "brain.head.profile")
                                .labelStyle(.iconOnly)
                        }
                        Button(action: { onOpenFocusWorkspace(.conceptMap) }) {
                            Label("Map", systemImage: "point.3.connected.trianglepath.dotted")
                                .labelStyle(.iconOnly)
                        }
                        Button(action: { onOpenFocusWorkspace(.examPrep) }) {
                            Label("Exam", systemImage: "checkmark.seal")
                                .labelStyle(.iconOnly)
                        }
                    }
                    .font(.title3)
                }
            }
        )
    }

    private func summaryText(for tab: SummaryTab) -> String {
        switch tab {
        case .thirtySeconds: return summaryPack.executiveSummary
        case .twoMinutes: return summaryPack.detailedSummary
        case .exam: return summaryPack.examRevisionSummary
        }
    }
}

// MARK: - Card Helper
struct Card<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)
            content()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 4)
        .frame(minWidth: 170, maxWidth: 220, alignment: .topLeading)
    }
}

// MARK: - Detail Sheets
struct ConceptDetailSheet: View {
    let concept: String
    let onExplain: () -> Void
    let onGenerate: () -> Void
    let onInsert: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(concept)
                .font(.title3.weight(.bold))
            Button("Explain Concept", action: onExplain)
            Button("Generate Section", action: onGenerate)
            Button("Insert Into Note", action: onInsert)
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct GapDetailSheet: View {
    let gap: StudyKnowledgeGap
    let onLearn: () -> Void
    let onGenerateNotes: () -> Void
    let onCreateFlashcards: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(gap.title)
                .font(.title3.weight(.bold))
            Text(gap.description)
                .font(.body)
            Button("Learn Now", action: onLearn)
            Button("Generate Notes", action: onGenerateNotes)
            Button("Create Flashcards", action: onCreateFlashcards)
        }
        .padding(20)
        .frame(width: 320)
    }
}

// MARK: - Supporting Types
enum ConceptStatus {
    case well, partial, missing
    var color: Color {
        switch self {
        case .well: return .green
        case .partial: return .yellow
        case .missing: return .red
        }
    }
}

enum SummaryTab: CaseIterable {
    case thirtySeconds, twoMinutes, exam
    var title: String {
        switch self {
        case .thirtySeconds: return "30 Second Review"
        case .twoMinutes: return "2 Minute Review"
        case .exam: return "Exam Review"
        }
    }
    var shortTitle: String {
        switch self {
        case .thirtySeconds: return "30s"
        case .twoMinutes: return "2m"
        case .exam: return "Exam"
        }
    }
}

enum FocusWorkspaceType {
    case flashcards, quiz, conceptMap, activeRecall, examPrep
}

struct ExamReadinessScore {
    let score: Int
    let breakdown: [BreakdownItem]
    struct BreakdownItem { let title: String; let value: Int }
}
