import SwiftUI

struct ResourceSheetView: View {
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]

    private func assignmentCount(for resource: ProjectResource) -> Int {
        guard let uid = resource.uniqueID else { return 0 }
        return assignments.filter { $0.resourceUniqueID == uid }.count
    }

    private func taskCount(for resource: ProjectResource) -> Int {
        guard let uid = resource.uniqueID else { return 0 }
        return Set(assignments.filter { $0.resourceUniqueID == uid }.compactMap { $0.taskUniqueID }).count
    }

    var body: some View {
        if resources.isEmpty {
            ContentUnavailableView("No Resources", systemImage: "person.2", description: Text("This project has no resources defined."))
        } else {
            Table(resources) {
                TableColumn("ID") { resource in
                    Text(resource.id.map(String.init) ?? "")
                        .monospacedDigit()
                }
                .width(min: 30, ideal: 50, max: 60)

                TableColumn("Name") { resource in
                    Text(resource.name ?? "(Unnamed)")
                }
                .width(min: 150, ideal: 250)

                TableColumn("Type") { resource in
                    Text(resource.type ?? "")
                }
                .width(min: 50, ideal: 80, max: 100)

                TableColumn("Group") { resource in
                    Text(resource.group ?? "")
                }
                .width(min: 60, ideal: 100, max: 150)

                TableColumn("Max Units") { resource in
                    if let units = resource.maxUnits {
                        Text("\(Int(units))%")
                            .monospacedDigit()
                    }
                }
                .width(min: 60, ideal: 80, max: 100)

                TableColumn("Std Rate") { resource in
                    if let rate = resource.standardRate {
                        Text(String(format: "%.2f", rate))
                            .monospacedDigit()
                    }
                }
                .width(min: 70, ideal: 100, max: 130)

                TableColumn("Email") { resource in
                    Text(resource.emailAddress ?? "")
                        .font(.caption)
                }
                .width(min: 100, ideal: 180)

                TableColumn("Assignments") { resource in
                    let count = assignmentCount(for: resource)
                    if count > 0 {
                        Text("\(count)")
                            .monospacedDigit()
                    }
                }
                .width(min: 60, ideal: 80, max: 100)
            }
        }
    }
}
