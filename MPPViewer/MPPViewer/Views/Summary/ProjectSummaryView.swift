import SwiftUI

struct ProjectSummaryView: View {
    let project: ProjectModel
    private let stats: ProjectSummaryStats

    private var props: ProjectProperties { project.properties }

    init(project: ProjectModel) {
        self.project = project
        self.stats = ProjectSummaryStats(project: project)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Project Info
                GroupBox("Project Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        summaryRow("Title", value: props.projectTitle)
                        summaryRow("Subject", value: props.subject)
                        summaryRow("Author", value: props.author)
                        summaryRow("Manager", value: props.manager)
                        summaryRow("Company", value: props.company)
                        summaryRow("Category", value: props.category)
                        summaryRow("Keywords", value: props.keywords)
                        summaryRow("Application", value: props.fullApplicationName)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // Schedule
                GroupBox("Schedule") {
                    VStack(alignment: .leading, spacing: 8) {
                        summaryRow("Start Date", dateString: props.startDate)
                        summaryRow("Finish Date", dateString: props.finishDate)
                        summaryRow("Status Date", dateString: props.statusDate)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // Statistics
                GroupBox("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        summaryRow("Total Tasks", value: "\(stats.totalTasks)")
                        summaryRow("Summary Tasks", value: "\(stats.summaryTasks)")
                        summaryRow("Milestones", value: "\(stats.milestones)")
                        summaryRow("Resources", value: "\(stats.resources)")
                        summaryRow("Assignments", value: "\(stats.assignments)")
                        summaryRow("Calendars", value: "\(stats.calendars)")
                        summaryRow("Critical Tasks", value: "\(stats.criticalTasks)")
                        summaryRow("Completed Tasks", value: "\(stats.completedTasks)")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // File Info
                GroupBox("File Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        summaryRow("Created", dateString: props.creationDate)
                        summaryRow("Last Saved", dateString: props.lastSaved)
                        summaryRow("Currency", value: [props.currencySymbol, props.currencyCode].compactMap { $0 }.joined(separator: " "))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                // Comments
                if let comments = props.comments, !comments.isEmpty {
                    GroupBox("Comments") {
                        Text(comments)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func summaryRow(_ label: String, value: String?) -> some View {
        if let value = value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 140, alignment: .trailing)
                Text(value)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ label: String, dateString: String?) -> some View {
        let formatted = DateFormatting.mediumDateTime(dateString)
        if !formatted.isEmpty {
            summaryRow(label, value: formatted)
        }
    }
}

private struct ProjectSummaryStats {
    let totalTasks: Int
    let summaryTasks: Int
    let milestones: Int
    let resources: Int
    let assignments: Int
    let calendars: Int
    let criticalTasks: Int
    let completedTasks: Int

    init(project: ProjectModel) {
        totalTasks = project.tasks.count
        summaryTasks = project.tasks.reduce(0) { $0 + ($1.summary == true ? 1 : 0) }
        milestones = project.tasks.reduce(0) { $0 + ($1.milestone == true ? 1 : 0) }
        resources = project.resources.count
        assignments = project.assignments.count
        calendars = project.calendars.count
        criticalTasks = project.tasks.reduce(0) { $0 + ($1.critical == true ? 1 : 0) }
        completedTasks = project.tasks.reduce(0) { $0 + ((($1.percentComplete ?? 0) >= 100) ? 1 : 0) }
    }
}
