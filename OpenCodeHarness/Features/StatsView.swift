import Charts
import AppKit
import SwiftUI

struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.ocBorder).frame(height: 0.5)
            if let stats = model.stats {
                content(stats)
            } else if model.isRefreshing {
                Spacer()
                Spinner(size: 22)
                Spacer()
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("Loading usage…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.ocTextTertiary)
                    Spacer()
                }
            }
        }
        .background(Color.ocCanvas)
        .task {
            if model.stats == nil { await model.loadStats() }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.ocAccent.opacity(0.10))
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ocAccent)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage & activity")
                    .font(.ocRounded(19, weight: .bold))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(model.workspace?.name ?? "All projects")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            Spacer()
            Button {
                Task { await model.loadStats() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.ocHover))
            .foregroundStyle(Color.ocTextSecondary)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.ocHover))
            .foregroundStyle(Color.ocTextSecondary)
        }
        .padding(.horizontal, 22)
        .frame(height: 66)
    }

    private func content(_ stats: SessionStatsInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    statCard("Sessions", "\(stats.sessions)", icon: "bubble.left.and.bubble.right", tint: .ocAccent)
                    statCard("Prompts", "\(stats.prompts)", icon: "text.bubble", tint: .ocTeal)
                    statCard("Tokens", Format.tokens(stats.tokens.total), icon: "text.word.spacing", tint: .ocViolet)
                    statCard("Cost", Format.cost(stats.cost), icon: "dollarsign.circle", tint: .ocWarning)
                }

                activityChart(stats)

                HStack(alignment: .top, spacing: 12) {
                    modelsCard(stats)
                    toolsCard(stats)
                }

                HStack(spacing: 10) {
                    miniStat("Active days", "\(stats.activeDays)", icon: "calendar")
                    miniStat("Streak", "\(stats.streak ?? 0) days", icon: "flame")
                    miniStat("Steps", "\(stats.steps)", icon: "figure.walk")
                    miniStat("Subagents", "\(stats.subagents ?? 0)", icon: "person.2")
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private func statCard(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.ocRounded(23, weight: .bold))
                .foregroundStyle(Color.ocTextPrimary)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.ocMono(8.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.ocTextTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .cardSurface(radius: 11)
    }

    private func activityChart(_ stats: SessionStatsInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITY")
                    .font(.ocMono(8.5, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Color.ocTextTertiary)
                Spacer()
                Text(rangeLabel(stats))
                    .font(.ocMono(8.5))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            if stats.activity.isEmpty {
                Text("No activity recorded for this range.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.ocTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(activityPoints(stats)) { point in
                    AreaMark(
                        x: .value("Day", point.date),
                        y: .value("Steps", point.steps)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.ocAccent.opacity(0.35), Color.ocAccent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Day", point.date),
                        y: .value("Steps", point.steps)
                    )
                    .foregroundStyle(Color.ocAccent)
                    .lineStyle(StrokeStyle(lineWidth: 1.7, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(Color.ocBorder)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                            .font(.ocMono(8))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(Color.ocBorder)
                        AxisValueLabel()
                            .font(.ocMono(8))
                            .foregroundStyle(Color.ocTextTertiary)
                    }
                }
                .frame(height: 150)
            }
        }
        .padding(13)
        .cardSurface(radius: 11)
    }

    private func modelsCard(_ stats: SessionStatsInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("MODELS")
                .font(.ocMono(8.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.ocTextTertiary)
            if stats.models.isEmpty {
                Text("No model usage yet.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(stats.models.prefix(6)) { usage in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(usage.model.shortName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Color.ocTextPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.cost(usage.cost))
                                .font(.ocMono(8.5))
                                .foregroundStyle(Color.ocTextTertiary)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.ocHover)
                                Capsule()
                                    .fill(Color.ocAccent.opacity(0.65))
                                    .frame(width: proxy.size.width * fraction(usage, stats: stats))
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .cardSurface(radius: 11)
    }

    private func toolsCard(_ stats: SessionStatsInfo) -> some View {
        let tools = stats.tools?["usage"]?.array ?? []
        return VStack(alignment: .leading, spacing: 9) {
            Text("TOOLS")
                .font(.ocMono(8.5, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Color.ocTextTertiary)
            if tools.isEmpty {
                Text("Enable detailed tool stats with `tools=detail`.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.ocTextTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(Array(tools.prefix(6).enumerated()), id: \.offset) { _, tool in
                    HStack {
                        Text(tool["name"]?.string ?? "tool")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.ocTextPrimary)
                        Spacer()
                        Text("\(tool["calls"]?.int ?? 0) calls")
                            .font(.ocMono(8.5))
                            .foregroundStyle(Color.ocTextTertiary)
                        if let failed = tool["failed"]?.int, failed > 0 {
                            Text("\(failed) failed")
                                .font(.ocMono(8))
                                .foregroundStyle(Color.ocDanger)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .cardSurface(radius: 11)
    }

    private func miniStat(_ label: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.ocTextTertiary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ocTextPrimary)
                Text(label)
                    .font(.ocMono(8))
                    .foregroundStyle(Color.ocTextTertiary)
            }
            Spacer()
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: 9)
    }

    private func fraction(_ usage: StatsModelUsage, stats: SessionStatsInfo) -> CGFloat {
        let maxCost = stats.models.map(\.cost).max() ?? 1
        guard maxCost > 0 else { return 0.05 }
        return max(0.04, CGFloat(usage.cost / maxCost))
    }

    private struct DailyPoint: Identifiable {
        var date: Date
        var steps: Int
        var id: Date { date }
    }

    private func activityPoints(_ stats: SessionStatsInfo) -> [DailyPoint] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return stats.activity.compactMap { item in
            guard let date = formatter.date(from: item.date) else { return nil }
            return DailyPoint(date: date, steps: item.steps)
        }
    }

    private func rangeLabel(_ stats: SessionStatsInfo) -> String {
        let from = Date(timeIntervalSince1970: stats.range.from / 1000)
        let to = Date(timeIntervalSince1970: stats.range.to / 1000)
        return "\(from.formatted(.dateTime.month(.abbreviated).day())) – \(to.formatted(.dateTime.month(.abbreviated).day()))"
    }

}
