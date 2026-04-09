import Foundation

struct ScenarioTaskImpact: Identifiable {
    let id: Int
    let taskName: String
    let projectedStart: Date?
    let projectedFinish: Date?
    let startDeltaDays: Int?
    let finishDeltaDays: Int?
    let isMilestone: Bool
    let isCritical: Bool
}

struct ScenarioSimulationResult {
    let sourceTaskName: String
    let slipDays: Int
    let projectedSourceStart: Date?
    let projectedSourceFinish: Date?
    let impactedTasks: [ScenarioTaskImpact]
    let projectFinishDeltaDays: Int?
    let milestoneImpactCount: Int
    let criticalImpactCount: Int
}

enum ScenarioAnalysis {

    static func simulateSlip(
        for task: ProjectTask,
        slipDays: Int,
        allTasks: [Int: ProjectTask]
    ) -> ScenarioSimulationResult? {
        guard slipDays > 0 else { return nil }
        guard let taskStart = task.startDate, let taskFinish = task.finishDate else { return nil }

        let slipSeconds = TimeInterval(slipDays * 86_400)
        var projectedDates: [Int: (start: Date?, finish: Date?, shiftSeconds: TimeInterval)] = [
            task.uniqueID: (taskStart.addingTimeInterval(slipSeconds), taskFinish.addingTimeInterval(slipSeconds), slipSeconds)
        ]
        var queue: [Int] = [task.uniqueID]

        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            guard let currentTask = allTasks[currentID] else { continue }
            guard let currentProjection = projectedDates[currentID] else { continue }

            for relation in currentTask.successors ?? [] {
                guard let successor = allTasks[relation.targetTaskUniqueID] else { continue }
                guard let successorStart = successor.startDate, let successorFinish = successor.finishDate else { continue }

                let lagSeconds = TimeInterval(relation.lag ?? 0)
                let type = relation.type ?? "FS"
                let candidateShiftSeconds: TimeInterval?

                switch type {
                case "SS":
                    guard let currentStart = currentProjection.start else { continue }
                    let requiredStart = currentStart.addingTimeInterval(lagSeconds)
                    let delta = requiredStart.timeIntervalSince(successorStart)
                    candidateShiftSeconds = delta > 0 ? delta : nil
                case "FF":
                    guard let currentFinish = currentProjection.finish else { continue }
                    let requiredFinish = currentFinish.addingTimeInterval(lagSeconds)
                    let delta = requiredFinish.timeIntervalSince(successorFinish)
                    candidateShiftSeconds = delta > 0 ? delta : nil
                case "SF":
                    guard let currentStart = currentProjection.start else { continue }
                    let requiredFinish = currentStart.addingTimeInterval(lagSeconds)
                    let delta = requiredFinish.timeIntervalSince(successorFinish)
                    candidateShiftSeconds = delta > 0 ? delta : nil
                default:
                    guard let currentFinish = currentProjection.finish else { continue }
                    let requiredStart = currentFinish.addingTimeInterval(lagSeconds)
                    let delta = requiredStart.timeIntervalSince(successorStart)
                    candidateShiftSeconds = delta > 0 ? delta : nil
                }

                guard let candidateShiftSeconds else { continue }
                let existingShiftSeconds = projectedDates[successor.uniqueID]?.shiftSeconds ?? 0
                guard candidateShiftSeconds > existingShiftSeconds else { continue }

                projectedDates[successor.uniqueID] = (
                    start: successorStart.addingTimeInterval(candidateShiftSeconds),
                    finish: successorFinish.addingTimeInterval(candidateShiftSeconds),
                    shiftSeconds: candidateShiftSeconds
                )
                queue.append(successor.uniqueID)
            }
        }

        let impactedTasks = projectedDates
            .filter { $0.key != task.uniqueID }
            .compactMap { uniqueID, projection -> ScenarioTaskImpact? in
                guard let impactedTask = allTasks[uniqueID] else { return nil }
                let startDelta = dayDelta(from: impactedTask.startDate, to: projection.start)
                let finishDelta = dayDelta(from: impactedTask.finishDate, to: projection.finish)
                return ScenarioTaskImpact(
                    id: uniqueID,
                    taskName: impactedTask.displayName,
                    projectedStart: projection.start,
                    projectedFinish: projection.finish,
                    startDeltaDays: startDelta,
                    finishDeltaDays: finishDelta,
                    isMilestone: impactedTask.isDisplayMilestone,
                    isCritical: impactedTask.critical == true
                )
            }
            .sorted { lhs, rhs in
                let lhsDelta = lhs.finishDeltaDays ?? lhs.startDeltaDays ?? 0
                let rhsDelta = rhs.finishDeltaDays ?? rhs.startDeltaDays ?? 0
                if lhsDelta == rhsDelta {
                    return lhs.taskName < rhs.taskName
                }
                return lhsDelta > rhsDelta
            }

        let originalProjectFinish = allTasks.values.compactMap(\.finishDate).max()
        let projectedProjectFinish = allTasks.values.compactMap { task -> Date? in
            projectedDates[task.uniqueID]?.finish ?? task.finishDate
        }.max()

        return ScenarioSimulationResult(
            sourceTaskName: task.displayName,
            slipDays: slipDays,
            projectedSourceStart: projectedDates[task.uniqueID]?.start,
            projectedSourceFinish: projectedDates[task.uniqueID]?.finish,
            impactedTasks: impactedTasks,
            projectFinishDeltaDays: dayDelta(from: originalProjectFinish, to: projectedProjectFinish),
            milestoneImpactCount: impactedTasks.filter(\.isMilestone).count,
            criticalImpactCount: impactedTasks.filter(\.isCritical).count
        )
    }

    private static func dayDelta(from original: Date?, to projected: Date?) -> Int? {
        guard let original, let projected else { return nil }
        let delta = Calendar.current.dateComponents([.day], from: original, to: projected).day
        guard let delta, delta != 0 else { return nil }
        return delta
    }
}
