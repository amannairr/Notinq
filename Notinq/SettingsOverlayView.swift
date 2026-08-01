import SwiftUI

struct SettingsOverlayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var authErrorMessage: String?
    @State private var modelPathSummary: String = AIModelManager.shared.currentModelPathDescription()
    #if DEBUG
    @State private var isShowingAIEvaluation = false
    @State private var isShowingLocalAIPlayground = false
    #endif

    var body: some View {
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
}
