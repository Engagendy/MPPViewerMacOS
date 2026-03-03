import SwiftUI

struct ProjectSummaryView: View {
    let project: ProjectModel

    private var props: ProjectProperties { project.properties }

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
                        summaryRow("Total Tasks", value: "\(project.tasks.count)")
                        summaryRow("Summary Tasks", value: "\(project.tasks.filter { $0.summary == true }.count)")
                        summaryRow("Milestones", value: "\(project.tasks.filter { $0.milestone == true }.count)")
                        summaryRow("Resources", value: "\(project.resources.count)")
                        summaryRow("Assignments", value: "\(project.assignments.count)")
                        summaryRow("Calendars", value: "\(project.calendars.count)")

                        let criticalCount = project.tasks.filter { $0.critical == true }.count
                        summaryRow("Critical Tasks", value: "\(criticalCount)")

                        let completedCount = project.tasks.filter { ($0.percentComplete ?? 0) >= 100 }.count
                        summaryRow("Completed Tasks", value: "\(completedCount)")
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
