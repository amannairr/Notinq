import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsOverlayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var authErrorMessage: String?
    @State private var modelPathSummary: String = AIModelManager.shared.currentModelPathDescription()
    @State private var researchStatistics: ResearchEventStatistics = .empty
    @State private var researchExportStatus: String?
    #if DEBUG
    @State private var isShowingAIEvaluation = false
    @State private var isShowingLocalAIPlayground = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        appState.isSettingsOpen = false
                    }

                VStack(alignment: .leading, spacing: 20) {
                    header
                    aiSettingsSection
                    privacySection
                    researchSection
                    voiceSection
                    accountSection
                    debugSection
                }
                .padding(24)
                .frame(width: 460)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 26, x: 0, y: 14)
            }
            .onAppear {
                modelPathSummary = AIModelManager.shared.currentModelPathDescription()
                refreshResearchStatistics()
            }
            .onReceive(NotificationCenter.default.publisher(for: .notinqLocalModelDidChange)) { _ in
                modelPathSummary = AIModelManager.shared.currentModelPathDescription()
            }
            #if DEBUG
            .sheet(isPresented: $isShowingAIEvaluation) {
                AIEvaluationView()
            }
            .sheet(isPresented: $isShowingLocalAIPlayground) {
                LocalAIPlaygroundView()
            }
            #endif
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 24, weight: .semibold))
            Spacer()
            Button(action: { appState.isSettingsOpen = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var aiSettingsSection: some View {
        section("AI Settings") {
            Picker("AI Mode", selection: $appState.aiMode) {
                Text("Auto").tag(AIMode.auto)
                Text("Local").tag(AIMode.local)
                Text("Advanced (Cloud)").tag(AIMode.advancedCloud)
            }
            .pickerStyle(.segmented)
            .onChange(of: appState.aiMode) { _, _ in appState.persistPreferences() }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local Model")
                        .font(.system(size: 13, weight: .medium))
                    Text(modelPathSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button("Select…") {
                    Task { @MainActor in
                        AIModelManager.shared.chooseLocalModelFile()
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack {
                Text("Default Action Style")
                Spacer()
                Picker("Default Action Style", selection: $appState.defaultActionStyle) {
                    Text("Concise").tag(DefaultActionStyle.concise)
                    Text("Detailed").tag(DefaultActionStyle.detailed)
                    Text("Bullet Points").tag(DefaultActionStyle.bulletPoints)
                }
                .labelsHidden()
                .frame(width: 190)
            }
            .onChange(of: appState.defaultActionStyle) { _, _ in appState.persistPreferences() }

            Toggle("Enable Streaming Responses", isOn: $appState.enableStreamingResponses)
                .onChange(of: appState.enableStreamingResponses) { _, _ in appState.persistPreferences() }
        }
    }

    private var privacySection: some View {
        section("Privacy") {
            Toggle("Allow cloud AI for complex tasks", isOn: $appState.allowCloudAIForComplexTasks)
                .onChange(of: appState.allowCloudAIForComplexTasks) { _, _ in appState.persistPreferences() }

            Toggle("Private Notes Mode (never send to cloud)", isOn: $appState.privateNotesMode)
                .onChange(of: appState.privateNotesMode) { _, _ in appState.persistPreferences() }
        }
    }

    private var researchSection: some View {
        section("Research") {
            Toggle("Research Instrumentation", isOn: $appState.researchInstrumentationEnabled)
                .onChange(of: appState.researchInstrumentationEnabled) { _, _ in
                    appState.persistPreferences()
                    refreshResearchStatistics()
                }

            Text("Stores local, aggregate workflow events only. Note text, transcripts, audio, and personal identifiers are not collected.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                researchStatisticRow("Total events", researchStatistics.totalEvents)
                researchStatisticRow("AI proposals generated", researchStatistics.proposalsGenerated)
                researchStatisticRow("Accepted", researchStatistics.proposalsAccepted)
                researchStatisticRow("Rejected", researchStatistics.proposalsRejected)
                researchStatisticRow("Edited", researchStatistics.proposalsEdited)
                researchStatisticRow("Knowledge gaps detected", researchStatistics.knowledgeGapsDetected)
                researchStatisticRow("Resolved", researchStatistics.knowledgeGapsResolved)
                researchStatisticRow("Questions answered", researchStatistics.questionsAnswered)
                researchStatisticRow("Teach Me sessions completed", researchStatistics.teachMeSessionsCompleted)
            }
            .padding(10)
            .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 8) {
                Button("Export JSON") {
                    exportResearchDataset(format: .json)
                }
                .buttonStyle(.bordered)

                Button("Export CSV") {
                    exportResearchDataset(format: .csv)
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if let researchExportStatus {
                Text(researchExportStatus)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var voiceSection: some View {
        section("Voice") {
            Toggle("Auto-insert transcription", isOn: $appState.autoInsertTranscription)
                .onChange(of: appState.autoInsertTranscription) { _, _ in appState.persistPreferences() }

            Toggle("Use voice as AI command input", isOn: $appState.useVoiceAsAICommandInput)
                .onChange(of: appState.useVoiceAsAICommandInput) { _, _ in appState.persistPreferences() }
        }
    }

    private var accountSection: some View {
        section("Account") {
            if appState.isLoggedIn {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appState.userEmail ?? "Signed in")
                        .font(.system(size: 13, weight: .medium))
                    Text("Connected to Gemini")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Button("Sign out") {
                    AuthService.shared.signOut()
                    appState.refreshAuthState()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Sign in with Google") {
                    AuthService.shared.signIn { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success:
                                authErrorMessage = nil
                                appState.refreshAuthState()
                            case .failure(let error):
                                authErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                if let authErrorMessage {
                    Text(authErrorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    #if DEBUG
    private var debugSection: some View {
        section("Developer") {
            Button("Open AI Evaluation") {
                isShowingAIEvaluation = true
            }
            .buttonStyle(.bordered)

            Button("Open Local AI Playground") {
                isShowingLocalAIPlayground = true
            }
            .buttonStyle(.bordered)

            NavigationLink("Knowledge Extraction Tests") {
                ExtractionTestView()
            }
            .buttonStyle(.bordered)
        }
    }
    #else
    private var debugSection: some View {
        EmptyView()
    }
    #endif

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            content()
        }
    }

    private func researchStatisticRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value.formatted())
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }

    private func refreshResearchStatistics() {
        researchStatistics = ResearchInstrumentationService.shared.statistics()
    }

    private func exportResearchDataset(format: ResearchDatasetExportFormat) {
        refreshResearchStatistics()

        let savePanel = NSSavePanel()
        savePanel.title = "Export Research Dataset"
        savePanel.nameFieldStringValue = format.defaultFileName
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.canCreateDirectories = true

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            do {
                let data = try format.exportData(from: ResearchInstrumentationService.shared)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    researchExportStatus = "Exported \(format.displayName) research dataset."
                    refreshResearchStatistics()
                }
            } catch {
                DispatchQueue.main.async {
                    researchExportStatus = "Export failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum ResearchDatasetExportFormat {
    case json
    case csv

    var displayName: String {
        switch self {
        case .json: return "JSON"
        case .csv: return "CSV"
        }
    }

    var defaultFileName: String {
        switch self {
        case .json: return "notinq-research-events.json"
        case .csv: return "notinq-research-events.csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .json:
            return .json
        case .csv:
            return UTType(filenameExtension: "csv") ?? .plainText
        }
    }

    func exportData(from service: ResearchInstrumentationService) throws -> Data {
        switch self {
        case .json:
            return try service.jsonExportData()
        case .csv:
            return service.csvExportData()
        }
    }
}
