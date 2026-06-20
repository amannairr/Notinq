import SwiftUI
import Foundation

enum StudyWorkspaceSection: String, CaseIterable, Identifiable {
    case flashcards = "Flashcards"
    case quizzes = "Quizzes"
    case testMe = "Test Me"
    case insights = "Insights"
    case learningInsights = "Learning Insights"
    case progress = "Progress"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .flashcards:
            return "rectangle.stack"
        case .quizzes:
            return "checklist"
        case .testMe:
            return "graduationcap"
        case .insights:
            return "chart.bar.doc.horizontal"
        case .learningInsights:
            return "brain.head.profile"
        case .progress:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

enum StudyCardType: String, CaseIterable, Codable, Identifiable {
    case definition
    case questionAnswer = "question_answer"
    case concept
    case cloze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .definition:
            return "Definition"
        case .questionAnswer:
            return "Q&A"
        case .concept:
            return "Concept"
        case .cloze:
            return "Cloze"
        }
    }

    var tint: Color {
        switch self {
        case .definition:
            return Color(red: 0.33, green: 0.57, blue: 0.74)
        case .questionAnswer:
            return Color(red: 0.33, green: 0.63, blue: 0.50)
        case .concept:
            return Color(red: 0.74, green: 0.51, blue: 0.32)
        case .cloze:
            return Color(red: 0.62, green: 0.42, blue: 0.66)
        }
    }
}

struct StudyFlashcard: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: StudyCardType
    var front: String
    var back: String
    var whyItMatters: String = ""
}

enum StudyQuizQuestionType: String, CaseIterable, Codable, Identifiable {
    case multipleChoice = "multiple_choice"
    case trueFalse = "true_false"
    case shortAnswer = "short_answer"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice:
            return "Multiple Choice"
        case .trueFalse:
            return "True / False"
        case .shortAnswer:
            return "Short Answer"
        }
    }
}

struct StudyQuizQuestion: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: StudyQuizQuestionType
    var prompt: String
    var options: [String] = []
    var correctAnswer: String
    var explanation: String = ""
    var keywords: [String] = []
}

struct StudyQuizSet: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var generatedAt: Date = Date()
    var questions: [StudyQuizQuestion]
}

struct StudyTutorQuestion: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var prompt: String
    var expectedAnswer: String
    var keyPoints: [String] = []
    var explanation: String = ""
    var concept: String = ""
}

struct StudyTerm: Codable, Equatable, Identifiable {
    var term: String
    var count: Int

    var id: String { term }
}

struct StudyInsights: Codable, Equatable {
    var keyConcepts: [String] = []
    var importantConcepts: [String] = []
    var frequentTerms: [StudyTerm] = []
    var potentialExamTopics: [String] = []
    var knowledgeGaps: [String] = []
}

struct StudyQuizAttempt: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var quizSetID: UUID
    var quizTitle: String
    var attemptedAt: Date = Date()
    var score: Int
    var totalQuestions: Int
    var percentage: Double
}

struct StudyTestMeSessionRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var completedAt: Date = Date()
    var score: Int
    var totalQuestions: Int
    var concepts: [String] = []
}

struct StudyProgress: Codable, Equatable {
    var flashcardsCreated: Int = 0
    var flashcardsReviewed: Int = 0
    var quizAttempts: [StudyQuizAttempt] = []
    var testMeSessions: [StudyTestMeSessionRecord] = []
}

struct NoteStudyData: Codable, Equatable {
    var flashcards: [StudyFlashcard] = []
    var quizSets: [StudyQuizSet] = []
    var tutorQuestions: [StudyTutorQuestion] = []
    var insights: StudyInsights = StudyInsights()
    var learningInsights: LectureCompletenessAnalysis = LectureCompletenessAnalysis()
    var progress: StudyProgress = StudyProgress()
    var lastGeneratedAt: Date?
}

extension StudyInsights {
    var isEmpty: Bool {
        keyConcepts.isEmpty
            && importantConcepts.isEmpty
            && frequentTerms.isEmpty
            && potentialExamTopics.isEmpty
            && knowledgeGaps.isEmpty
    }
}

