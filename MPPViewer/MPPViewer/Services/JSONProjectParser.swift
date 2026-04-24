import Foundation

enum ParserError: LocalizedError {
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed(let msg):
            return "Failed to parse project JSON: \(msg)"
        }
    }
}

final class JSONProjectParser {

    static func parseDetached(jsonData: Data) async throws -> ProjectModel {
        try await Task.detached(priority: .userInitiated) {
            try JSONProjectParser().parse(jsonData: jsonData)
        }.value
    }

    func parse(jsonData: Data) throws -> ProjectModel {
        let decoder = JSONDecoder()

        let output: MPXJOutput
        do {
            output = try decoder.decode(MPXJOutput.self, from: jsonData)
        } catch {
            throw ParserError.decodingFailed(error.localizedDescription)
        }

        let tasks = output.tasks ?? []
        let resources = output.resources ?? []
        let assignments = output.assignments ?? []
        let calendars = output.calendars ?? []
        let properties = output.propertyValues ?? ProjectProperties(
            projectTitle: nil, author: nil, lastAuthor: nil, manager: nil,
            company: nil, startDate: nil, finishDate: nil, statusDate: nil,
            creationDate: nil, lastSaved: nil, currencySymbol: nil,
            currencyCode: nil, comments: nil, subject: nil, category: nil,
            keywords: nil, defaultCalendarUniqueId: nil,
            shortApplicationName: nil, fullApplicationName: nil
        )

        // Build task hierarchy
        let (rootTasks, tasksByID) = buildTaskHierarchy(tasks: tasks)

        return ProjectModel(
            properties: properties,
            tasks: tasks,
            resources: resources,
            assignments: assignments,
            calendars: calendars,
            rootTasks: rootTasks,
            tasksByID: tasksByID
        )
    }

    private func buildTaskHierarchy(tasks: [ProjectTask]) -> ([ProjectTask], [Int: ProjectTask]) {
        var tasksByID: [Int: ProjectTask] = [:]
        for task in tasks {
            tasksByID[task.uniqueID] = task
            task.children = []
        }

        var rootTasks: [ProjectTask] = []

        for task in tasks {
            if let parentID = task.parentTaskUniqueID, let parent = tasksByID[parentID] {
                parent.children.append(task)
            } else {
                rootTasks.append(task)
            }
        }

        return (rootTasks, tasksByID)
    }
}
