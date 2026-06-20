import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var styleState = TextStyleState()
    @State private var bridge = TextViewBridge()

    private var selectedNoteID: UUID? {
        appState.selectedNoteID
    }

    private var noteTitle: String {
        guard let selectedNoteID else { return "Untitled Note" }
        return appState.noteTitle(for: selectedNoteID)
    }

    private var noteContentBinding: Binding<String> {
        Binding(
            get: {
                guard let selectedNoteID else { return "" }
                return appState.noteContent(for: selectedNoteID)
            },
            set: { newValue in
                guard let selectedNoteID else { return }
                appState.updateNoteContent(newValue, for: selectedNoteID)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorTopBar(
                bridge: bridge,
                styleState: $styleState,
                onAskAI: {
                    appState.selectedMode = .ai
                },
                onGenerateStudyMaterials: {
                    appState.selectedMode = .study
                },
                isGeneratingStudyMaterials: false,
                canGenerateStudyMaterials: selectedNoteID != nil
            )

            Divider()
                .opacity(0.08)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(noteTitle)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                    }

                    Spacer()
                }

                if selectedNoteID != nil {
                    TextEditor(text: noteContentBinding)
                        .font(.system(.body, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No note selected")
                            .font(.headline)
                        Text("Choose a note from the sidebar to begin editing.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color.white.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgEditor)
    }
}