extension NoteStudyData {
    var hasMaterials: Bool {
        !flashcards.isEmpty
            || !quizSets.isEmpty
            || !tutorQuestions.isEmpty
            || !insights.isEmpty
            || learningInsights.hasResults
    }
}

extension StudyProgress {
    var averageQuizScore: Int {
        guard !quizAttempts.isEmpty else { return 0 }
        let total = quizAttempts.reduce(0.0) { $0 + $1.percentage }
        return Int((total / Double(quizAttempts.count)).rounded())
    }

    var bestQuizScore: Int {
        Int(quizAttempts.map(\.percentage).max() ?? 0)
    }
}

struct PracticeQuizSession {
    let quizSetID: UUID
    var answers: [UUID: String] = [:]
    var isSubmitted = false
    var score: Int = 0
    var didPersistAttempt = false
}

enum StudyTutorVerdict: String {
    case correct
    case almost
    case incorrect

    var title: String {
        switch self {
        case .correct:
            return "Correct"
        case .almost:
            return "Almost There"
        case .incorrect:
            return "Review Needed"
        }
    }

    var tint: Color {
        switch self {
        case .correct:
            return Color(red: 0.27, green: 0.58, blue: 0.39)
        case .almost:
            return Color(red: 0.78, green: 0.58, blue: 0.25)
        case .incorrect:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        }
    }
}

struct StudyTutorEvaluation {
    var verdict: StudyTutorVerdict
    var feedback: String
    var explanation: String
    var modelAnswer: String
    var awardedPoint: Int
}

struct StudyTutorTurn {
    var questionID: UUID
    var concept: String
    var answer: String
    var evaluation: StudyTutorEvaluation
}

struct StudyTutorSessionState {
    var isActive = false
    var currentIndex = 0
    var answerText = ""
    var isEvaluating = false
    var currentEvaluation: StudyTutorEvaluation?
    var turns: [StudyTutorTurn] = []
    var score = 0
    var isComplete = false
    var didPersistCompletion = false
}

enum StudyStatusTone {
    case neutral
    case success
    case error

    var tint: Color {
        switch self {
        case .neutral:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .success:
            return Color(red: 0.27, green: 0.58, blue: 0.39)
        case .error:
            return Color(red: 0.73, green: 0.35, blue: 0.33)
        }
    }

    var icon: String {
        switch self {
        case .neutral:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}

private enum StudyTool: String, CaseIterable, Identifiable {
    case learningInsights = "Learning Insights"
    case flashcards = "Flashcards"
    case quizGenerator = "Quiz Generator"
    case summaryGenerator = "Summary Generator"
    case keyConcepts = "Key Concepts"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .learningInsights:
            return "brain.head.profile"
        case .flashcards:
            return "rectangle.stack"
        case .quizGenerator:
            return "checklist"
        case .summaryGenerator:
            return "text.alignleft"
        case .keyConcepts:
            return "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .learningInsights:
            return "Compare notes against transcript and slides."
        case .flashcards:
            return "Turn the note into reviewable cards."
        case .quizGenerator:
            return "Build multiple choice and short answer practice."
        case .summaryGenerator:
            return "Produce a compact note summary."
        case .keyConcepts:
            return "Extract the terms worth reviewing first."
        }
    }

    var actionLabel: String {
        switch self {
        case .learningInsights:
            return "Analyze"
        case .flashcards:
            return "Create"
        case .quizGenerator:
            return "Build"
        case .summaryGenerator:
            return "Generate"
        case .keyConcepts:
            return "Extract"
        }
    }
}

struct StudyView: View {
    let noteID: UUID?
    let noteTitle: String
    let selectedText: String
    let noteHasContent: Bool
    let studyData: NoteStudyData
    let isGenerating: Bool
    let generationStatus: String
    let generationSummary: String?
    let statusMessage: String?
    let statusTone: StudyStatusTone
    let onGenerateMaterials: () -> Void
    let onClose: () -> Void
    let onExplainSimply: () -> Void
    let onGiveExample: () -> Void
    let onCompareConcepts: () -> Void
    let onCreateAnalogy: () -> Void
    let onMarkFlashcardReviewed: (StudyFlashcard) -> Void
    let onRecordQuizAttempt: (StudyQuizSet, Int, Int) -> Void
    let onEvaluateTestMe: (StudyTutorQuestion, String, @escaping (StudyTutorEvaluation) -> Void) -> Void
    let onRecordTestMeSession: (Int, Int, [String]) -> Void

