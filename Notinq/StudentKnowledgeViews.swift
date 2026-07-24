import SwiftUI

struct StudentKnowledgeOverviewCard: View {
    let summary: StudentKnowledgeDashboardSummary
    let title: String

    private let tint = Color(red: 0.34, green: 0.52, blue: 0.62)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            statsGrid
            distributionView
            reviewCalendarView
            conceptLists
            emptyState
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text("Persistent student mastery and review scheduling.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            statPill(title: "Mastered", value: summary.masteredConcepts, color: .green)
            statPill(title: "Learning", value: summary.learningConcepts, color: Color(red: 0.28, green: 0.43, blue: 0.66))
            statPill(title: "Review", value: summary.reviewConcepts, color: Color(red: 0.80, green: 0.54, blue: 0.20))
            statPill(title: "Forgotten", value: summary.forgottenConcepts, color: Color(red: 0.73, green: 0.35, blue: 0.33))
        }
    }

    private var distributionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mastery distribution")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(summary.masteryDistribution) { bucket in
                HStack(spacing: 8) {
                    Text(bucket.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.black.opacity(0.06))
                            Capsule()
                                .fill(tint.opacity(0.78))
                                .frame(width: max(8, proxy.size.width * normalizedCount(bucket.count)))
                        }
                    }
                    .frame(height: 8)
                    Text("\(bucket.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                }
            }
        }
    }

    private var reviewCalendarView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(summary.reviewCalendar.prefix(7)) { day in
                    VStack(spacing: 5) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("\(day.dueCount)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(day.dueCount > 0 ? tint : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(day.dueCount > 0 ? tint.opacity(0.10) : Color.black.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var conceptLists: some View {
        VStack(alignment: .leading, spacing: 10) {
            conceptList(title: "Strongest", concepts: summary.strongestConcepts.prefix(3))
            conceptList(title: "Weakest", concepts: summary.weakestConcepts.prefix(3))
        }
    }

    @ViewBuilder
    private func conceptList(title: String, concepts: ArraySlice<StudentKnowledgeConceptRecord>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if concepts.isEmpty {
                Text("No concepts yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(concepts)) { concept in
                    HStack(alignment: .top, spacing: 8) {
                        Text(concept.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(Int((concept.masteryLevel * 100).rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        Group {
            if summary.totalConcepts == 0 {
                Text("Create or generate study materials to begin tracking concept mastery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func statPill(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func normalizedCount(_ count: Int) -> CGFloat {
        guard summary.masteryDistribution.map(\.count).max() ?? 0 > 0 else { return 0 }
        return CGFloat(count) / CGFloat(summary.masteryDistribution.map(\.count).max() ?? 1)
    }
}
