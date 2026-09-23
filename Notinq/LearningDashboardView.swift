import SwiftUI

struct LearningDashboardView: View {
    @StateObject private var viewModel = LearningDashboardViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                progressSection
                todaysPlanSection
                dueReviewsSection
                topicSection
                learningGapsSection
                recommendedReviewsSection
                graphStatisticsSection
            }
            .padding(24)
            .frame(maxWidth: 1120, alignment: .leading)
            .redacted(reason: viewModel.isLoading ? .placeholder : [])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgEditor)
        .onAppear { viewModel.load() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Learning Dashboard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Knowledge graph and student model summary.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading learning dashboard")
            } else {
                Text("Loaded in \(Int(viewModel.loadDurationMilliseconds.rounded())) ms")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.bgElevated)
                    .clipShape(Capsule())
            }
        }
    }

    private var progressSection: some View {
        section(title: "Overall Progress") {
            LazyVGrid(columns: columns, spacing: 14) {
                metricCard(title: "Mastery", value: percent(viewModel.masteryScore), tint: Color(red: 0.25, green: 0.47, blue: 0.58))
                metricCard(title: "Retention", value: percent(viewModel.retentionScore), tint: Color(red: 0.33, green: 0.55, blue: 0.39))
                metricCard(title: "Confidence", value: percent(viewModel.confidenceScore), tint: Color(red: 0.43, green: 0.39, blue: 0.67))
                metricCard(title: "Exam Readiness", value: percent(viewModel.examReadiness), tint: Color(red: 0.58, green: 0.43, blue: 0.23))
            }
            metricCard(title: "Study Streak", value: "\(viewModel.studyStreak) days", tint: Color(red: 0.42, green: 0.48, blue: 0.52))
        }
    }

    private var topicSection: some View {
        HStack(alignment: .top, spacing: 14) {
            topicList(title: "Weak Topics", topics: viewModel.weakTopics, empty: "No weak topics available.")
            topicList(title: "Strong Topics", topics: viewModel.strongTopics, empty: "No strong topics available.")
        }
    }

    private var todaysPlanSection: some View {
        section(title: "Today's Plan") {
            if viewModel.todaysPlan.isEmpty {
                emptyText("No study tasks available yet.")
            } else {
                ForEach(viewModel.todaysPlan.prefix(6)) { task in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(task.concept)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(task.estimatedMinutes) min")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("Reason: \(task.reasonText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var dueReviewsSection: some View {
        section(title: "Due Reviews") {
            if viewModel.dueReviews.isEmpty {
                emptyText("No scheduled reviews available.")
            } else {
                ForEach(viewModel.dueReviews.prefix(6)) { review in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(review.conceptName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(review.statusText)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(review.daysUntilDue < 0 ? Color.red : .secondary)
                        }
                        Text("Retention: \(percent(review.retention)) · \(review.riskText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var learningGapsSection: some View {
        section(title: "Learning Gaps") {
            if viewModel.learningGaps.isEmpty {
                emptyText("No graph-backed learning gaps detected yet.")
            } else {
                ForEach(viewModel.learningGaps) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weak: \(item.weakConcept)")
                            .font(.subheadline.weight(.semibold))
                        Text(item.blockedTopics.isEmpty ? "Blocks: None detected" : "Blocks: \(item.blockedTopics.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var recommendedReviewsSection: some View {
        section(title: "Recommended Reviews") {
            if viewModel.recommendedReviews.isEmpty {
                emptyText("No review recommendations available.")
            } else {
                ForEach(viewModel.recommendedReviews) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Review: \(item.concept)")
                            .font(.subheadline.weight(.semibold))
                        Text("Reason: \(item.reason)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.52))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var graphStatisticsSection: some View {
        section(title: "Graph Statistics") {
            LazyVGrid(columns: columns, spacing: 14) {
                metricCard(title: "Concepts", value: "\(viewModel.graphStatistics.conceptCount)", tint: Color(red: 0.25, green: 0.47, blue: 0.58))
                metricCard(title: "Relationships", value: "\(viewModel.graphStatistics.relationshipCount)", tint: Color(red: 0.33, green: 0.55, blue: 0.39))
                metricCard(title: "Connected Components", value: "\(viewModel.graphStatistics.connectedComponents)", tint: Color(red: 0.43, green: 0.39, blue: 0.67))
                metricCard(title: "Average Degree", value: String(format: "%.1f", viewModel.graphStatistics.averageDegree), tint: Color(red: 0.58, green: 0.43, blue: 0.23))
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(Color.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.borderSubtle, lineWidth: 0.6)
        )
    }

    private func metricCard(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value)")
    }

    private func topicList(title: String, topics: [String], empty: String) -> some View {
        section(title: title) {
            if topics.isEmpty {
                emptyText(empty)
            } else {
                ForEach(topics.prefix(8), id: \.self) { topic in
                    Text(topic)
                        .font(.subheadline.weight(.medium))
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