    @State private var selectedTab: StudyWorkspaceSection = .flashcards
    @State private var flashcardFilter: StudyCardType? = nil
    @State private var currentFlashcardIndex = 0
    @State private var isFlashcardRevealed = false
    @State private var reviewedCardIDs: Set<UUID> = []
    @State private var selectedQuizSetID: UUID?
    @State private var quizSession: PracticeQuizSession?
    @State private var tutorSession = StudyTutorSessionState()
    @State private var generatedFocusTarget: StudyWorkspaceSection?
    @State private var highlightedSection: StudyWorkspaceSection?
    @State private var highlightPulse = false
    @State private var highlightDismissTask: Task<Void, Never>?
    @State private var selectedTool: StudyTool = .learningInsights

    private let quizColumns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private let progressColumns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 10)]
    private let tabColumns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 8)]
    private let dashboardColumns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 10)]

    private var selectedExcerpt: String {
        selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var preferredGeneratedSection: StudyWorkspaceSection? {
        if !studyData.flashcards.isEmpty { return .flashcards }
        if !studyData.quizSets.isEmpty { return .quizzes }
        if !studyData.insights.isEmpty { return .insights }
        if studyData.learningInsights.hasResults { return .learningInsights }
        if !studyData.tutorQuestions.isEmpty { return .testMe }
        if !studyData.progress.quizAttempts.isEmpty || !studyData.progress.testMeSessions.isEmpty { return .progress }
        return nil
    }

    private var currentTabHasContent: Bool {
        switch selectedTab {
        case .flashcards:
            return !studyData.flashcards.isEmpty
        case .quizzes:
            return !studyData.quizSets.isEmpty
        case .testMe:
            return !studyData.tutorQuestions.isEmpty
        case .insights:
            return !studyData.insights.isEmpty
        case .learningInsights:
            return studyData.learningInsights.hasResults
        case .progress:
            return !studyData.progress.quizAttempts.isEmpty || !studyData.progress.testMeSessions.isEmpty
        }
    }

    private func firstAvailableContentTab() -> StudyWorkspaceSection? {
        if !studyData.flashcards.isEmpty { return .flashcards }
        if !studyData.quizSets.isEmpty { return .quizzes }
        if !studyData.tutorQuestions.isEmpty { return .testMe }
        if !studyData.insights.isEmpty { return .insights }
        if studyData.learningInsights.hasResults { return .learningInsights }
        if !studyData.progress.quizAttempts.isEmpty || !studyData.progress.testMeSessions.isEmpty { return .progress }
        return nil
    }

    private var filteredFlashcards: [StudyFlashcard] {
        if let flashcardFilter {
            return studyData.flashcards.filter { $0.type == flashcardFilter }
        }
        return studyData.flashcards
    }

    private var selectedQuizSet: StudyQuizSet? {
        guard let selectedQuizSetID else { return studyData.quizSets.first }
        return studyData.quizSets.first(where: { $0.id == selectedQuizSetID }) ?? studyData.quizSets.first
    }

    private var currentTutorQuestion: StudyTutorQuestion? {
        guard studyData.tutorQuestions.indices.contains(tutorSession.currentIndex) else { return studyData.tutorQuestions.first }
        return studyData.tutorQuestions[tutorSession.currentIndex]
    }

    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerCard
                toolsSection
                selectedToolDetail
            }
            .padding(24)
        }
        .background(backgroundGradient.ignoresSafeArea())
        .onAppear {
            if selectedToolCards.contains(selectedTool) == false {
                selectedTool = .learningInsights
            }
        }
    }

    private var selectedToolCards: [StudyTool] {
        StudyTool.allCases
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 0.98),
                Color(red: 0.93, green: 0.94, blue: 0.96),
                Color(red: 0.96, green: 0.93, blue: 0.90)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(noteTitle)
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("Study workspace")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(noteSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: onGenerateMaterials) {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isGenerating ? generationStatus : "Generate Materials")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.22, green: 0.44, blue: 0.58))
            .disabled(isGenerating || !noteHasContent)
        }
        .padding(20)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Study Tools")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Everything stays connected to the current note.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if let generationSummary {
                    Text(generationSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 290), spacing: 14)], spacing: 14) {
                ForEach(selectedToolCards) { tool in
                    toolCard(tool)
                }
            }
        }
    }

    private func toolCard(_ tool: StudyTool) -> some View {
        Button {
            selectedTool = tool
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: toolIcon(tool))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(toolTint(tool))
                        .frame(width: 30, height: 30)
                        .background(toolTint(tool).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    if selectedTool == tool {
                        Text("Selected")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(toolTint(tool))
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(tool.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tool.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(tool.actionLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(toolTint(tool))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 156, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        toolTint(tool).opacity(0.09)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(selectedTool == tool ? toolTint(tool).opacity(0.35) : Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(selectedTool == tool ? 0.06 : 0.04), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var selectedToolDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedTool.rawValue)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Selected tool detail")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            switch selectedTool {
            case .learningInsights:
                learningInsightsDetail
            case .flashcards:
                flashcardsDetail
            case .quizGenerator:
                quizDetail
            case .summaryGenerator:
                summaryDetail
            case .keyConcepts:
                keyConceptsDetail
            }
        }
        .padding(20)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var learningInsightsDetail: some View {
        let analysis = studyData.learningInsights
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                scoreRing(score: analysis.completenessScore)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Lecture Completeness \(analysis.scorePercent)%")
                        .font(.headline)
                    Text("Compare notes against the lecture transcript and slides to spot what is missing or underdeveloped.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            statRow(title: "Missing Concepts", value: "\(analysis.missingConcepts.count)")
            statRow(title: "Partially Captured", value: "\(analysis.partiallyCapturedConcepts.count)")
            statRow(title: "Well Covered", value: "\(analysis.wellCoveredConcepts.count)")

            if !analysis.missingConcepts.isEmpty {
                chipSection(title: "Top Missing", items: analysis.missingConcepts.prefix(3).map(\.title), tint: Color(red: 0.72, green: 0.31, blue: 0.28))
            }
            if !analysis.partiallyCapturedConcepts.isEmpty {
                chipSection(title: "Weak Coverage", items: analysis.partiallyCapturedConcepts.prefix(3).map(\.title), tint: Color(red: 0.77, green: 0.56, blue: 0.21))
            }
            if !analysis.reviewPriority.isEmpty {
                chipSection(title: "Review First", items: analysis.reviewPriority.prefix(3).map(\.title), tint: Color(red: 0.27, green: 0.43, blue: 0.55))
            }
        }
    }

    private var flashcardsDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            statRow(title: "Flashcards Available", value: "\(studyData.flashcards.count)")

            if let card = studyData.flashcards.first {
                VStack(alignment: .leading, spacing: 8) {
                    Text(card.type.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.type.tint)
                    Text(card.front)
                        .font(.headline)
                    Text(card.back)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.white.opacity(0.70))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                emptyCompactState(
                    title: "No flashcards yet",
                    message: "Generate materials to create study cards from the active note."
                )
            }
        }
    }

    private var quizDetail: some View {
        let multipleChoice = studyData.quizSets.flatMap(\.questions).filter { $0.type == .multipleChoice }.count
        let shortAnswer = studyData.quizSets.flatMap(\.questions).filter { $0.type == .shortAnswer }.count

        return VStack(alignment: .leading, spacing: 14) {
            statRow(title: "Quiz Sets", value: "\(studyData.quizSets.count)")
            statRow(title: "Multiple Choice", value: "\(multipleChoice)")
            statRow(title: "Short Answer", value: "\(shortAnswer)")

            emptyCompactState(
                title: "Quiz generator",
                message: "Turn the current note into practice questions, then review them in the Quizzes section."
            )
        }
    }

    private var summaryDetail: some View {
        VStack(alignment: .leading, spacing: 14) {
            statRow(title: "Summary Length", value: "\(summaryWordCount) words")
            emptyCompactState(
                title: "Summary generator",
                message: summaryPreview
            )
        }
    }

    private var keyConceptsDetail: some View {
        let concepts = effectiveKeyConcepts

        return VStack(alignment: .leading, spacing: 14) {
            statRow(title: "Key Concepts", value: "\(concepts.count)")

            if concepts.isEmpty {
                emptyCompactState(
                    title: "No key concepts yet",
                    message: "Generate materials or use Learning Insights to extract the important terms."
                )
            } else {
                chipSection(title: "Important Terms", items: concepts.prefix(8), tint: Color(red: 0.23, green: 0.47, blue: 0.59))
            }
        }
    }

    private func scoreRing(score: Double) -> some View {
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

            Text("\(Int((score.clamped(to: 0...1) * 100).rounded()))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
        }
        .frame(width: 92, height: 92)
    }

    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chipSection(title: String, items: ArraySlice<String>, tint: Color) -> some View {
        chipSection(title: title, items: Array(items), tint: tint)
    }

    private func chipSection(title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(tint.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func emptyCompactState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var noteSubtitle: String {
        if let generationSummary {
            return generationSummary
        }
        if let statusMessage {
            return statusMessage
        }
        return "Everything stays connected to the active note."
    }

    private var summaryPreview: String {
        if let generationSummary, !generationSummary.isEmpty {
            return generationSummary
        }
        let text = selectedExcerpt
        guard !text.isEmpty else {
            return "A generated summary will appear here once study materials are created."
        }
        return String(text.prefix(180)) + (text.count > 180 ? "..." : "")
    }

    private var summaryWordCount: Int {
        selectedExcerpt.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var effectiveKeyConcepts: [String] {
        if !studyData.insights.keyConcepts.isEmpty {
            return studyData.insights.keyConcepts
        }
        if !studyData.insights.importantConcepts.isEmpty {
            return studyData.insights.importantConcepts
        }
        return selectedExcerpt
            .split { $0.isWhitespace || $0.isNewline }
            .prefix(10)
            .map(String.init)
    }

    private func toolIcon(_ tool: StudyTool) -> String {
        tool.icon
    }

    private func toolTint(_ tool: StudyTool) -> Color {
        switch tool {
        case .learningInsights:
            return Color(red: 0.24, green: 0.49, blue: 0.59)
        case .flashcards:
            return Color(red: 0.31, green: 0.56, blue: 0.38)
        case .quizGenerator:
            return Color(red: 0.60, green: 0.45, blue: 0.20)
        case .summaryGenerator:
            return Color(red: 0.54, green: 0.38, blue: 0.61)
        case .keyConcepts:
            return Color(red: 0.27, green: 0.43, blue: 0.55)
        }
    }

    private var studyTabStrip: some View {
        let tabs = availableTabs

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(tabs) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(selectedTab == tab ? Color.white : Color(red: 0.22, green: 0.28, blue: 0.33))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(selectedTab == tab ? Color(red: 0.22, green: 0.44, blue: 0.58) : Color.white.opacity(0.78))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(selectedTab == tab ? 0 : 0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var studyContent: some View {
        switch selectedTab {
        case .flashcards:
            flashcardsWorkspace
        case .quizzes:
            quizzesWorkspace
        case .testMe:
            testMeWorkspace
        case .insights:
            insightsWorkspace
        case .learningInsights:
            LearningInsightsPanelView(
                noteTitle: noteTitle,
                studentNotes: resolvedStudentNotes,
                initialAnalysis: initialLearningInsights,
                onSaveAnalysis: saveLearningInsights
            )
        case .progress:
            progressWorkspace
        }
    }

    private var availableTabs: [StudyWorkspaceSection] {
        StudyWorkspaceSection.allCases.filter { section in
            switch section {
            case .flashcards:
                return !studyData.flashcards.isEmpty
            case .quizzes:
                return !studyData.quizSets.isEmpty
            case .testMe:
                return !studyData.tutorQuestions.isEmpty
            case .insights:
                return !studyData.insights.isEmpty
            case .learningInsights:
                return true
            case .progress:
                return !studyData.progress.quizAttempts.isEmpty
                    || !studyData.progress.testMeSessions.isEmpty
                    || studyData.progress.flashcardsCreated > 0
                    || studyData.progress.flashcardsReviewed > 0
            }
        }
    }

    private func syncSelectedTab() {
        if availableTabs.contains(selectedTab) {
            return
        }

        selectedTab = preferredGeneratedSection ?? .learningInsights
    }

    private var flashcardsWorkspace: some View {
        workspaceCard(title: "Flashcards", subtitle: "\(studyData.flashcards.count) cards available.") {
            if studyData.flashcards.isEmpty {
                emptyWorkspaceState(
                    title: "No flashcards yet",
                    message: "Generate study materials to create flashcards from the note content."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(studyData.flashcards.prefix(6)) { card in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(card.type.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(card.type.tint)
                                Spacer()
                                Text(card.whyItMatters)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(card.front)
                                .font(.headline)
                            Text(card.back)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var quizzesWorkspace: some View {
        workspaceCard(title: "Quizzes", subtitle: "\(studyData.quizSets.count) quiz set(s) available.") {
            if studyData.quizSets.isEmpty {
                emptyWorkspaceState(
                    title: "No quizzes yet",
                    message: "Generate materials to create quiz questions for this lecture."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(studyData.quizSets) { quizSet in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(quizSet.title)
                                .font(.headline)
                            Text("\(quizSet.questions.count) questions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(quizTypeSummary(for: quizSet))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var testMeWorkspace: some View {
        workspaceCard(title: "Test Me", subtitle: "\(studyData.tutorQuestions.count) tutor prompt(s) available.") {
            if studyData.tutorQuestions.isEmpty {
                emptyWorkspaceState(
                    title: "No tutor prompts yet",
                    message: "Generate materials to create guided recall questions."
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(studyData.tutorQuestions) { question in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(question.concept.isEmpty ? "Concept" : question.concept)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.27, green: 0.45, blue: 0.32))
                            Text(question.prompt)
                                .font(.headline)
                            Text(question.expectedAnswer)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var insightsWorkspace: some View {
        workspaceCard(title: "Insights", subtitle: "Key concepts and study signals.") {
            if studyData.insights.isEmpty {
                emptyWorkspaceState(
                    title: "No insights yet",
                    message: "Generate materials to populate concept insights for this note."
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    insightGroup(title: "Key Concepts", items: studyData.insights.keyConcepts)
                    insightGroup(title: "Important Concepts", items: studyData.insights.importantConcepts)
                    insightGroup(title: "Potential Exam Topics", items: studyData.insights.potentialExamTopics)
                    insightGroup(title: "Knowledge Gaps", items: studyData.insights.knowledgeGaps)
                }
            }
        }
    }

    private var progressWorkspace: some View {
        workspaceCard(title: "Progress", subtitle: "Track practice and recall sessions.") {
            let hasProgress = !studyData.progress.quizAttempts.isEmpty
                || !studyData.progress.testMeSessions.isEmpty
                || studyData.progress.flashcardsCreated > 0
                || studyData.progress.flashcardsReviewed > 0

            if !hasProgress {
                emptyWorkspaceState(
                    title: "No progress yet",
                    message: "Complete quizzes or Test Me sessions to track your study history."
                )
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        progressMetric(title: "Flashcards Created", value: "\(studyData.progress.flashcardsCreated)")
                        progressMetric(title: "Reviewed", value: "\(studyData.progress.flashcardsReviewed)")
                        progressMetric(title: "Avg Quiz Score", value: "\(studyData.progress.averageQuizScore)%")
                        progressMetric(title: "Best Quiz Score", value: "\(studyData.progress.bestQuizScore)%")
                    }

                    if !studyData.progress.quizAttempts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quiz Attempts")
                                .font(.headline)
                            ForEach(studyData.progress.quizAttempts.prefix(4)) { attempt in
                                HStack {
                                    Text(attempt.quizTitle)
                                    Spacer()
                                    Text("\(attempt.percentage, specifier: "%.0f")%")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
            }
        }
    }

    private func workspaceCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func emptyWorkspaceState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func insightGroup(title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if items.isEmpty {
                Text("No items captured yet.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)")
                            .font(.subheadline)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private func progressMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var resolvedStudentNotes: String {
        if let noteID {
            let noteContent = appState.noteContent(for: noteID).trimmingCharacters(in: .whitespacesAndNewlines)
            if !noteContent.isEmpty {
                return noteContent
            }
        }

        let fallback = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty {
            return fallback
        }

        return noteHasContent ? selectedText : ""
    }

    private var initialLearningInsights: LectureCompletenessAnalysis? {
        guard let noteID else { return nil }
        return appState.studyData(for: noteID).learningInsights
    }

    private func saveLearningInsights(_ analysis: LectureCompletenessAnalysis) {
        guard let noteID else { return }
        appState.mutateStudyData(for: noteID) { studyData in
            studyData.learningInsights = analysis
            studyData.lastGeneratedAt = analysis.generatedAt
        }
    }

    private func submitQuiz(_ quizSet: StudyQuizSet) {
        guard var quizSession, quizSession.quizSetID == quizSet.id else { return }
        let score = quizSet.questions.reduce(0) { partial, question in
            let answer = quizSession.answers[question.id, default: ""]
            return partial + (quizAnswerIsCorrect(question: question, answer: answer) ? 1 : 0)
        }

        quizSession.score = score
        quizSession.isSubmitted = true

        if !quizSession.didPersistAttempt {
            onRecordQuizAttempt(quizSet, score, quizSet.questions.count)
            quizSession.didPersistAttempt = true
        }

        self.quizSession = quizSession
    }

    private func quizAnswerIsCorrect(question: StudyQuizQuestion, answer: String) -> Bool {
        switch question.type {
        case .multipleChoice, .trueFalse:
            return normalizeStudyText(answer) == normalizeStudyText(question.correctAnswer)
        case .shortAnswer:
            return StudySemanticGrader.shared.gradeShortAnswer(
                studentAnswer: answer,
                correctAnswer: question.correctAnswer,
                keywords: question.keywords
            ).isCorrect
        }
    }

    private func evaluateCurrentTutorAnswer(question: StudyTutorQuestion) {
        let answer = tutorSession.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        tutorSession.isEvaluating = true
        onEvaluateTestMe(question, answer) { evaluation in
            tutorSession.isEvaluating = false
            tutorSession.currentEvaluation = evaluation
            tutorSession.score += evaluation.awardedPoint
            tutorSession.turns.append(
                StudyTutorTurn(
                    questionID: question.id,
                    concept: question.concept,
                    answer: answer,
                    evaluation: evaluation
                )
            )
        }
    }

    private func advanceTutorSession() {
        guard tutorSession.currentIndex < studyData.tutorQuestions.count - 1 else {
            completeTutorSession()
            return
        }

        tutorSession.currentIndex += 1
        tutorSession.answerText = ""
        tutorSession.currentEvaluation = nil
    }

    private func completeTutorSession() {
        if !tutorSession.didPersistCompletion {
            let concepts = Array(Set(tutorSession.turns.filter { $0.evaluation.verdict != .correct }.map(\.concept))).filter { !$0.isEmpty }
            onRecordTestMeSession(tutorSession.score, max(1, tutorSession.turns.count), concepts)
            tutorSession.didPersistCompletion = true
        }

        tutorSession.isActive = false
        tutorSession.isComplete = true
        tutorSession.answerText = ""
        tutorSession.currentEvaluation = nil
    }

    private func quizTypeSummary(for quizSet: StudyQuizSet) -> String {
        let multipleChoice = quizSet.questions.filter { $0.type == .multipleChoice }.count
        let trueFalse = quizSet.questions.filter { $0.type == .trueFalse }.count
        let shortAnswer = quizSet.questions.filter { $0.type == .shortAnswer }.count

        var parts: [String] = []
        if multipleChoice > 0 { parts.append("\(multipleChoice) multiple choice") }
        if trueFalse > 0 { parts.append("\(trueFalse) true/false") }
        if shortAnswer > 0 { parts.append("\(shortAnswer) short answer") }
        return parts.joined(separator: ", ")
    }
}

private extension StudyQuizQuestion {
    var optionsForDisplay: [String] {
        switch type {
        case .multipleChoice:
            return options
        case .trueFalse:
            return options.isEmpty ? ["True", "False"] : options
        case .shortAnswer:
            return []
        }
    }
}

final class StudySemanticGrader {
    static let shared = StudySemanticGrader()

    struct Result {
        let isCorrect: Bool
        let score: Float
        let reasoning: String
    }

    private init() {}

    func gradeShortAnswer(studentAnswer: String, correctAnswer: String, keywords: [String]) -> Result {
        let normalizedStudent = normalizeStudyText(studentAnswer)
        let normalizedCorrect = normalizeStudyText(correctAnswer)

        if normalizedStudent == normalizedCorrect {
            return Result(isCorrect: true, score: 1.0, reasoning: "Exact match")
        }

        if let semanticScore = semanticSimilarity(studentAnswer, correctAnswer), semanticScore >= 0.90 {
            return Result(isCorrect: true, score: semanticScore, reasoning: "Semantic match")
        }

        let keywordScore = keywordOverlapScore(studentAnswer: studentAnswer, correctAnswer: correctAnswer, keywords: keywords)
        if keywordScore >= 0.75 {
            return Result(isCorrect: true, score: keywordScore, reasoning: "Keyword overlap")
        }

        return Result(isCorrect: false, score: max(semanticSimilarity(studentAnswer, correctAnswer) ?? 0, keywordScore), reasoning: "Needs review")
    }

    func tutorEvaluation(studentAnswer: String, correctAnswer: String, keywords: [String]) -> StudyTutorEvaluation {
        let result = gradeShortAnswer(studentAnswer: studentAnswer, correctAnswer: correctAnswer, keywords: keywords)
        let verdict: StudyTutorVerdict
        let awardedPoint: Int

        switch result.score {
        case 0.90...:
            verdict = .correct
            awardedPoint = 1
        case 0.75..<0.90:
            verdict = .almost
            awardedPoint = 1
        case 0.60..<0.75:
            verdict = .almost
            awardedPoint = 0
        default:
            verdict = .incorrect
            awardedPoint = 0
        }

        return StudyTutorEvaluation(
            verdict: verdict,
            feedback: feedbackMessage(for: verdict, score: result.score),
            explanation: result.reasoning,
            modelAnswer: correctAnswer,
            awardedPoint: awardedPoint
        )
    }

    private func semanticSimilarity(_ first: String, _ second: String) -> Float? {
        EmbeddingService.shared.similarity(between: first, and: second)
    }

    private func keywordOverlapScore(studentAnswer: String, correctAnswer: String, keywords: [String]) -> Float {
        let studentTokens = Set(normalizeStudyText(studentAnswer).split(separator: " ").map(String.init))
        let answerTokens = Set(normalizeStudyText(correctAnswer).split(separator: " ").map(String.init))
        let keywordTokens = Set(keywords.flatMap { normalizeStudyText($0).split(separator: " ").map(String.init) })
        let expectedTokens = answerTokens.union(keywordTokens)
        guard !expectedTokens.isEmpty else { return 0 }

        let overlap = studentTokens.intersection(expectedTokens)
        return Float(overlap.count) / Float(expectedTokens.count)
    }

    private func feedbackMessage(for verdict: StudyTutorVerdict, score: Float) -> String {
        switch verdict {
        case .correct:
            return "Strong conceptual answer."
        case .almost:
            return score >= 0.75 ? "Mostly correct with minor gaps." : "Partial understanding is visible."
        case .incorrect:
            return "Review the core concept and try again."
        }
    }
}

func normalizeStudyText(_ text: String) -> String {
    text
        .lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
