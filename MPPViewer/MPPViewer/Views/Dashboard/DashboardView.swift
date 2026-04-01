import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?
    @AppStorage("taskReviewNotes") private var taskReviewNotesData: Data = Data()

    var body: some View {
        Group {
            if let stats = stats {
                dashboardContent(stats: stats)
            } else {
                ProgressView("Loading dashboard...")
            }
        }
        .task {
            let computed = ProjectStats(project: project)
            stats = computed
        }
    }

    private func dashboardContent(stats: ProjectStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button {
                        exportReviewPack()
                    } label: {
                        Label("Export Review Pack", systemImage: "doc.richtext")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                    Button {
                        exportExecutiveSummary(stats: stats)
                    } label: {
                        Label("Export Summary", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                }

                // Top KPI Cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                ], spacing: 16) {
                    KPICard(
                        title: "Average Task Progress",
                        value: "\(stats.averageProgressPercent)%",
                        subtitle: "\(stats.completedPercent)% of work tasks completed",
                        icon: "chart.pie.fill",
                        color: stats.averageProgressPercent >= 75 ? .green : stats.averageProgressPercent >= 40 ? .blue : .orange,
                        progress: Double(stats.averageProgressPercent) / 100.0
                    )

                    KPICard(
                        title: "On Track",
                        value: "\(stats.onTrackTasks)",
                        subtitle: "\(stats.behindTasks) behind schedule",
                        icon: "checkmark.circle.fill",
                        color: stats.behindTasks == 0 ? .green : .orange
                    )

                    KPICard(
                        title: "Critical Tasks",
                        value: "\(stats.criticalTasks)",
                        subtitle: "\(stats.criticalIncompleteTasks) incomplete",
                        icon: "exclamationmark.triangle.fill",
                        color: stats.criticalIncompleteTasks > 0 ? .red : .green
                    )

                    KPICard(
                        title: "Total Cost",
                        value: stats.totalCostFormatted,
                        subtitle: "across \(stats.totalWorkTasks) tasks",
                        icon: "dollarsign.circle.fill",
                        color: .blue
                    )
                }

                // EVM KPI Row
                if stats.evmMetrics.bac > 0 {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16),
                    ], spacing: 16) {
                        KPICard(
                            title: "Cost Performance (CPI)",
                            value: String(format: "%.2f", stats.evmMetrics.cpi),
                            subtitle: stats.evmMetrics.cpi >= 1.0 ? "Under budget" : "Over budget",
                            icon: "dollarsign.circle.fill",
                            color: stats.evmMetrics.cpi >= 1.0 ? .green : .red
                        )
                        KPICard(
                            title: "Schedule Performance (SPI)",
                            value: String(format: "%.2f", stats.evmMetrics.spi),
                            subtitle: stats.evmMetrics.spi >= 1.0 ? "Ahead of schedule" : "Behind schedule",
                            icon: "clock.fill",
                            color: stats.evmMetrics.spi >= 1.0 ? .green : .red
                        )
                    }
                }

                // Second Row
                HStack(alignment: .top, spacing: 16) {
                    // Task Status Breakdown
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Task Status")
                                .font(.headline)

                            StatusBar(segments: [
                                StatusSegment(label: "Completed", count: stats.completedTasks, color: .green),
                                StatusSegment(label: "In Progress", count: stats.inProgressTasks, color: .blue),
                                StatusSegment(label: "Not Started", count: stats.notStartedTasks, color: .gray),
                                StatusSegment(label: "Overdue", count: stats.overdueTasks, color: .red),
                            ], total: stats.totalWorkTasks)

                            Divider()

                            HStack(spacing: 20) {
                                statusLegend("Completed", count: stats.completedTasks, color: .green)
                                statusLegend("In Progress", count: stats.inProgressTasks, color: .blue)
                                statusLegend("Not Started", count: stats.notStartedTasks, color: .gray)
                                statusLegend("Overdue", count: stats.overdueTasks, color: .red)
                            }
                        }
                        .padding(4)
                    }

                    // Milestones
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Upcoming Milestones")
                                .font(.headline)

                            if stats.upcomingMilestones.isEmpty {
                                Text("No upcoming milestones")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(stats.upcomingMilestones, id: \.uniqueID) { task in
                                    HStack {
                                        Image(systemName: "diamond.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text(task.displayName)
                                            .lineLimit(1)
                                        Spacer()
                                        if let date = task.startDate {
                                            Text(date, style: .date)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        milestoneBadge(for: task)
                                    }
                                    .font(.caption)

                                    if task.uniqueID != stats.upcomingMilestones.last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                // Third Row
                HStack(alignment: .top, spacing: 16) {
                    // Resource Summary
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resources")
                                .font(.headline)

                            let workResources = project.resources.filter { $0.type == "work" || $0.type == nil }
                            let materialResources = project.resources.filter { $0.type == "material" }

                            HStack(spacing: 24) {
                                VStack {
                                    Text("\(project.resources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("Total")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(workResources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.blue)
                                    Text("Work")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(materialResources.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.orange)
                                    Text("Material")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                VStack {
                                    Text("\(project.assignments.count)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.green)
                                    Text("Assignments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Schedule Health
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Schedule")
                                .font(.headline)

                            if let start = project.properties.startDate {
                                infoRow("Project Start", value: DateFormatting.mediumDateTime(start))
                            }
                            if let finish = project.properties.finishDate {
                                infoRow("Project Finish", value: DateFormatting.mediumDateTime(finish))
                            }
                            infoRow("Duration", value: stats.projectDurationText)
                            infoRow("Days Remaining", value: stats.daysRemainingText)
                            if stats.projectDurationDays > 0 {
                                ProgressView(value: Double(stats.daysElapsed), total: Double(stats.projectDurationDays))
                                    .tint(stats.daysRemaining < 0 ? .red : .blue)
                            }
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if stats.hasBaselineData {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Baseline Analysis")
                                    .font(.headline)
                                Spacer()
                                baselinePill("\(stats.baselineTrackedTasks) tracked", color: .blue)
                                baselinePill("\(stats.baselineSlippedTasks) slipped", color: stats.baselineSlippedTasks > 0 ? .red : .green)
                                baselinePill("\(stats.baselineOnPlanTasks) on plan", color: .green)
                            }

                            HStack(alignment: .top, spacing: 24) {
                                baselineStat("Ahead", "\(stats.baselineAheadTasks)", color: .blue)
                                baselineStat("On Baseline", "\(stats.baselineOnPlanTasks)", color: .green)
                                baselineStat("Late vs Baseline", "\(stats.baselineSlippedTasks)", color: .red)
                                baselineStat("Milestone Slips", "\(stats.baselineSlippedMilestones)", color: stats.baselineSlippedMilestones > 0 ? .orange : .green)
                            }

                            Divider()

                            infoRow("Average Finish Variance", value: stats.averageFinishVarianceText)
                            infoRow("Worst Finish Variance", value: stats.worstFinishVarianceText)
                            infoRow("Largest Slip Task", value: stats.worstFinishVarianceTaskName)
                        }
                        .padding(4)
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } // end dashboardContent

    private func statusLegend(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").fontWeight(.medium)
            Text(label)
        }
        .font(.caption)
    }

    private func baselinePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func baselineStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func milestoneBadge(for task: ProjectTask) -> some View {
        let pct = task.percentComplete ?? 0
        let isOverdue: Bool = {
            guard let date = task.startDate, pct < 100 else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        }()

        if pct >= 100 {
            Text("Done")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if isOverdue {
            Text("Overdue")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        } else {
            Text("Pending")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.caption)
    }

    private func exportExecutiveSummary(stats: ProjectStats) {
        let validationIssues = ProjectValidator.validate(project: project)
        let lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") Executive Summary",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Headline Metrics",
            "- Average task progress: \(stats.averageProgressPercent)%",
            "- Completed-task ratio: \(stats.completedPercent)%",
            "- Total work tasks: \(stats.totalWorkTasks)",
            "- Completed tasks: \(stats.completedTasks)",
            "- In progress tasks: \(stats.inProgressTasks)",
            "- Overdue tasks: \(stats.overdueTasks)",
            "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
            "- Days remaining: \(stats.daysRemainingText)",
            "- Total cost: \(stats.totalCostFormatted)",
            "",
            "## Validation Snapshot",
            "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
            "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
            "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
            "",
            "## Upcoming Milestones",
        ] + milestoneSummaryLines(stats.upcomingMilestones)

        let markdown = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Executive Summary \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportReviewPack() {
        guard let stats else { return }
        let validationIssues = ProjectValidator.validate(project: project)
        let diagnostics = ProjectDiagnostics.analyze(project: project)
        let resourceIssues = ResourceDiagnostics.analyze(project: project)
        let milestones = project.tasks.filter { $0.isDisplayMilestone }.prefix(10)
        let notedTasks = reviewNotes.compactMap { uniqueID, note -> (ProjectTask, String)? in
            guard let task = project.tasksByID[uniqueID] else { return nil }
            return (task, note)
        }
        .sorted { $0.0.displayName < $1.0.displayName }

        let lines: [String] =
            [
                "# \(project.properties.projectTitle ?? "Project") Review Pack",
                "",
                "Generated: \(ISO8601DateFormatter().string(from: Date()))",
                "",
                "## Executive Summary",
                "- Average task progress: \(stats.averageProgressPercent)%",
                "- Completed-task ratio: \(stats.completedPercent)%",
                "- Days remaining: \(stats.daysRemainingText)",
                "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
                "- Baseline tracked tasks: \(stats.baselineTrackedTasks)",
                "- Baseline slipped tasks: \(stats.baselineSlippedTasks)",
                "",
                "## Validation",
                "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
                "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
                "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
            ]
            + validationIssues.prefix(10).map { "- [\($0.severity.label)] \($0.taskName ?? "Project"): \($0.message)" }
            + [
                "",
                "## Diagnostics",
                "- Total findings: \(diagnostics.count)",
            ]
            + diagnostics.prefix(10).map { "- [\($0.category.label)] \($0.taskName ?? "Project"): \($0.message)" }
            + [
                "",
                "## Resource Risks",
                "- Total findings: \(resourceIssues.count)",
            ]
            + resourceIssues.prefix(10).map { "- [\($0.severity.label)] \($0.resourceName): \($0.message)" }
            + [
                "",
                "## Milestone Outlook",
            ]
            + milestones.map { milestone in
                let variance = milestone.finishVarianceDays ?? milestone.startVarianceDays
                let varianceText = variance.map { "\($0 > 0 ? "+" : "")\($0)d vs baseline" } ?? "No baseline"
                return "- \(milestone.displayName): \(DateFormatting.shortDate(milestone.start)) · \(varianceText)"
            }
            + [
                "",
                "## Review Notes",
            ]
            + (notedTasks.isEmpty ? ["- No local review notes"] : notedTasks.map { "- \($0.0.displayName): \($0.1.replacingOccurrences(of: "\n", with: " "))" })

        let markdown = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Review Pack \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var reviewNotes: [Int: String] {
        (try? JSONDecoder().decode([Int: String].self, from: taskReviewNotesData)) ?? [:]
    }

    private func milestoneSummaryLines(_ milestones: [ProjectTask]) -> [String] {
        guard !milestones.isEmpty else { return ["- No upcoming milestones"] }
        return milestones.map { milestone in
            let dateText = milestone.startDate.map { _ in DateFormatting.shortDate(milestone.start) } ?? "No date"
            let status: String
            let pct = milestone.percentComplete ?? 0
            if pct >= 100 {
                status = "Done"
            } else if let date = milestone.startDate, date < Calendar.current.startOfDay(for: Date()) {
                status = "Overdue"
            } else {
                status = "Pending"
            }
            return "- \(milestone.displayName) — \(dateText) — \(status)"
        }
    }
}

struct ExecutiveModeView: View {
    let project: ProjectModel

    @State private var stats: ProjectStats?

    var body: some View {
        Group {
            if let stats {
                executiveContent(stats: stats)
            } else {
                ProgressView("Loading executive view...")
            }
        }
        .task {
            stats = ProjectStats(project: project)
        }
    }

    private func executiveContent(stats: ProjectStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(project.properties.projectTitle ?? "Project")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(executiveHeadline(stats))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            executivePill("Progress \(stats.averageProgressPercent)%", color: stats.averageProgressPercent >= 75 ? .green : .blue)
                            executivePill("Done \(stats.completedPercent)%", color: stats.completedPercent >= 75 ? .green : .blue)
                            executivePill(stats.daysRemainingText, color: stats.daysRemaining < 0 ? .red : .orange)
                            executivePill("\(stats.criticalIncompleteTasks) critical incomplete", color: stats.criticalIncompleteTasks > 0 ? .red : .green)
                        }
                    }

                    Spacer()

                    Button {
                        exportExecutiveSummary(stats: stats)
                    } label: {
                        Label("Export Summary", systemImage: "doc.text")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18),
                    GridItem(.flexible(), spacing: 18)
                ], spacing: 18) {
                    executiveMetricCard(
                        title: "Average Task Progress",
                        value: "\(stats.averageProgressPercent)%",
                        detail: "\(stats.completedPercent)% of work tasks are fully completed",
                        color: stats.averageProgressPercent >= 75 ? .green : .blue
                    )
                    executiveMetricCard(
                        title: "Schedule Position",
                        value: stats.daysRemainingText,
                        detail: "\(stats.overdueTasks) overdue tasks, \(stats.onTrackTasks) on track",
                        color: stats.daysRemaining < 0 ? .red : .orange
                    )
                    executiveMetricCard(
                        title: "Cost Outlook",
                        value: stats.totalCostFormatted,
                        detail: stats.evmMetrics.bac > 0 ? "CPI \(String(format: "%.2f", stats.evmMetrics.cpi)) · SPI \(String(format: "%.2f", stats.evmMetrics.spi))" : "EVM not available",
                        color: .blue
                    )
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Executive Summary")
                        .font(.headline)
                        Text(executiveNarrative(stats))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                }

                HStack(alignment: .top, spacing: 20) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Top Risks")
                                .font(.headline)
                            ForEach(executiveRiskItems(stats), id: \.title) { item in
                                executiveBullet(title: item.title, value: item.value)
                                if item.title != executiveRiskItems(stats).last?.title {
                                    Divider()
                                }
                            }
                        }
                        .padding(8)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Major Milestones")
                                .font(.headline)
                            if stats.upcomingMilestones.isEmpty {
                                Text("No upcoming milestones")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(stats.upcomingMilestones.prefix(4), id: \.uniqueID) { milestone in
                                    HStack(alignment: .top) {
                                        Image(systemName: "diamond.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption2)
                                            .padding(.top, 4)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(milestone.displayName)
                                                .fontWeight(.medium)
                                            Text(milestone.startDate.map { DateFormatting.mediumDateTime($0) } ?? "No date")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        milestoneBadge(for: milestone)
                                    }
                                    if milestone.uniqueID != stats.upcomingMilestones.prefix(4).last?.uniqueID {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.06), Color.orange.opacity(0.04), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var validationSummary: String {
        let issues = ProjectValidator.validate(project: project)
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        if errors == 0 && warnings == 0 { return "No major validation problems detected." }
        return "\(errors) errors and \(warnings) warnings need review."
    }

    private var diagnosticsSummary: String {
        let signals = ProjectDiagnostics.analyze(project: project)
        if signals.isEmpty { return "No major dependency or constraint hotspots detected." }
        return "\(signals.count) dependency and constraint signals flagged."
    }

    private var resourceRiskSummary: String {
        let risks = ResourceDiagnostics.analyze(project: project)
        if risks.isEmpty { return "No resource over-allocation hotspots detected." }
        return "\(risks.count) resource allocation risks identified."
    }

    private func executiveHeadline(_ stats: ProjectStats) -> String {
        if stats.daysRemaining < 0 {
            return "Project is currently running overdue and needs executive attention."
        }
        if stats.criticalIncompleteTasks > 0 {
            return "Delivery is active with critical-path work still open."
        }
        return "Project is progressing without major critical-path alarms."
    }

    private func executiveNarrative(_ stats: ProjectStats) -> String {
        let schedulePhrase = stats.daysRemaining < 0 ? "The schedule is beyond its target finish by \(-stats.daysRemaining) days." : "The schedule currently shows \(stats.daysRemainingText.lowercased())."
        let progressPhrase = "Average task progress is \(stats.averageProgressPercent)% and \(stats.completedPercent)% of work tasks are fully completed."
        let riskPhrase = stats.criticalIncompleteTasks > 0 ? "\(stats.criticalIncompleteTasks) critical tasks remain open and represent the main delivery risk." : "There are no incomplete critical tasks currently flagged."
        return "\(schedulePhrase) \(progressPhrase) \(riskPhrase)"
    }

    private func executiveMetricCard(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func executivePill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func executiveBullet(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func executiveStatLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func executiveRiskItems(_ stats: ProjectStats) -> [(title: String, value: String)] {
        [
            ("Schedule", stats.daysRemaining < 0 ? "Project is overdue by \(-stats.daysRemaining) days." : "Project timeline shows \(stats.daysRemainingText.lowercased())."),
            ("Quality of Data", validationSummary),
            ("Dependencies", diagnosticsSummary),
            ("Resources", resourceRiskSummary)
        ]
    }

    @ViewBuilder
    private func milestoneBadge(for task: ProjectTask) -> some View {
        let pct = task.percentComplete ?? 0
        let isOverdue: Bool = {
            guard let date = task.startDate, pct < 100 else { return false }
            return date < Calendar.current.startOfDay(for: Date())
        }()

        if pct >= 100 {
            Text("Done")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.green.opacity(0.15))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        } else if isOverdue {
            Text("Overdue")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        } else {
            Text("Pending")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func exportExecutiveSummary(stats: ProjectStats) {
        let validationIssues = ProjectValidator.validate(project: project)
        let lines: [String] = [
            "# \(project.properties.projectTitle ?? "Project") Executive Summary",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "## Headline Metrics",
            "- Average task progress: \(stats.averageProgressPercent)%",
            "- Completed-task ratio: \(stats.completedPercent)%",
            "- Total work tasks: \(stats.totalWorkTasks)",
            "- Completed tasks: \(stats.completedTasks)",
            "- In progress tasks: \(stats.inProgressTasks)",
            "- Overdue tasks: \(stats.overdueTasks)",
            "- Critical incomplete tasks: \(stats.criticalIncompleteTasks)",
            "- Days remaining: \(stats.daysRemainingText)",
            "- Total cost: \(stats.totalCostFormatted)",
            "",
            "## Validation Snapshot",
            "- Errors: \(validationIssues.filter { $0.severity == .error }.count)",
            "- Warnings: \(validationIssues.filter { $0.severity == .warning }.count)",
            "- Info: \(validationIssues.filter { $0.severity == .info }.count)",
            "",
            "## Upcoming Milestones",
        ] + milestoneSummaryLines(stats.upcomingMilestones)

        let markdown = lines.joined(separator: "\n")
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Executive Summary \(PDFExporter.fileNameTimestamp).md"
        panel.allowedContentTypes = [UTType.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func milestoneSummaryLines(_ milestones: [ProjectTask]) -> [String] {
        guard !milestones.isEmpty else { return ["- No upcoming milestones"] }
        return milestones.map { milestone in
            let dateText = milestone.startDate.map { _ in DateFormatting.shortDate(milestone.start) } ?? "No date"
            let status: String
            let pct = milestone.percentComplete ?? 0
            if pct >= 100 {
                status = "Done"
            } else if let date = milestone.startDate, date < Calendar.current.startOfDay(for: Date()) {
                status = "Overdue"
            } else {
                status = "Pending"
            }
            return "- \(milestone.displayName) — \(dateText) — \(status)"
        }
    }
}

// MARK: - KPI Card

struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var progress: Double? = nil

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                if let progress = progress {
                    ProgressView(value: progress)
                        .tint(color)
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(2)
        }
    }
}

// MARK: - Status Bar

struct StatusSegment {
    let label: String
    let count: Int
    let color: Color
}

struct StatusBar: View {
    let segments: [StatusSegment]
    let total: Int

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(segments.indices, id: \.self) { i in
                    let seg = segments[i]
                    if seg.count > 0 {
                        let width = max(4, geometry.size.width * CGFloat(seg.count) / CGFloat(max(1, total)))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(seg.color)
                            .frame(width: width)
                            .help("\(seg.label): \(seg.count)")
                    }
                }
            }
        }
        .frame(height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Project Stats

struct ProjectStats {
    let totalWorkTasks: Int
    let completedTasks: Int
    let inProgressTasks: Int
    let notStartedTasks: Int
    let overdueTasks: Int
    let onTrackTasks: Int
    let behindTasks: Int
    let criticalTasks: Int
    let criticalIncompleteTasks: Int
    let overallPercent: Int
    let totalCost: Double
    let upcomingMilestones: [ProjectTask]
    let projectDurationDays: Int
    let daysElapsed: Int
    let daysRemaining: Int
    let evmMetrics: EVMMetrics
    let baselineTrackedTasks: Int
    let baselineOnPlanTasks: Int
    let baselineAheadTasks: Int
    let baselineSlippedTasks: Int
    let baselineSlippedMilestones: Int
    let averageFinishVarianceDays: Int?
    let worstFinishVarianceTaskName: String
    let worstFinishVarianceDays: Int?

    var averageProgressPercent: Int { overallPercent }

    var completedPercent: Int {
        guard totalWorkTasks > 0 else { return 0 }
        return Int((Double(completedTasks) / Double(totalWorkTasks) * 100.0).rounded())
    }

    var hasBaselineData: Bool {
        baselineTrackedTasks > 0
    }

    var averageFinishVarianceText: String {
        guard let averageFinishVarianceDays else { return "N/A" }
        if averageFinishVarianceDays == 0 { return "On baseline" }
        return "\(averageFinishVarianceDays > 0 ? "+" : "")\(averageFinishVarianceDays) days"
    }

    var worstFinishVarianceText: String {
        guard let worstFinishVarianceDays else { return "N/A" }
        if worstFinishVarianceDays == 0 { return "On baseline" }
        return "\(worstFinishVarianceDays > 0 ? "+" : "")\(worstFinishVarianceDays) days"
    }

    var totalCostFormatted: String {
        if totalCost == 0 { return "N/A" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: totalCost)) ?? "$\(Int(totalCost))"
    }

    var projectDurationText: String {
        if projectDurationDays <= 0 { return "N/A" }
        return "\(projectDurationDays) days"
    }

    var daysRemainingText: String {
        if daysRemaining < 0 {
            return "\(-daysRemaining) days overdue"
        } else if daysRemaining == 0 {
            return "Due today"
        }
        return "\(daysRemaining) days"
    }

    init(project: ProjectModel) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let workTasks = project.tasks.filter { $0.summary != true && $0.milestone != true }

        self.totalWorkTasks = workTasks.count

        self.completedTasks = workTasks.filter { ($0.percentComplete ?? 0) >= 100 }.count

        self.inProgressTasks = workTasks.filter {
            let pct = $0.percentComplete ?? 0
            return pct > 0 && pct < 100
        }.count

        let overdue = workTasks.filter {
            let pct = $0.percentComplete ?? 0
            guard pct < 100, let finish = $0.finishDate else { return false }
            return finish < today
        }
        self.overdueTasks = overdue.count

        let overdueIDs = Set(overdue.map { $0.uniqueID })
        self.notStartedTasks = workTasks.filter {
            ($0.percentComplete ?? 0) == 0 && !overdueIDs.contains($0.uniqueID)
        }.count

        self.behindTasks = overdueTasks
        self.onTrackTasks = totalWorkTasks - overdueTasks

        self.criticalTasks = project.tasks.filter { $0.critical == true }.count
        self.criticalIncompleteTasks = project.tasks.filter { $0.critical == true && ($0.percentComplete ?? 0) < 100 }.count

        let totalPct = workTasks.reduce(0.0) { $0 + ($1.percentComplete ?? 0) }
        self.overallPercent = workTasks.isEmpty ? 0 : Int(totalPct / Double(workTasks.count))

        self.totalCost = project.tasks.compactMap { $0.cost }.reduce(0, +)

        let baselineTasks = project.tasks.filter { $0.summary != true && $0.hasBaseline }
        self.baselineTrackedTasks = baselineTasks.count
        self.baselineOnPlanTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) == 0 }.count
        self.baselineAheadTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) < 0 }.count
        self.baselineSlippedTasks = baselineTasks.filter { ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) > 0 }.count
        self.baselineSlippedMilestones = project.tasks.filter { $0.isDisplayMilestone && ($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) > 0 }.count

        let finishVariances = baselineTasks.compactMap { $0.finishVarianceDays ?? $0.startVarianceDays }
        if finishVariances.isEmpty {
            self.averageFinishVarianceDays = nil
        } else {
            let average = Double(finishVariances.reduce(0, +)) / Double(finishVariances.count)
            self.averageFinishVarianceDays = Int(average.rounded())
        }

        if let worstTask = baselineTasks.max(by: { abs($0.finishVarianceDays ?? $0.startVarianceDays ?? 0) < abs($1.finishVarianceDays ?? $1.startVarianceDays ?? 0) }) {
            self.worstFinishVarianceTaskName = worstTask.displayName
            self.worstFinishVarianceDays = worstTask.finishVarianceDays ?? worstTask.startVarianceDays
        } else {
            self.worstFinishVarianceTaskName = "N/A"
            self.worstFinishVarianceDays = nil
        }

        // Upcoming milestones: incomplete milestones with dates in the next 30 days
        self.upcomingMilestones = project.tasks
            .filter { $0.isDisplayMilestone }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
            .prefix(8)
            .map { $0 }

        // Project duration
        let allStarts = project.tasks.compactMap { $0.startDate }
        let allFinishes = project.tasks.compactMap { $0.finishDate }
        let projectStart = allStarts.min()
        let projectFinish = allFinishes.max()

        if let start = projectStart, let finish = projectFinish {
            self.projectDurationDays = max(1, calendar.dateComponents([.day], from: start, to: finish).day ?? 0)
            self.daysElapsed = max(0, calendar.dateComponents([.day], from: start, to: today).day ?? 0)
            self.daysRemaining = calendar.dateComponents([.day], from: today, to: finish).day ?? 0
        } else {
            self.projectDurationDays = 0
            self.daysElapsed = 0
            self.daysRemaining = 0
        }

        // EVM
        let statusDate: Date = {
            if let sd = project.properties.statusDate {
                return DateFormatting.parseMPXJDate(sd) ?? today
            }
            return today
        }()
        self.evmMetrics = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: statusDate)
    }
}
