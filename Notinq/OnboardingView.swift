import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    Text(viewModel.progressText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button("Skip") {
                        viewModel.skip()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHint("Dismisses onboarding and opens Notinq")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.currentStep.title)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(viewModel.currentStep.message)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ProgressView(value: Double(viewModel.currentStepIndex + 1), total: Double(viewModel.steps.count))
                    .accessibilityLabel("Onboarding progress")
                    .accessibilityValue(viewModel.progressText)

                HStack(spacing: 10) {
                    Button("Back") {
                        viewModel.goBack()
                    }
                    .disabled(!viewModel.canGoBack)

                    Spacer()

                    Button(viewModel.currentStep.actionTitle) {
                        viewModel.advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 460)
            .background(Color.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.borderSubtle, lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 14)
            .accessibilityElement(children: .contain)
        }
    }
}
