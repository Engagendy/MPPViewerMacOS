import SwiftUI
import SwiftData
import Combine
import AppKit
import UniformTypeIdentifiers

extension Notification.Name {
    static let navigateToItem = Notification.Name("navigateToItem")
}

struct NativePlanAnalysis {
    struct HeaderMetrics {
        let plannedCost: Double
        let bac: Double
        let actualCost: Double
        let cpi: Double
        let spi: Double
        let eac: Double
    }

    let project: ProjectModel
    let evm: EVMMetrics
    let headerMetrics: HeaderMetrics
    let validationIssues: [ProjectValidationIssue]
    let diagnosticItems: [ProjectDiagnosticItem]
    let summaryParentTaskIDs: Set<Int>

    static let placeholder: NativePlanAnalysis = {
        let emptyProject = NativeProjectPlan.empty().asProjectModel()
        return NativePlanAnalysis(
            project: emptyProject,
            evm: .zero,
            headerMetrics: HeaderMetrics(
                plannedCost: 0,
                bac: 0,
                actualCost: 0,
                cpi: 0,
                spi: 0,
                eac: 0
            ),
            validationIssues: [],
            diagnosticItems: [],
            summaryParentTaskIDs: Set<Int>()
        )
    }()

    static func build(from plan: NativeProjectPlan) -> NativePlanAnalysis {
        let project = plan.asProjectModel()
        let evm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate)
        let plannedCost = project.tasks
            .filter { $0.summary != true }
            .compactMap(\.cost)
            .reduce(0, +)
        return NativePlanAnalysis(
            project: project,
            evm: evm,
            headerMetrics: HeaderMetrics(
                plannedCost: plannedCost,
                bac: evm.bac,
                actualCost: evm.ac,
                cpi: evm.cpi,
                spi: evm.spi,
                eac: evm.eac
            ),
            validationIssues: ProjectValidator.validate(project: project, resourceLeaves: plan.resourceLeaves),
            diagnosticItems: ProjectDiagnostics.analyze(project: project),
            summaryParentTaskIDs: plan.summaryParentTaskIDs()
        )
    }

    static func buildPreview(from plan: NativeProjectPlan) -> NativePlanAnalysis {
        let unscheduledResult = PlanScheduleResult(
            tasks: plan.tasks,
            criticalTaskIDs: [],
            totalSlackSecondsByTaskID: [:]
        )
        let project = plan.asProjectModel(scheduleResult: unscheduledResult)
        let evm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate)
        let plannedCost = project.tasks
            .filter { $0.summary != true }
            .compactMap(\.cost)
            .reduce(0, +)
        return NativePlanAnalysis(
            project: project,
            evm: evm,
            headerMetrics: HeaderMetrics(
                plannedCost: plannedCost,
                bac: evm.bac,
                actualCost: evm.ac,
                cpi: evm.cpi,
                spi: evm.spi,
                eac: evm.eac
            ),
            validationIssues: [],
            diagnosticItems: [],
            summaryParentTaskIDs: plan.summaryParentTaskIDs()
        )
    }

    static func build(fromProjection planModel: PortfolioProjectPlan) -> NativePlanAnalysis {
        let nativeTasks = planModel.nativeTasksForUI
        let nativeAssignments = planModel.nativeAssignmentsForUI
        let nativeResources = planModel.nativeResourcesForUI
        let nativeCalendars = planModel.nativeCalendarsForUI
        let nativeSprints = planModel.nativeSprintsForUI
        let nativeStatusSnapshots = planModel.nativeStatusSnapshotsForUI
        let nativeWorkflowColumns = planModel.nativeWorkflowColumnsForUI
        let nativeTypeWorkflowOverrides = planModel.nativeTypeWorkflowOverridesForUI
        let projection = NativeProjectPlan(
            portfolioID: planModel.portfolioID,
            title: planModel.title,
            manager: planModel.manager,
            company: planModel.company,
            statusDate: planModel.statusDate,
            portfolioWorkspace: planModel.portfolioWorkspace,
            portfolioProgram: planModel.portfolioProgram,
            portfolioSponsor: planModel.portfolioSponsor,
            portfolioStage: planModel.portfolioStage,
            portfolioHealth: planModel.portfolioHealth,
            portfolioPriorityBand: planModel.portfolioPriorityBand,
            portfolioApprovalState: planModel.portfolioApprovalState,
            portfolioStrategicAlignment: planModel.portfolioStrategicAlignment,
            portfolioRiskScore: planModel.portfolioRiskScore,
            portfolioObjective: planModel.portfolioObjective,
            portfolioReviewDate: planModel.portfolioReviewDate,
            portfolioReviewCadenceDays: planModel.portfolioReviewCadenceDays,
            portfolioArchiveReason: planModel.portfolioArchiveReason,
            defaultCalendarUniqueID: planModel.defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: planModel.boardColumns,
            workflowColumns: nativeWorkflowColumns,
            typeWorkflowOverrides: nativeTypeWorkflowOverrides,
            sprints: nativeSprints,
            statusSnapshots: nativeStatusSnapshots
        )
        return build(from: projection)
    }

    static func buildAsync(from plan: NativeProjectPlan) async -> NativePlanAnalysis {
        let scheduleResult = await PlanScheduler.schedule(plan)
        return await Task.detached(priority: .userInitiated) {
            let project = plan.asProjectModel(scheduleResult: scheduleResult)
            let evm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: plan.statusDate)
            let plannedCost = project.tasks
                .filter { $0.summary != true }
                .compactMap(\.cost)
                .reduce(0, +)
            return NativePlanAnalysis(
                project: project,
                evm: evm,
                headerMetrics: HeaderMetrics(
                    plannedCost: plannedCost,
                    bac: evm.bac,
                    actualCost: evm.ac,
                    cpi: evm.cpi,
                    spi: evm.spi,
                    eac: evm.eac
                ),
                validationIssues: ProjectValidator.validate(project: project, resourceLeaves: plan.resourceLeaves),
                diagnosticItems: ProjectDiagnostics.analyze(project: project),
                summaryParentTaskIDs: plan.summaryParentTaskIDs()
            )
        }.value
    }

    /// Reads SwiftData model properties, so it must stay on the main actor;
    /// running it on the cooperative pool races main-thread fetches and
    /// crashes inside SwiftData accessors. Only the pure value computation in
    /// `buildAsync(from:)` runs detached.
    @MainActor
    static func buildAsync(fromProjection planModel: PortfolioProjectPlan) async -> NativePlanAnalysis {
        let nativeTasks = planModel.nativeTasksForUI
        let nativeAssignments = planModel.nativeAssignmentsForUI
        let nativeResources = planModel.nativeResourcesForUI
        let nativeCalendars = planModel.nativeCalendarsForUI
        let nativeSprints = planModel.nativeSprintsForUI
        let nativeStatusSnapshots = planModel.nativeStatusSnapshotsForUI
        let nativeWorkflowColumns = planModel.nativeWorkflowColumnsForUI
        let nativeTypeWorkflowOverrides = planModel.nativeTypeWorkflowOverridesForUI
        let projection = NativeProjectPlan(
            portfolioID: planModel.portfolioID,
            title: planModel.title,
            manager: planModel.manager,
            company: planModel.company,
            statusDate: planModel.statusDate,
            portfolioWorkspace: planModel.portfolioWorkspace,
            portfolioProgram: planModel.portfolioProgram,
            portfolioSponsor: planModel.portfolioSponsor,
            portfolioStage: planModel.portfolioStage,
            portfolioHealth: planModel.portfolioHealth,
            portfolioPriorityBand: planModel.portfolioPriorityBand,
            portfolioApprovalState: planModel.portfolioApprovalState,
            portfolioStrategicAlignment: planModel.portfolioStrategicAlignment,
            portfolioRiskScore: planModel.portfolioRiskScore,
            portfolioObjective: planModel.portfolioObjective,
            portfolioReviewDate: planModel.portfolioReviewDate,
            portfolioReviewCadenceDays: planModel.portfolioReviewCadenceDays,
            portfolioArchiveReason: planModel.portfolioArchiveReason,
            defaultCalendarUniqueID: planModel.defaultCalendarUniqueID,
            tasks: nativeTasks,
            resources: nativeResources,
            assignments: nativeAssignments,
            calendars: nativeCalendars.isEmpty ? [NativePlanCalendar.standard(id: 1)] : nativeCalendars,
            boardColumns: planModel.boardColumns,
            workflowColumns: nativeWorkflowColumns,
            typeWorkflowOverrides: nativeTypeWorkflowOverrides,
            sprints: nativeSprints,
            statusSnapshots: nativeStatusSnapshots
        )
        return await buildAsync(from: projection)
    }
}

/// Value snapshot of the plan fields the portfolio analytics builders read,
/// captured on the main actor so summaries can be computed off the main
/// thread without touching SwiftData objects. Member names intentionally
/// mirror `PortfolioProjectPlan` / `PortfolioPlanTask` so builder bodies stay
/// unchanged.
struct PortfolioAnalyticsPlanSnapshot: Sendable {
    struct Task: Sendable {
        let uniqueID: UUID
        let legacyID: Int
        let name: String
        let isMilestone: Bool
        let isActive: Bool
        let percentComplete: Double
        let startDate: Date
        let finishDate: Date
        let baselineFinishDate: Date?
        let boardStatus: String
    }

    let portfolioID: UUID
    let title: String
    let portfolioWorkspace: String?
    let portfolioProgram: String?
    let portfolioSponsor: String?
    let portfolioHealth: String?
    let portfolioStage: String?
    let portfolioApprovalState: String?
    let portfolioStrategicAlignment: Int?
    let portfolioRiskScore: Int?
    let portfolioReviewDate: Date?
    let portfolioReviewCadenceDays: Int?
    let portfolioArchiveReason: String?
    let portfolioBudget: Double
    let portfolioActualCost: Double
    let isArchivedValue: Bool
    let tasks: [Task]
}

struct PortfolioAnalyticsDependencySnapshot: Sendable {
    let uniqueID: UUID
    let sourcePlanID: UUID
    let sourcePlanTitle: String
    let sourceTaskUniqueID: UUID
    let sourceTaskName: String
    let targetPlanID: UUID
    let targetPlanTitle: String
    let targetTaskUniqueID: UUID
    let targetTaskName: String
    let relationType: String
    let lagDays: Int
    let note: String
}

extension PortfolioProjectPlan {
    func analyticsSnapshot() -> PortfolioAnalyticsPlanSnapshot {
        PortfolioAnalyticsPlanSnapshot(
            portfolioID: portfolioID,
            title: title,
            portfolioWorkspace: portfolioWorkspace,
            portfolioProgram: portfolioProgram,
            portfolioSponsor: portfolioSponsor,
            portfolioHealth: portfolioHealth,
            portfolioStage: portfolioStage,
            portfolioApprovalState: portfolioApprovalState,
            portfolioStrategicAlignment: portfolioStrategicAlignment,
            portfolioRiskScore: portfolioRiskScore,
            portfolioReviewDate: portfolioReviewDate,
            portfolioReviewCadenceDays: portfolioReviewCadenceDays,
            portfolioArchiveReason: portfolioArchiveReason,
            portfolioBudget: portfolioBudget,
            portfolioActualCost: portfolioActualCost,
            isArchivedValue: isArchivedValue,
            tasks: tasks.map { task in
                PortfolioAnalyticsPlanSnapshot.Task(
                    uniqueID: task.uniqueID,
                    legacyID: task.legacyID,
                    name: task.name,
                    isMilestone: task.isMilestone,
                    isActive: task.isActive,
                    percentComplete: task.percentComplete,
                    startDate: task.startDate,
                    finishDate: task.finishDate,
                    baselineFinishDate: task.baselineFinishDate,
                    boardStatus: task.boardStatus
                )
            }
        )
    }
}

extension PortfolioCrossProjectDependency {
    func analyticsSnapshot() -> PortfolioAnalyticsDependencySnapshot {
        PortfolioAnalyticsDependencySnapshot(
            uniqueID: uniqueID,
            sourcePlanID: sourcePlanID,
            sourcePlanTitle: sourcePlanTitle,
            sourceTaskUniqueID: sourceTaskUniqueID,
            sourceTaskName: sourceTaskName,
            targetPlanID: targetPlanID,
            targetPlanTitle: targetPlanTitle,
            targetTaskUniqueID: targetTaskUniqueID,
            targetTaskName: targetTaskName,
            relationType: relationType,
            lagDays: lagDays,
            note: note
        )
    }
}

struct PortfolioExecutiveSummary {
    struct ProjectInsight: Identifiable, Hashable {
        let planID: UUID
        let title: String
        let workspace: String
        let program: String
        let sponsor: String
        let manualHealth: String
        let riskBand: String
        let score: Int
        let overdueTaskCount: Int
        let activeTaskCount: Int
        let slippedTaskCount: Int
        let slippedMilestoneCount: Int
        let upcomingMilestoneCount: Int
        let maxScheduleSlipDays: Int
        let completionPercent: Double
        let budgetVariance: Double
        let costOverrun: Double
        let costVariancePercent: Double
        let reviewDate: Date?
        let reviewDueSoon: Bool
        let reviewOverdue: Bool
        let nextMilestoneDate: Date?
        let attentionReasons: [String]

        var id: UUID { planID }
    }

    struct MilestoneRollup: Identifiable, Hashable {
        let id: String
        let planID: UUID
        let planTitle: String
        let taskID: Int
        let taskName: String
        let finishDate: Date
        let slipDays: Int
        let category: String
    }

    struct AttentionItem: Identifiable, Hashable {
        let id: String
        let planID: UUID
        let planTitle: String
        let severity: String
        let headline: String
        let detail: String
        let rank: Int
    }

    let projectInsights: [ProjectInsight]
    let rankedProjects: [ProjectInsight]
    let topCostVarianceProjects: [ProjectInsight]
    let topScheduleSlipProjects: [ProjectInsight]
    let attentionFeed: [AttentionItem]
    let upcomingMilestones: [MilestoneRollup]
    let slippedMilestones: [MilestoneRollup]
    let healthyCount: Int
    let watchCount: Int
    let atRiskCount: Int
    let reviewDueCount: Int
    let slippedMilestoneCount: Int
    let upcomingMilestoneCount: Int

    static func build(plans: [PortfolioProjectPlan], now: Date = Date()) -> PortfolioExecutiveSummary {
        build(snapshots: plans.map { $0.analyticsSnapshot() }, now: now)
    }

    static func build(snapshots plans: [PortfolioAnalyticsPlanSnapshot], now: Date = Date()) -> PortfolioExecutiveSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let reviewHorizon = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        let milestoneHorizon = calendar.date(byAdding: .day, value: 30, to: today) ?? today

        let insights = plans.map { plan in
            buildInsight(
                for: plan,
                today: today,
                reviewHorizon: reviewHorizon,
                milestoneHorizon: milestoneHorizon,
                calendar: calendar
            )
        }

        let rankedProjects = insights.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            if lhs.costOverrun != rhs.costOverrun {
                return lhs.costOverrun > rhs.costOverrun
            }
            if lhs.maxScheduleSlipDays != rhs.maxScheduleSlipDays {
                return lhs.maxScheduleSlipDays > rhs.maxScheduleSlipDays
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let topCostVarianceProjects = insights.sorted { lhs, rhs in
            if lhs.costOverrun != rhs.costOverrun {
                return lhs.costOverrun > rhs.costOverrun
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let topScheduleSlipProjects = insights.sorted { lhs, rhs in
            if lhs.maxScheduleSlipDays != rhs.maxScheduleSlipDays {
                return lhs.maxScheduleSlipDays > rhs.maxScheduleSlipDays
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        let upcomingMilestones = plans
            .flatMap { plan in
                plan.tasks.compactMap { task -> MilestoneRollup? in
                    guard task.isMilestone else { return nil }
                    let finishDate = calendar.startOfDay(for: task.finishDate)
                    guard finishDate >= today, finishDate <= milestoneHorizon else { return nil }
                    return MilestoneRollup(
                        id: "\(plan.portfolioID.uuidString)-upcoming-\(task.legacyID)",
                        planID: plan.portfolioID,
                        planTitle: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                        taskID: task.legacyID,
                        taskName: trimmedOrFallback(task.name, fallback: "Untitled Milestone"),
                        finishDate: finishDate,
                        slipDays: milestoneSlipDays(for: task, calendar: calendar),
                        category: "Upcoming"
                    )
                }
            }
            .sorted {
                if $0.finishDate != $1.finishDate {
                    return $0.finishDate < $1.finishDate
                }
                return $0.planTitle.localizedCaseInsensitiveCompare($1.planTitle) == .orderedAscending
            }

        let slippedMilestones = plans
            .flatMap { plan in
                plan.tasks.compactMap { task -> MilestoneRollup? in
                    guard task.isMilestone else { return nil }
                    let slipDays = milestoneSlipDays(for: task, calendar: calendar)
                    guard slipDays > 0 else { return nil }
                    return MilestoneRollup(
                        id: "\(plan.portfolioID.uuidString)-slipped-\(task.legacyID)",
                        planID: plan.portfolioID,
                        planTitle: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                        taskID: task.legacyID,
                        taskName: trimmedOrFallback(task.name, fallback: "Untitled Milestone"),
                        finishDate: calendar.startOfDay(for: task.finishDate),
                        slipDays: slipDays,
                        category: "Slipped"
                    )
                }
            }
            .sorted {
                if $0.slipDays != $1.slipDays {
                    return $0.slipDays > $1.slipDays
                }
                return $0.finishDate < $1.finishDate
            }

        var attentionFeed: [AttentionItem] = []
        for insight in rankedProjects {
            if insight.riskBand == "At Risk" {
                attentionFeed.append(
                    AttentionItem(
                        id: "\(insight.planID.uuidString)-risk",
                        planID: insight.planID,
                        planTitle: insight.title,
                        severity: "High",
                        headline: "Executive intervention recommended",
                        detail: insight.attentionReasons.first ?? "Portfolio risk score dropped below the healthy range.",
                        rank: 0
                    )
                )
            }
            if insight.costOverrun > 0 {
                attentionFeed.append(
                    AttentionItem(
                        id: "\(insight.planID.uuidString)-cost",
                        planID: insight.planID,
                        planTitle: insight.title,
                        severity: insight.costVariancePercent >= 15 ? "High" : "Medium",
                        headline: "Budget variance needs review",
                        detail: "Overrun \(CurrencyFormatting.string(from: insight.costOverrun)) against current budget.",
                        rank: insight.costVariancePercent >= 15 ? 1 : 3
                    )
                )
            }
            if insight.slippedMilestoneCount > 0 {
                attentionFeed.append(
                    AttentionItem(
                        id: "\(insight.planID.uuidString)-milestones",
                        planID: insight.planID,
                        planTitle: insight.title,
                        severity: insight.slippedMilestoneCount >= 2 ? "High" : "Medium",
                        headline: "Milestone slippage detected",
                        detail: "\(insight.slippedMilestoneCount) milestone(s) are behind baseline, max slip \(insight.maxScheduleSlipDays)d.",
                        rank: insight.slippedMilestoneCount >= 2 ? 1 : 4
                    )
                )
            }
            if insight.reviewOverdue || insight.reviewDueSoon {
                attentionFeed.append(
                    AttentionItem(
                        id: "\(insight.planID.uuidString)-review",
                        planID: insight.planID,
                        planTitle: insight.title,
                        severity: insight.reviewOverdue ? "High" : "Medium",
                        headline: insight.reviewOverdue ? "Portfolio review is overdue" : "Portfolio review due this week",
                        detail: insight.reviewDate.map { "Review date \($0.formatted(date: .abbreviated, time: .omitted))." } ?? "Set a review date for this initiative.",
                        rank: insight.reviewOverdue ? 2 : 5
                    )
                )
            }
        }

        attentionFeed.sort { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.planTitle.localizedCaseInsensitiveCompare(rhs.planTitle) == .orderedAscending
        }

        return PortfolioExecutiveSummary(
            projectInsights: insights,
            rankedProjects: rankedProjects,
            topCostVarianceProjects: topCostVarianceProjects,
            topScheduleSlipProjects: topScheduleSlipProjects,
            attentionFeed: attentionFeed,
            upcomingMilestones: upcomingMilestones,
            slippedMilestones: slippedMilestones,
            healthyCount: insights.filter { $0.riskBand == "Healthy" }.count,
            watchCount: insights.filter { $0.riskBand == "Watch" }.count,
            atRiskCount: insights.filter { $0.riskBand == "At Risk" }.count,
            reviewDueCount: insights.filter(\.reviewDueSoon).count,
            slippedMilestoneCount: slippedMilestones.count,
            upcomingMilestoneCount: upcomingMilestones.count
        )
    }

    private static func buildInsight(
        for plan: PortfolioAnalyticsPlanSnapshot,
        today: Date,
        reviewHorizon: Date,
        milestoneHorizon: Date,
        calendar: Calendar
    ) -> ProjectInsight {
        let tasks = plan.tasks
        let activeTasks = tasks.filter { $0.isActive && $0.percentComplete < 100 }
        let overdueTaskCount = activeTasks.filter { calendar.startOfDay(for: $0.finishDate) < today }.count
        let slippedTasks = activeTasks.filter { task in
            guard let baselineFinishDate = task.baselineFinishDate else { return false }
            return calendar.startOfDay(for: task.finishDate) > calendar.startOfDay(for: baselineFinishDate)
        }
        let milestones = tasks.filter(\.isMilestone)
        let slippedMilestones = milestones.filter { milestoneSlipDays(for: $0, calendar: calendar) > 0 }
        let upcomingMilestones = milestones.filter { task in
            let finishDate = calendar.startOfDay(for: task.finishDate)
            return finishDate >= today && finishDate <= milestoneHorizon
        }
        let nextMilestoneDate = milestones
            .map { calendar.startOfDay(for: $0.finishDate) }
            .filter { $0 >= today }
            .min()
        let maxScheduleSlipDays = slippedTasks.map { scheduleSlipDays(for: $0, calendar: calendar) }.max() ?? 0
        let completedTaskCount = tasks.filter { $0.percentComplete >= 100 }.count
        let completionPercent = tasks.isEmpty ? 0 : (Double(completedTaskCount) / Double(tasks.count)) * 100
        let budgetVariance = plan.portfolioBudget - plan.portfolioActualCost
        let costOverrun = max(0, -budgetVariance)
        let costVariancePercent = plan.portfolioBudget > 0 ? (costOverrun / plan.portfolioBudget) * 100 : 0
        let reviewDate = plan.portfolioReviewDate.map { calendar.startOfDay(for: $0) }
        let reviewDueSoon = reviewDate.map { $0 <= reviewHorizon } ?? false
        let reviewOverdue = reviewDate.map { $0 < today } ?? false

        var score = 100
        switch normalizedText(plan.portfolioHealth)?.lowercased() {
        case "red":
            score -= 40
        case "amber":
            score -= 24
        case "on hold":
            score -= 30
        case "green", nil:
            break
        default:
            score -= 8
        }

        score -= min(24, overdueTaskCount * 4)
        score -= min(18, slippedMilestones.count * 6)
        score -= min(15, maxScheduleSlipDays)
        score -= min(20, Int(costVariancePercent.rounded()))
        if reviewOverdue {
            score -= 10
        } else if reviewDueSoon {
            score -= 4
        }
        score = max(0, min(100, score))

        let riskBand: String
        switch score {
        case 80...100:
            riskBand = "Healthy"
        case 60..<80:
            riskBand = "Watch"
        default:
            riskBand = "At Risk"
        }

        var attentionReasons: [String] = []
        if let manualHealth = normalizedText(plan.portfolioHealth),
           manualHealth.caseInsensitiveCompare("Green") != .orderedSame {
            attentionReasons.append("Manual health \(manualHealth)")
        }
        if overdueTaskCount > 0 {
            attentionReasons.append("\(overdueTaskCount) overdue active task(s)")
        }
        if slippedMilestones.count > 0 {
            attentionReasons.append("\(slippedMilestones.count) slipped milestone(s)")
        }
        if costOverrun > 0 {
            attentionReasons.append("Cost overrun \(CurrencyFormatting.string(from: costOverrun))")
        }
        if reviewOverdue {
            attentionReasons.append("Review overdue")
        } else if reviewDueSoon {
            attentionReasons.append("Review due this week")
        }
        if attentionReasons.isEmpty {
            attentionReasons.append("No major delivery alerts")
        }

        return ProjectInsight(
            planID: plan.portfolioID,
            title: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
            workspace: trimmedOrFallback(plan.portfolioWorkspace ?? "", fallback: "Unassigned"),
            program: trimmedOrFallback(plan.portfolioProgram ?? "", fallback: "Unassigned"),
            sponsor: trimmedOrFallback(plan.portfolioSponsor ?? "", fallback: "Unassigned"),
            manualHealth: trimmedOrFallback(plan.portfolioHealth ?? "", fallback: "Not Set"),
            riskBand: riskBand,
            score: score,
            overdueTaskCount: overdueTaskCount,
            activeTaskCount: activeTasks.count,
            slippedTaskCount: slippedTasks.count,
            slippedMilestoneCount: slippedMilestones.count,
            upcomingMilestoneCount: upcomingMilestones.count,
            maxScheduleSlipDays: maxScheduleSlipDays,
            completionPercent: completionPercent,
            budgetVariance: budgetVariance,
            costOverrun: costOverrun,
            costVariancePercent: costVariancePercent,
            reviewDate: reviewDate,
            reviewDueSoon: reviewDueSoon,
            reviewOverdue: reviewOverdue,
            nextMilestoneDate: nextMilestoneDate,
            attentionReasons: attentionReasons
        )
    }

    private static func milestoneSlipDays(for task: PortfolioAnalyticsPlanSnapshot.Task, calendar: Calendar) -> Int {
        guard let baselineFinishDate = task.baselineFinishDate else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: baselineFinishDate), to: calendar.startOfDay(for: task.finishDate)).day ?? 0)
    }

    private static func scheduleSlipDays(for task: PortfolioAnalyticsPlanSnapshot.Task, calendar: Calendar) -> Int {
        milestoneSlipDays(for: task, calendar: calendar)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct PortfolioGovernanceSummary {
    struct ProjectInsight: Identifiable, Hashable {
        let planID: UUID
        let title: String
        let workspace: String
        let program: String
        let approvalState: String
        let stage: String
        let strategicAlignment: Int
        let riskScore: Int
        let governanceScore: Int
        let reviewDate: Date?
        let nextReviewDate: Date?
        let reviewCadenceDays: Int
        let reviewDueSoon: Bool
        let reviewOverdue: Bool
        let archiveReason: String?

        var id: UUID { planID }
    }

    let projectInsights: [ProjectInsight]
    let rankedProjects: [ProjectInsight]
    let approvedCount: Int
    let intakeCount: Int
    let onHoldCount: Int
    let cancelledCount: Int
    let reviewDueCount: Int
    let averageGovernanceScore: Int
    let averageStrategicAlignment: Int
    let averageRiskScore: Int

    static func build(plans: [PortfolioProjectPlan], now: Date = Date()) -> PortfolioGovernanceSummary {
        build(snapshots: plans.map { $0.analyticsSnapshot() }, now: now)
    }

    static func build(snapshots plans: [PortfolioAnalyticsPlanSnapshot], now: Date = Date()) -> PortfolioGovernanceSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dueSoonHorizon = calendar.date(byAdding: .day, value: 7, to: today) ?? today

        let insights = plans.map { buildInsight(for: $0, today: today, dueSoonHorizon: dueSoonHorizon, calendar: calendar) }
        let rankedProjects = insights.sorted { lhs, rhs in
            if lhs.governanceScore != rhs.governanceScore {
                return lhs.governanceScore > rhs.governanceScore
            }
            if lhs.approvalState != rhs.approvalState {
                return lhs.approvalState.localizedCaseInsensitiveCompare(rhs.approvalState) == .orderedAscending
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        func stateCount(_ states: Set<String>) -> Int {
            insights.filter { states.contains($0.approvalState.lowercased()) }.count
        }

        let totalScore = insights.reduce(0) { $0 + $1.governanceScore }
        let totalAlignment = insights.reduce(0) { $0 + $1.strategicAlignment }
        let totalRisk = insights.reduce(0) { $0 + $1.riskScore }
        let divisor = max(insights.count, 1)

        return PortfolioGovernanceSummary(
            projectInsights: insights,
            rankedProjects: rankedProjects,
            approvedCount: stateCount(["approved"]),
            intakeCount: stateCount(["proposed", "intake review"]),
            onHoldCount: stateCount(["on hold"]),
            cancelledCount: stateCount(["cancelled"]),
            reviewDueCount: insights.filter { $0.reviewDueSoon || $0.reviewOverdue }.count,
            averageGovernanceScore: totalScore / divisor,
            averageStrategicAlignment: totalAlignment / divisor,
            averageRiskScore: totalRisk / divisor
        )
    }

    private static func buildInsight(
        for plan: PortfolioAnalyticsPlanSnapshot,
        today: Date,
        dueSoonHorizon: Date,
        calendar: Calendar
    ) -> ProjectInsight {
        let approvalState = resolvedApprovalState(for: plan)
        let stage = trimmedOrFallback(plan.portfolioStage ?? "", fallback: "Not Set")
        let strategicAlignment = min(100, max(0, plan.portfolioStrategicAlignment ?? 50))
        let riskScore = min(100, max(0, plan.portfolioRiskScore ?? defaultRiskScore(for: plan)))
        let reviewCadenceDays = max(7, plan.portfolioReviewCadenceDays ?? 14)
        let reviewDate = plan.portfolioReviewDate.map { calendar.startOfDay(for: $0) }
        let nextReviewDate = reviewDate.flatMap { calendar.date(byAdding: .day, value: reviewCadenceDays, to: $0) }.map { calendar.startOfDay(for: $0) }
        let reviewOverdue = nextReviewDate.map { $0 < today } ?? false
        let reviewDueSoon = nextReviewDate.map { $0 <= dueSoonHorizon } ?? false

        var governanceScore = strategicAlignment
        governanceScore -= riskScore / 2

        switch approvalState.lowercased() {
        case "approved":
            governanceScore += 12
        case "intake review":
            governanceScore += 2
        case "proposed":
            governanceScore -= 4
        case "on hold":
            governanceScore -= 12
        case "cancelled":
            governanceScore -= 30
        default:
            break
        }

        switch stage.lowercased() {
        case "delivery":
            governanceScore += 8
        case "completed":
            governanceScore += 4
        case "planning":
            governanceScore -= 2
        case "on hold":
            governanceScore -= 6
        default:
            break
        }

        if plan.isArchivedValue {
            governanceScore -= 20
        }
        if reviewOverdue {
            governanceScore -= 10
        } else if reviewDueSoon {
            governanceScore -= 4
        }

        governanceScore = min(100, max(0, governanceScore))

        return ProjectInsight(
            planID: plan.portfolioID,
            title: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
            workspace: trimmedOrFallback(plan.portfolioWorkspace ?? "", fallback: "Unassigned"),
            program: trimmedOrFallback(plan.portfolioProgram ?? "", fallback: "Unassigned"),
            approvalState: approvalState,
            stage: stage,
            strategicAlignment: strategicAlignment,
            riskScore: riskScore,
            governanceScore: governanceScore,
            reviewDate: reviewDate,
            nextReviewDate: nextReviewDate,
            reviewCadenceDays: reviewCadenceDays,
            reviewDueSoon: reviewDueSoon,
            reviewOverdue: reviewOverdue,
            archiveReason: normalizedText(plan.portfolioArchiveReason)
        )
    }

    private static func resolvedApprovalState(for plan: PortfolioAnalyticsPlanSnapshot) -> String {
        if let value = normalizedText(plan.portfolioApprovalState) {
            return value
        }

        switch normalizedText(plan.portfolioStage)?.lowercased() {
        case "proposed":
            return "Proposed"
        case "approved", "delivery", "completed":
            return "Approved"
        case "on hold":
            return "On Hold"
        default:
            return "Intake Review"
        }
    }

    private static func defaultRiskScore(for plan: PortfolioAnalyticsPlanSnapshot) -> Int {
        switch normalizedText(plan.portfolioHealth)?.lowercased() {
        case "red":
            return 80
        case "amber":
            return 55
        case "on hold":
            return 65
        case "green":
            return 25
        default:
            return 40
        }
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct PortfolioResourceCapacitySummary {
    struct WeeklyDemand: Identifiable, Hashable {
        let weekStart: Date
        let totalHours: Double
        let capacityHours: Double
        let contributingPlans: [String]

        var id: Date { weekStart }
        var allocationPercent: Double {
            capacityHours > 0 ? (totalHours / capacityHours) * 100 : 0
        }
        var overloadHours: Double {
            max(0, totalHours - capacityHours)
        }
        var isOverloaded: Bool {
            totalHours > capacityHours + 0.01
        }
        var isDoubleBooked: Bool {
            contributingPlans.count > 1
        }
    }

    struct ResourceInsight: Identifiable, Hashable {
        let id: String
        let displayName: String
        let emailAddress: String?
        let group: String?
        let planTitles: [String]
        let weeklyDemand: [WeeklyDemand]

        var projectCount: Int { planTitles.count }
        var peakWeek: WeeklyDemand? {
            weeklyDemand.max { lhs, rhs in
                lhs.allocationPercent < rhs.allocationPercent
            }
        }
        var currentWeek: WeeklyDemand? {
            weeklyDemand.first(where: {
                Calendar.current.isDate($0.weekStart, equalTo: Date(), toGranularity: .weekOfYear)
            })
        }
        var peakAllocationPercent: Double {
            peakWeek?.allocationPercent ?? 0
        }
        var overloadedWeekCount: Int {
            weeklyDemand.filter(\.isOverloaded).count
        }
        var doubleBookedWeekCount: Int {
            weeklyDemand.filter(\.isDoubleBooked).count
        }
        var overloadHours: Double {
            weeklyDemand.reduce(0) { $0 + $1.overloadHours }
        }
        var currentAllocationPercent: Double {
            currentWeek?.allocationPercent ?? 0
        }
    }

    struct AlertItem: Identifiable, Hashable {
        let id: String
        let resourceID: String
        let resourceName: String
        let severity: String
        let headline: String
        let detail: String
        let contributingPlans: [String]
        let weekStart: Date
        let rank: Int
    }

    let resources: [ResourceInsight]
    let overloadedResources: [ResourceInsight]
    let sharedResources: [ResourceInsight]
    let alerts: [AlertItem]
    let uniqueResourceCount: Int
    let overloadedResourceCount: Int
    let sharedResourceCount: Int
    let overloadedWeekCount: Int
    let doubleBookedWeekCount: Int

    /// Lightweight value snapshot of a plan, captured on the main actor so the
    /// heavy schedule + workload computation can run off the main thread.
    struct PlanProjection: Sendable {
        let title: String
        let plan: NativeProjectPlan
    }

    static func projections(for plans: [PortfolioProjectPlan]) -> [PlanProjection] {
        plans.map { plan in
            PlanProjection(
                title: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                plan: plan.asNativePlan()
            )
        }
    }

    static func build(plans: [PortfolioProjectPlan], now: Date = Date()) -> PortfolioResourceCapacitySummary {
        build(projections: projections(for: plans), now: now)
    }

    static func build(projections planProjections: [PlanProjection], now: Date = Date()) -> PortfolioResourceCapacitySummary {
        struct MutableWeek {
            var totalHours: Double = 0
            var capacityHours: Double = 0
            var planTitles: Set<String> = []
        }

        struct MutableResource {
            var key: String
            var displayName: String
            var emailAddress: String?
            var group: String?
            var planTitles: Set<String> = []
            var weeklyDemandByStart: [Date: MutableWeek] = [:]
        }

        let calendar = Calendar.current
        var resourcesByKey: [String: MutableResource] = [:]

        for planProjection in planProjections {
            let project = planProjection.plan.asProjectModel()
            guard !project.tasks.isEmpty else { continue }

            let planTitle = planProjection.title
            let dateRange = GanttDateHelpers.dateRange(for: project.tasks)
            let workloads = WorkloadCalculator.compute(
                resources: project.resources,
                assignments: project.assignments,
                tasks: project.tasks,
                calendars: project.calendars,
                defaultCalendarID: project.properties.defaultCalendarUniqueId,
                dateRange: dateRange
            )

            for workload in workloads {
                guard let key = resourceKey(for: workload.resource) else { continue }
                let displayName = trimmedOrFallback(workload.resource.name ?? workload.resource.emailAddress ?? "", fallback: "Unnamed Resource")
                var aggregate = resourcesByKey[key] ?? MutableResource(
                    key: key,
                    displayName: displayName,
                    emailAddress: normalizedText(workload.resource.emailAddress),
                    group: normalizedText(workload.resource.group)
                )
                aggregate.planTitles.insert(planTitle)
                if aggregate.displayName == "Unnamed Resource", displayName != "Unnamed Resource" {
                    aggregate.displayName = displayName
                }
                aggregate.emailAddress = aggregate.emailAddress ?? normalizedText(workload.resource.emailAddress)
                aggregate.group = aggregate.group ?? normalizedText(workload.resource.group)

                for week in workload.weeklyLoads where week.totalHours > 0.01 {
                    let weekStart = calendar.startOfDay(for: week.weekStart)
                    var aggregateWeek = aggregate.weeklyDemandByStart[weekStart] ?? MutableWeek()
                    aggregateWeek.totalHours += week.totalHours
                    aggregateWeek.capacityHours = max(aggregateWeek.capacityHours, week.capacity)
                    aggregateWeek.planTitles.insert(planTitle)
                    aggregate.weeklyDemandByStart[weekStart] = aggregateWeek
                }

                resourcesByKey[key] = aggregate
            }
        }

        let resources: [ResourceInsight] = resourcesByKey.values.map { aggregate in
            let weeklyDemand = aggregate.weeklyDemandByStart
                .map { weekStart, week in
                    WeeklyDemand(
                        weekStart: weekStart,
                        totalHours: week.totalHours,
                        capacityHours: week.capacityHours,
                        contributingPlans: week.planTitles.sorted()
                    )
                }
                .sorted { $0.weekStart < $1.weekStart }

            return ResourceInsight(
                id: aggregate.key,
                displayName: aggregate.displayName,
                emailAddress: aggregate.emailAddress,
                group: aggregate.group,
                planTitles: aggregate.planTitles.sorted(),
                weeklyDemand: weeklyDemand
            )
        }
        .sorted { lhs, rhs in
            if lhs.peakAllocationPercent != rhs.peakAllocationPercent {
                return lhs.peakAllocationPercent > rhs.peakAllocationPercent
            }
            if lhs.projectCount != rhs.projectCount {
                return lhs.projectCount > rhs.projectCount
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        let overloadedResources = resources.filter { $0.overloadedWeekCount > 0 }
        let sharedResources = resources.filter { $0.projectCount > 1 }

        var alerts: [AlertItem] = []
        for resource in resources {
            if let peakWeek = resource.peakWeek, peakWeek.isOverloaded {
                alerts.append(
                    AlertItem(
                        id: "\(resource.id)-overload-\(peakWeek.weekStart.timeIntervalSince1970)",
                        resourceID: resource.id,
                        resourceName: resource.displayName,
                        severity: peakWeek.allocationPercent >= 150 ? "High" : "Medium",
                        headline: "Resource is overloaded",
                        detail: "Week of \(peakWeek.weekStart.formatted(date: .abbreviated, time: .omitted)) at \(Int(peakWeek.allocationPercent.rounded()))% capacity across \(peakWeek.contributingPlans.joined(separator: ", ")).",
                        contributingPlans: peakWeek.contributingPlans,
                        weekStart: peakWeek.weekStart,
                        rank: peakWeek.allocationPercent >= 150 ? 0 : 2
                    )
                )
            }

            if let sharedWeek = resource.weeklyDemand.first(where: { $0.isDoubleBooked }) {
                alerts.append(
                    AlertItem(
                        id: "\(resource.id)-shared-\(sharedWeek.weekStart.timeIntervalSince1970)",
                        resourceID: resource.id,
                        resourceName: resource.displayName,
                        severity: sharedWeek.isOverloaded ? "High" : "Medium",
                        headline: "Resource is booked across multiple projects",
                        detail: "Week of \(sharedWeek.weekStart.formatted(date: .abbreviated, time: .omitted)) shared by \(sharedWeek.contributingPlans.joined(separator: ", ")).",
                        contributingPlans: sharedWeek.contributingPlans,
                        weekStart: sharedWeek.weekStart,
                        rank: sharedWeek.isOverloaded ? 1 : 3
                    )
                )
            }
        }

        alerts.sort { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            if lhs.weekStart != rhs.weekStart {
                return lhs.weekStart < rhs.weekStart
            }
            return lhs.resourceName.localizedCaseInsensitiveCompare(rhs.resourceName) == .orderedAscending
        }

        return PortfolioResourceCapacitySummary(
            resources: resources,
            overloadedResources: overloadedResources,
            sharedResources: sharedResources,
            alerts: alerts,
            uniqueResourceCount: resources.count,
            overloadedResourceCount: overloadedResources.count,
            sharedResourceCount: sharedResources.count,
            overloadedWeekCount: resources.reduce(0) { $0 + $1.overloadedWeekCount },
            doubleBookedWeekCount: resources.reduce(0) { $0 + $1.doubleBookedWeekCount }
        )
    }

    private static func resourceKey(for resource: ProjectResource) -> String? {
        if let email = normalizedText(resource.emailAddress)?.lowercased() {
            return "email:\(email)"
        }
        if let name = normalizedText(resource.name)?.lowercased() {
            let group = normalizedText(resource.group)?.lowercased() ?? ""
            return "name:\(name)|group:\(group)"
        }
        return nil
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct PortfolioProgramRoadmapSummary {
    struct TimelineEvent: Identifiable, Hashable {
        let id: String
        let program: String
        let planID: UUID
        let planTitle: String
        let title: String
        let date: Date
        let kind: String
        let slipDays: Int
        let isLate: Bool

        var isReview: Bool { kind == "Review" }
    }

    struct ProgramInsight: Identifiable, Hashable {
        let program: String
        let workspaceNames: [String]
        let projectCount: Int
        let atRiskProjectCount: Int
        let reviewDueCount: Int
        let slippedMilestoneCount: Int
        let totalBudget: Double
        let totalActualCost: Double
        let nextMilestoneDate: Date?
        let timelineEvents: [TimelineEvent]

        var id: String { program }
    }

    let programs: [ProgramInsight]
    let timelineEvents: [TimelineEvent]
    let slippedMilestoneCount: Int
    let overdueReviewCount: Int

    static func build(plans: [PortfolioProjectPlan], now: Date = Date()) -> PortfolioProgramRoadmapSummary {
        build(snapshots: plans.map { $0.analyticsSnapshot() }, now: now)
    }

    static func build(snapshots plans: [PortfolioAnalyticsPlanSnapshot], now: Date = Date()) -> PortfolioProgramRoadmapSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let roadmapHorizon = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        let reviewHorizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today

        let groups = Dictionary(grouping: plans) { plan in
            trimmedOrFallback(plan.portfolioProgram ?? "", fallback: "Unassigned Program")
        }

        let programs = groups.map { program, plans -> ProgramInsight in
            let workspaceNames = Set(plans.map { trimmedOrFallback($0.portfolioWorkspace ?? "", fallback: "Unassigned") })
            let milestoneEvents: [TimelineEvent] = plans.flatMap { plan in
                plan.tasks.compactMap { task in
                    guard task.isMilestone else { return nil }
                    let finishDate = calendar.startOfDay(for: task.finishDate)
                    let slipDays = milestoneSlipDays(for: task, calendar: calendar)
                    let include = (finishDate >= today && finishDate <= roadmapHorizon) || slipDays > 0
                    guard include else { return nil }
                    return TimelineEvent(
                        id: "\(program)-milestone-\(plan.portfolioID.uuidString)-\(task.uniqueID.uuidString)",
                        program: program,
                        planID: plan.portfolioID,
                        planTitle: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                        title: trimmedOrFallback(task.name, fallback: "Untitled Milestone"),
                        date: finishDate,
                        kind: "Milestone",
                        slipDays: slipDays,
                        isLate: slipDays > 0
                    )
                }
            }

            let reviewEvents: [TimelineEvent] = plans.compactMap { plan in
                let cadenceDays = max(7, plan.portfolioReviewCadenceDays ?? 14)
                let reviewDate = plan.portfolioReviewDate.map { calendar.startOfDay(for: $0) }
                let nextReviewDate = reviewDate.flatMap { calendar.date(byAdding: .day, value: cadenceDays, to: $0) }.map { calendar.startOfDay(for: $0) }
                guard let nextReviewDate else { return nil }
                guard nextReviewDate <= roadmapHorizon else { return nil }
                return TimelineEvent(
                    id: "\(program)-review-\(plan.portfolioID.uuidString)",
                    program: program,
                    planID: plan.portfolioID,
                    planTitle: trimmedOrFallback(plan.title, fallback: "Untitled Plan"),
                    title: "Portfolio review",
                    date: nextReviewDate,
                    kind: "Review",
                    slipDays: 0,
                    isLate: nextReviewDate < today
                )
            }

            let timelineEvents = (milestoneEvents + reviewEvents).sorted {
                if $0.date != $1.date {
                    return $0.date < $1.date
                }
                if $0.kind != $1.kind {
                    return $0.kind.localizedCaseInsensitiveCompare($1.kind) == .orderedAscending
                }
                return $0.planTitle.localizedCaseInsensitiveCompare($1.planTitle) == .orderedAscending
            }

            let nextMilestoneDate = milestoneEvents
                .map(\.date)
                .filter { $0 >= today }
                .min()

            let atRiskProjectCount = plans.filter { plan in
                let manualHealth = normalizedText(plan.portfolioHealth)?.lowercased()
                if manualHealth == "red" || manualHealth == "amber" || manualHealth == "on hold" {
                    return true
                }
                let hasOverdueTask = plan.tasks.contains {
                    $0.isActive
                        && $0.percentComplete < 100
                        && calendar.startOfDay(for: $0.finishDate) < today
                }
                if hasOverdueTask {
                    return true
                }
                return plan.portfolioBudget > 0 && plan.portfolioActualCost > plan.portfolioBudget
            }.count

            let reviewDueCount = reviewEvents.filter { $0.date <= reviewHorizon || $0.isLate }.count

            return ProgramInsight(
                program: program,
                workspaceNames: workspaceNames.sorted(),
                projectCount: plans.count,
                atRiskProjectCount: atRiskProjectCount,
                reviewDueCount: reviewDueCount,
                slippedMilestoneCount: milestoneEvents.filter(\.isLate).count,
                totalBudget: plans.reduce(0) { $0 + $1.portfolioBudget },
                totalActualCost: plans.reduce(0) { $0 + $1.portfolioActualCost },
                nextMilestoneDate: nextMilestoneDate,
                timelineEvents: Array(timelineEvents.prefix(10))
            )
        }
        .sorted { lhs, rhs in
            if lhs.nextMilestoneDate != rhs.nextMilestoneDate {
                switch (lhs.nextMilestoneDate, rhs.nextMilestoneDate) {
                case let (left?, right?):
                    return left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    break
                }
            }
            if lhs.slippedMilestoneCount != rhs.slippedMilestoneCount {
                return lhs.slippedMilestoneCount > rhs.slippedMilestoneCount
            }
            return lhs.program.localizedCaseInsensitiveCompare(rhs.program) == .orderedAscending
        }

        return PortfolioProgramRoadmapSummary(
            programs: programs,
            timelineEvents: programs.flatMap(\.timelineEvents).sorted {
                if $0.date != $1.date {
                    return $0.date < $1.date
                }
                return $0.planTitle.localizedCaseInsensitiveCompare($1.planTitle) == .orderedAscending
            },
            slippedMilestoneCount: programs.reduce(0) { $0 + $1.slippedMilestoneCount },
            overdueReviewCount: programs.reduce(0) { $0 + $1.reviewDueCount }
        )
    }

    private static func milestoneSlipDays(for task: PortfolioAnalyticsPlanSnapshot.Task, calendar: Calendar) -> Int {
        guard let baselineFinishDate = task.baselineFinishDate else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: baselineFinishDate), to: calendar.startOfDay(for: task.finishDate)).day ?? 0)
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct PortfolioDependencySummary {
    struct DependencyInsight: Identifiable, Hashable {
        let id: UUID
        let sourcePlanID: UUID
        let sourcePlanTitle: String
        let sourceTaskName: String
        let targetPlanID: UUID
        let targetPlanTitle: String
        let targetTaskName: String
        let sourceProgram: String
        let targetProgram: String
        let relationType: String
        let lagDays: Int
        let note: String?
        let severity: String
        let blockerReason: String
        let targetDate: Date
        let requiredDate: Date
        let scheduleLeadDays: Int
        let sourcePercentComplete: Double
        let rank: Int

        var isCrossProgram: Bool {
            sourceProgram.caseInsensitiveCompare(targetProgram) != .orderedSame
        }
    }

    let dependencies: [DependencyInsight]
    let blockedCount: Int
    let highSeverityCount: Int
    let dueSoonCount: Int
    let crossProgramCount: Int

    static func build(
        plans: [PortfolioProjectPlan],
        dependencies: [PortfolioCrossProjectDependency],
        now: Date = Date()
    ) -> PortfolioDependencySummary {
        build(
            snapshots: plans.map { $0.analyticsSnapshot() },
            dependencySnapshots: dependencies.map { $0.analyticsSnapshot() },
            now: now
        )
    }

    static func build(
        snapshots plans: [PortfolioAnalyticsPlanSnapshot],
        dependencySnapshots dependencies: [PortfolioAnalyticsDependencySnapshot],
        now: Date = Date()
    ) -> PortfolioDependencySummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dueSoonHorizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today

        let planByID = Dictionary(nonThrowingUniquePairs: plans.map { ($0.portfolioID, $0) })
        let taskByPlanAndID: [UUID: [UUID: PortfolioAnalyticsPlanSnapshot.Task]] = Dictionary(
            uniqueKeysWithValues: plans.map { plan in
                (plan.portfolioID, Dictionary(uniqueKeysWithValues: plan.tasks.map { ($0.uniqueID, $0) }))
            }
        )

        let insights = dependencies.compactMap { dependency -> DependencyInsight? in
            guard let sourcePlan = planByID[dependency.sourcePlanID],
                  let targetPlan = planByID[dependency.targetPlanID],
                  let sourceTask = taskByPlanAndID[dependency.sourcePlanID]?[dependency.sourceTaskUniqueID],
                  let targetTask = taskByPlanAndID[dependency.targetPlanID]?[dependency.targetTaskUniqueID] else {
                return nil
            }

            let sourceStart = calendar.startOfDay(for: sourceTask.startDate)
            let sourceFinish = calendar.startOfDay(for: sourceTask.finishDate)
            let targetStart = calendar.startOfDay(for: targetTask.startDate)
            let targetFinish = calendar.startOfDay(for: targetTask.finishDate)

            let sourceAnchor: Date
            let targetAnchor: Date
            switch dependency.relationType.uppercased() {
            case "SS":
                sourceAnchor = sourceStart
                targetAnchor = targetStart
            case "FF":
                sourceAnchor = sourceFinish
                targetAnchor = targetFinish
            case "SF":
                sourceAnchor = sourceStart
                targetAnchor = targetFinish
            default:
                sourceAnchor = sourceFinish
                targetAnchor = targetStart
            }

            let requiredDate = calendar.date(byAdding: .day, value: dependency.lagDays, to: sourceAnchor) ?? sourceAnchor
            let scheduleLeadDays = calendar.dateComponents([.day], from: requiredDate, to: targetAnchor).day ?? 0
            let sourceIncomplete = sourceTask.percentComplete < 100
            let targetPastDue = targetAnchor < today
            let targetDueSoon = targetAnchor <= dueSoonHorizon
            let scheduleTooEarly = scheduleLeadDays < 0

            let severity: String
            let rank: Int
            let blockerReason: String
            if sourceIncomplete && targetPastDue {
                severity = "High"
                rank = 0
                let daysLate = max(1, calendar.dateComponents([.day], from: targetAnchor, to: today).day ?? 0)
                blockerReason = "Successor date opened \(daysLate)d ago while the predecessor is only \(Int(sourceTask.percentComplete.rounded()))% complete."
            } else if sourceIncomplete && targetDueSoon {
                severity = "High"
                rank = 1
                let daysToTarget = max(0, calendar.dateComponents([.day], from: today, to: targetAnchor).day ?? 0)
                blockerReason = "Successor handoff is due in \(daysToTarget)d and the predecessor is still in flight."
            } else if scheduleTooEarly {
                severity = "Medium"
                rank = 2
                blockerReason = "Successor schedule leads the dependency window by \(abs(scheduleLeadDays))d."
            } else if sourceIncomplete {
                severity = "Low"
                rank = 3
                blockerReason = "Dependency is registered and still waiting on predecessor completion."
            } else {
                severity = "Resolved"
                rank = 4
                blockerReason = "Predecessor is complete and the handoff window is satisfied."
            }

            return DependencyInsight(
                id: dependency.uniqueID,
                sourcePlanID: dependency.sourcePlanID,
                sourcePlanTitle: trimmedOrFallback(sourcePlan.title, fallback: dependency.sourcePlanTitle),
                sourceTaskName: trimmedOrFallback(sourceTask.name, fallback: dependency.sourceTaskName),
                targetPlanID: dependency.targetPlanID,
                targetPlanTitle: trimmedOrFallback(targetPlan.title, fallback: dependency.targetPlanTitle),
                targetTaskName: trimmedOrFallback(targetTask.name, fallback: dependency.targetTaskName),
                sourceProgram: trimmedOrFallback(sourcePlan.portfolioProgram ?? "", fallback: "Unassigned"),
                targetProgram: trimmedOrFallback(targetPlan.portfolioProgram ?? "", fallback: "Unassigned"),
                relationType: dependency.relationType.uppercased(),
                lagDays: dependency.lagDays,
                note: normalizedText(dependency.note),
                severity: severity,
                blockerReason: blockerReason,
                targetDate: targetAnchor,
                requiredDate: requiredDate,
                scheduleLeadDays: scheduleLeadDays,
                sourcePercentComplete: sourceTask.percentComplete,
                rank: rank
            )
        }
        .sorted { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            if lhs.targetDate != rhs.targetDate {
                return lhs.targetDate < rhs.targetDate
            }
            return lhs.targetPlanTitle.localizedCaseInsensitiveCompare(rhs.targetPlanTitle) == .orderedAscending
        }

        return PortfolioDependencySummary(
            dependencies: insights,
            blockedCount: insights.filter { $0.severity == "High" || $0.severity == "Medium" }.count,
            highSeverityCount: insights.filter { $0.severity == "High" }.count,
            dueSoonCount: insights.filter { $0.targetDate <= dueSoonHorizon && $0.severity != "Resolved" }.count,
            crossProgramCount: insights.filter(\.isCrossProgram).count
        )
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

extension PortfolioReviewSnapshotPayload {
    static func build(
        title: String,
        presetName: String?,
        viewSettings: PortfolioReviewViewSettings,
        plans: [PortfolioProjectPlan],
        executive: PortfolioExecutiveSummary,
        governance: PortfolioGovernanceSummary,
        roadmap: PortfolioProgramRoadmapSummary,
        dependencies: PortfolioDependencySummary,
        capacity: PortfolioResourceCapacitySummary,
        overdueTaskCount: Int,
        now: Date = Date()
    ) -> PortfolioReviewSnapshotPayload {
        let visibleProjectCount = plans.count
        let activeProjectCount = plans.filter { !$0.isArchivedValue }.count
        let archivedProjectCount = plans.filter(\.isArchivedValue).count
        let workspaceCount = Set(plans.compactMap { normalizedText($0.portfolioWorkspace) }).count
        let programCount = Set(plans.compactMap { normalizedText($0.portfolioProgram) }).count

        return PortfolioReviewSnapshotPayload(
            title: trimmedOrFallback(title, fallback: "Portfolio Review"),
            presetName: normalizedText(presetName),
            capturedAt: now,
            viewSettings: viewSettings,
            visibleProjectCount: visibleProjectCount,
            activeProjectCount: activeProjectCount,
            archivedProjectCount: archivedProjectCount,
            workspaceCount: workspaceCount,
            programCount: programCount,
            atRiskProjectCount: executive.atRiskCount,
            approvedCount: governance.approvedCount,
            intakeCount: governance.intakeCount,
            onHoldCount: governance.onHoldCount,
            reviewDueCount: max(executive.reviewDueCount, governance.reviewDueCount),
            overdueTaskCount: overdueTaskCount,
            blockedDependencyCount: dependencies.blockedCount,
            highDependencyCount: dependencies.highSeverityCount,
            crossProgramDependencyCount: dependencies.crossProgramCount,
            slippedMilestoneCount: executive.slippedMilestoneCount,
            roadmapProgramCount: roadmap.programs.count,
            overloadedResourceCount: capacity.overloadedResourceCount,
            budgetTotal: plans.reduce(0) { $0 + $1.portfolioBudget },
            actualCostTotal: plans.reduce(0) { $0 + $1.portfolioActualCost },
            projectSummaries: executive.rankedProjects.prefix(8).map { insight in
                PortfolioReviewSnapshotPayload.ProjectSummary(
                    id: insight.planID.uuidString,
                    title: insight.title,
                    riskBand: insight.riskBand,
                    score: insight.score,
                    workspace: insight.workspace,
                    program: insight.program,
                    overdueTaskCount: insight.overdueTaskCount,
                    slippedMilestoneCount: insight.slippedMilestoneCount,
                    costOverrun: insight.costOverrun,
                    completionPercent: insight.completionPercent
                )
            },
            attentionItems: executive.attentionFeed.prefix(12).map { item in
                PortfolioReviewSnapshotPayload.AttentionItem(
                    id: item.id,
                    severity: item.severity,
                    headline: item.headline,
                    planTitle: item.planTitle,
                    detail: item.detail
                )
            },
            programItems: roadmap.programs.prefix(8).map { insight in
                PortfolioReviewSnapshotPayload.ProgramSummary(
                    id: insight.id,
                    program: insight.program,
                    projectCount: insight.projectCount,
                    atRiskProjectCount: insight.atRiskProjectCount,
                    reviewDueCount: insight.reviewDueCount,
                    slippedMilestoneCount: insight.slippedMilestoneCount,
                    totalBudget: insight.totalBudget,
                    totalActualCost: insight.totalActualCost,
                    nextMilestoneDate: insight.nextMilestoneDate
                )
            },
            dependencyItems: dependencies.dependencies.prefix(10).map { dependency in
                PortfolioReviewSnapshotPayload.DependencySummary(
                    id: dependency.id.uuidString,
                    severity: dependency.severity,
                    sourcePlanTitle: dependency.sourcePlanTitle,
                    sourceTaskName: dependency.sourceTaskName,
                    targetPlanTitle: dependency.targetPlanTitle,
                    targetTaskName: dependency.targetTaskName,
                    relationType: dependency.relationType,
                    lagDays: dependency.lagDays,
                    blockerReason: dependency.blockerReason,
                    targetDate: dependency.targetDate
                )
            }
        )
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func trimmedOrFallback(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

extension PortfolioReviewDelta {
    static func build(current: PortfolioReviewSnapshotPayload, baseline: PortfolioReviewSnapshotPayload) -> PortfolioReviewDelta {
        let currentAttention = Set(current.attentionItems.map { "\($0.planTitle)|\($0.headline)" })
        let baselineAttention = Set(baseline.attentionItems.map { "\($0.planTitle)|\($0.headline)" })
        let currentBlockedDependencies = Set(
            current.dependencyItems
                .filter { $0.severity == "High" || $0.severity == "Medium" }
                .map { "\($0.sourcePlanTitle): \($0.sourceTaskName) -> \($0.targetPlanTitle): \($0.targetTaskName)" }
        )
        let baselineBlockedDependencies = Set(
            baseline.dependencyItems
                .filter { $0.severity == "High" || $0.severity == "Medium" }
                .map { "\($0.sourcePlanTitle): \($0.sourceTaskName) -> \($0.targetPlanTitle): \($0.targetTaskName)" }
        )

        return PortfolioReviewDelta(
            current: current,
            baseline: baseline,
            visibleProjectDelta: current.visibleProjectCount - baseline.visibleProjectCount,
            atRiskProjectDelta: current.atRiskProjectCount - baseline.atRiskProjectCount,
            blockedDependencyDelta: current.blockedDependencyCount - baseline.blockedDependencyCount,
            highDependencyDelta: current.highDependencyCount - baseline.highDependencyCount,
            reviewDueDelta: current.reviewDueCount - baseline.reviewDueCount,
            slippedMilestoneDelta: current.slippedMilestoneCount - baseline.slippedMilestoneCount,
            overloadedResourceDelta: current.overloadedResourceCount - baseline.overloadedResourceCount,
            overdueTaskDelta: current.overdueTaskCount - baseline.overdueTaskCount,
            budgetDelta: current.budgetTotal - baseline.budgetTotal,
            actualCostDelta: current.actualCostTotal - baseline.actualCostTotal,
            newAttentionHeadlines: Array(currentAttention.subtracting(baselineAttention)).sorted(),
            resolvedAttentionHeadlines: Array(baselineAttention.subtracting(currentAttention)).sorted(),
            newBlockedDependencies: Array(currentBlockedDependencies.subtracting(baselineBlockedDependencies)).sorted()
        )
    }
}

struct StatusOvertimeDriver: Identifiable {
    let assignment: NativePlanAssignment
    let resource: NativePlanResource?

    var id: Int { assignment.id }
}

struct StatusCenterDerivedContent {
    let workTasks: [ProjectTask]
    let statusMetrics: EVMMetrics
    let overdueCount: Int
    let inProgressCount: Int
    let missingActualCount: Int
    let filteredTasks: [ProjectTask]
    let assignmentsByTaskID: [Int: [NativePlanAssignment]]
    let topScheduleSlips: [ProjectTask]
    let topCostOverruns: [ProjectTask]
    let topOvertimeDrivers: [StatusOvertimeDriver]
    let sortedSnapshots: [NativeStatusSnapshot]

    static func build(
        project: ProjectModel,
        assignments: [NativePlanAssignment],
        resources: [NativePlanResource],
        statusDate: Date,
        snapshots: [NativeStatusSnapshot],
        filter: StatusTaskFilter,
        searchText: String
    ) -> StatusCenterDerivedContent {
        let workTasks = project.tasks.filter { $0.summary != true }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let assignmentsByTaskID = Dictionary(grouping: assignments, by: \.taskID)
        let resourcesByID = Dictionary(nonThrowingUniquePairs: resources.map { ($0.id, $0) })

        let filteredTasks = workTasks.filter { task in
            let matchesFilter = switch filter {
            case .all:
                true
            case .attention:
                taskStatusNeedsAttentionStatic(task, statusDate: statusDate)
            case .inProgress:
                task.isInProgress
            case .overdue:
                !task.isCompleted && ((task.finishDate ?? .distantFuture) < statusDate)
            case .missingActuals:
                ((task.percentComplete ?? 0) > 0 && task.actualStart == nil) || (task.isCompleted && task.actualFinish == nil)
            }

            guard matchesFilter else { return false }
            guard !trimmedSearch.isEmpty else { return true }
            return task.displayName.lowercased().contains(trimmedSearch)
                || (task.wbs?.lowercased().contains(trimmedSearch) == true)
                || (task.id.map(String.init)?.contains(trimmedSearch) == true)
        }

        let topScheduleSlips = Array(
            workTasks
                .filter { ($0.finishVarianceDays ?? 0) > 0 }
                .sorted { ($0.finishVarianceDays ?? 0) > ($1.finishVarianceDays ?? 0) }
                .prefix(5)
        )

        let topCostOverruns = Array(
            workTasks
                .filter { task in
                    let baseline = task.baselineCost ?? task.cost ?? 0
                    let actual = task.actualCost ?? 0
                    return baseline > 0 && actual > baseline
                }
                .sorted { lhs, rhs in
                    let lhsBaseline = lhs.baselineCost ?? lhs.cost ?? 0
                    let rhsBaseline = rhs.baselineCost ?? rhs.cost ?? 0
                    let lhsOverrun = (lhs.actualCost ?? 0) - lhsBaseline
                    let rhsOverrun = (rhs.actualCost ?? 0) - rhsBaseline
                    return lhsOverrun > rhsOverrun
                }
                .prefix(5)
        )

        let topOvertimeDrivers = assignments
            .filter { ($0.overtimeWorkSeconds ?? 0) > 0 }
            .sorted { ($0.overtimeWorkSeconds ?? 0) > ($1.overtimeWorkSeconds ?? 0) }
            .prefix(5)
            .map { assignment in
                StatusOvertimeDriver(
                    assignment: assignment,
                    resource: assignment.resourceID.flatMap { resourcesByID[$0] }
                )
            }

        return StatusCenterDerivedContent(
            workTasks: workTasks,
            statusMetrics: EVMCalculator.projectMetrics(tasks: workTasks, statusDate: statusDate),
            overdueCount: workTasks.filter { !$0.isCompleted && ($0.finishDate ?? .distantFuture) < statusDate }.count,
            inProgressCount: workTasks.filter(\.isInProgress).count,
            missingActualCount: workTasks.filter { task in
                let shouldHaveActualStart = (task.percentComplete ?? 0) > 0
                let shouldHaveActualFinish = task.isCompleted
                let missingStart = shouldHaveActualStart && task.actualStart == nil
                let missingFinish = shouldHaveActualFinish && task.actualFinish == nil
                return missingStart || missingFinish
            }.count,
            filteredTasks: filteredTasks,
            assignmentsByTaskID: assignmentsByTaskID,
            topScheduleSlips: topScheduleSlips,
            topCostOverruns: topCostOverruns,
            topOvertimeDrivers: topOvertimeDrivers,
            sortedSnapshots: snapshots.sorted(by: { $0.statusDate > $1.statusDate })
        )
    }

    private static func taskStatusNeedsAttentionStatic(_ task: ProjectTask, statusDate: Date) -> Bool {
        let overdue = !task.isCompleted && ((task.finishDate ?? .distantFuture) < statusDate)
        let hasCostOverrun = {
            let baseline = task.baselineCost ?? task.cost ?? 0
            let actual = task.actualCost ?? 0
            return baseline > 0 && actual > baseline
        }()
        let missingActualStart = (task.percentComplete ?? 0) > 0 && task.actualStart == nil
        let missingActualFinish = task.isCompleted && task.actualFinish == nil
        return overdue || hasCostOverrun || missingActualStart || missingActualFinish
    }
}

struct AgileLaneTasks: Identifiable {
    let lane: String
    let tasks: [NativePlanTask]
    let id: String

    init(lane: String, tasks: [NativePlanTask], id: String) {
        self.lane = lane
        self.tasks = tasks
        self.id = id
    }
}

struct AgileSwimlaneGroup: Identifiable {
    let key: String
    let title: String
    let tasks: [NativePlanTask]
    let lane: String
    let parentTaskID: Int?
    let representsHierarchyRoot: Bool

    var id: String { key }
}

struct AgileBoardDerivedContent {
    let agileTasks: [NativePlanTask]
    let backlogTasks: [NativePlanTask]
    let boardColumns: [String]
    let tasksByLane: [AgileLaneTasks]
    let normalizedStatusByTaskID: [Int: String]
    let sprintNamesByID: [Int: String]
    let taskByID: [Int: NativePlanTask]
    let taskOrderByID: [Int: Int]
    let parentTaskIDByTaskID: [Int: Int]
    let parentTaskNameByTaskID: [Int: String]
    let rootParentTaskIDByTaskID: [Int: Int]
    let hierarchyDepthByTaskID: [Int: Int]
    let assignmentSummaryByTaskID: [Int: String]
    let primaryAssigneeNameByTaskID: [Int: String]
    let teamTitleByTaskID: [Int: String]
    let tasksBySprintID: [Int: [NativePlanTask]]
    let committedPointsBySprintID: [Int: Int]
    let completedPointsBySprintID: [Int: Int]
    let agileTypeCounts: [String: Int]
    let latestSnapshot: NativeStatusSnapshot?
    let totalStoryPoints: Int
    let totalSprintCapacityPoints: Int
    let doneCount: Int
    let readyCount: Int
    let inProgressCount: Int
    let completedCount: Int

    static func build(
        tasks: [NativePlanTask],
        assignments: [NativePlanAssignment],
        resources: [NativePlanResource],
        sprints: [NativePlanSprint],
        boardColumns configuredBoardColumns: [String],
        workflowColumns: [NativeBoardWorkflowColumn],
        typeWorkflowOverrides: [NativeBoardTypeWorkflow],
        statusSnapshots: [NativeStatusSnapshot]
    ) -> AgileBoardDerivedContent {
        var summaryTaskIDs: Set<Int> = []
        for index in tasks.indices.dropLast() where tasks[index + 1].outlineLevel > tasks[index].outlineLevel {
            summaryTaskIDs.insert(tasks[index].id)
        }

        var taskOrderByID: [Int: Int] = [:]
        var parentTaskIDByTaskID: [Int: Int] = [:]
        var parentTaskNameByTaskID: [Int: String] = [:]
        var hierarchyDepthByTaskID: [Int: Int] = [:]
        var outlineStack: [(level: Int, id: Int, name: String)] = []

        for (index, task) in tasks.enumerated() {
            taskOrderByID[task.id] = index

            while let last = outlineStack.last, last.level >= task.outlineLevel {
                outlineStack.removeLast()
            }

            if let parent = outlineStack.last {
                parentTaskIDByTaskID[task.id] = parent.id
                parentTaskNameByTaskID[task.id] = parent.name
                hierarchyDepthByTaskID[task.id] = max(0, task.outlineLevel - 1)
            } else {
                hierarchyDepthByTaskID[task.id] = 0
            }

            outlineStack.append((level: task.outlineLevel, id: task.id, name: task.name))
        }

        let activeTasks = tasks.filter(\.isActive)
        let taskByID = Dictionary(nonThrowingUniquePairs: activeTasks.map { ($0.id, $0) })
        var rootParentTaskIDByTaskID: [Int: Int] = [:]

        for task in activeTasks {
            var rootID = task.id
            var currentID = task.id
            while let parentID = parentTaskIDByTaskID[currentID] {
                rootID = parentID
                currentID = parentID
            }
            rootParentTaskIDByTaskID[task.id] = rootID
        }

        let agileTasks = activeTasks.filter { task in
            !summaryTaskIDs.contains(task.id) || task.storyPoints != nil || !task.boardStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !task.epicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let taskStatuses = agileTasks
            .map(\.boardStatus)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        var ordered: [String] = []

        let configuredColumns = workflowColumns.isEmpty ? configuredBoardColumns : workflowColumns.map(\.name)

        for column in configuredColumns where !column.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = column.trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(normalized.lowercased()).inserted {
                ordered.append(normalized)
            }
        }

        for status in taskStatuses where seen.insert(status.lowercased()).inserted {
            ordered.append(status)
        }

        let boardColumns = ordered.isEmpty ? NativeProjectPlan.defaultBoardColumns : ordered
        var normalizedStatusByTaskID: [Int: String] = [:]
        for task in agileTasks {
            normalizedStatusByTaskID[task.id] = normalizedBoardStatus(task.boardStatus, boardColumns: boardColumns)
        }
        let grouped = Dictionary(grouping: agileTasks) { task in
            normalizedStatusByTaskID[task.id] ?? (boardColumns.first ?? "Backlog")
        }

        let laneColumns = boardColumns.enumerated().map { index, lane in
            (lane: lane, id: "\(index)|\(lane)")
        }
        let sprintNamesByID = Dictionary(nonThrowingUniquePairs: sprints.map { ($0.id, $0.name) })
        let resourceByID = Dictionary(nonThrowingUniquePairs: resources.map { ($0.id, $0) })
        let sprintTeamByID = Dictionary(
            uniqueKeysWithValues: sprints.compactMap { sprint -> (Int, String)? in
                let trimmed = sprint.teamName.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : (sprint.id, trimmed)
            }
        )
        var assignmentResourceIDsByTaskID: [Int: [Int]] = [:]
        for assignment in assignments {
            guard let resourceID = assignment.resourceID else { continue }
            assignmentResourceIDsByTaskID[assignment.taskID, default: []].append(resourceID)
        }

        var assignmentSummaryByTaskID: [Int: String] = [:]
        var primaryAssigneeNameByTaskID: [Int: String] = [:]
        var teamTitleByTaskID: [Int: String] = [:]
        var tasksBySprintID: [Int: [NativePlanTask]] = [:]
        var committedPointsBySprintID: [Int: Int] = [:]
        var completedPointsBySprintID: [Int: Int] = [:]
        var agileTypeCounts: [String: Int] = [:]

        for task in agileTasks {
            let resourceIDs = assignmentResourceIDsByTaskID[task.id] ?? []
            let assigneeNames = resourceIDs.compactMap { resourceID -> String? in
                guard let resource = resourceByID[resourceID] else { return nil }
                let trimmed = resource.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let firstAssignee = assigneeNames.first {
                primaryAssigneeNameByTaskID[task.id] = firstAssignee
                assignmentSummaryByTaskID[task.id] = assigneeNames.count == 1 ? firstAssignee : "\(firstAssignee) +\(assigneeNames.count - 1)"
            }

            let teamTitle = resourceIDs.compactMap { resourceID -> String? in
                guard let resource = resourceByID[resourceID] else { return nil }
                let trimmed = resource.group.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }.first
            ?? task.sprintID.flatMap { sprintTeamByID[$0] }
            ?? "No Team"
            teamTitleByTaskID[task.id] = teamTitle

            if let sprintID = task.sprintID {
                tasksBySprintID[sprintID, default: []].append(task)
                committedPointsBySprintID[sprintID, default: 0] += max(0, task.storyPoints ?? 0)
                if normalizedStatusByTaskID[task.id]?.compare("Done", options: .caseInsensitive) == .orderedSame || task.percentComplete >= 100 {
                    completedPointsBySprintID[sprintID, default: 0] += max(0, task.storyPoints ?? 0)
                }
            }

            let typeKey = task.agileType.trimmingCharacters(in: .whitespacesAndNewlines)
            agileTypeCounts[typeKey.isEmpty ? "Task" : typeKey, default: 0] += 1
        }

        for sprintID in tasksBySprintID.keys {
            tasksBySprintID[sprintID]?.sort { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.id < rhs.id
                }
                return lhs.startDate < rhs.startDate
            }
        }

        let readyCount = agileTasks.reduce(0) { partial, task in
            partial + (normalizedStatusByTaskID[task.id] == "Ready" ? 1 : 0)
        }
        let inProgressCount = agileTasks.reduce(0) { partial, task in
            partial + (normalizedStatusByTaskID[task.id] == "In Progress" ? 1 : 0)
        }
        let completedCount = agileTasks.reduce(0) { partial, task in
            partial + (((normalizedStatusByTaskID[task.id] == "Done") || task.percentComplete >= 100) ? 1 : 0)
        }

        return AgileBoardDerivedContent(
            agileTasks: agileTasks,
            backlogTasks: agileTasks.filter { $0.sprintID == nil },
            boardColumns: boardColumns,
            tasksByLane: laneColumns.map { laneDescriptor in
                AgileLaneTasks(
                    lane: laneDescriptor.lane,
                    tasks: grouped[laneDescriptor.lane] ?? [],
                    id: laneDescriptor.id
                )
            },
            normalizedStatusByTaskID: normalizedStatusByTaskID,
            sprintNamesByID: sprintNamesByID,
            taskByID: taskByID,
            taskOrderByID: taskOrderByID,
            parentTaskIDByTaskID: parentTaskIDByTaskID,
            parentTaskNameByTaskID: parentTaskNameByTaskID,
            rootParentTaskIDByTaskID: rootParentTaskIDByTaskID,
            hierarchyDepthByTaskID: hierarchyDepthByTaskID,
            assignmentSummaryByTaskID: assignmentSummaryByTaskID,
            primaryAssigneeNameByTaskID: primaryAssigneeNameByTaskID,
            teamTitleByTaskID: teamTitleByTaskID,
            tasksBySprintID: tasksBySprintID,
            committedPointsBySprintID: committedPointsBySprintID,
            completedPointsBySprintID: completedPointsBySprintID,
            agileTypeCounts: agileTypeCounts,
            latestSnapshot: statusSnapshots.sorted { $0.statusDate < $1.statusDate }.last,
            totalStoryPoints: agileTasks.reduce(0) { $0 + max(0, $1.storyPoints ?? 0) },
            totalSprintCapacityPoints: sprints.reduce(0) { $0 + max(0, $1.capacityPoints) },
            doneCount: completedCount,
            readyCount: readyCount,
            inProgressCount: inProgressCount,
            completedCount: completedCount
        )
    }

    private static func normalizedBoardStatus(_ rawStatus: String, boardColumns: [String]) -> String {
        let normalized = rawStatus.trimmingCharacters(in: .whitespacesAndNewlines)
        return boardColumns.first(where: { $0.compare(normalized, options: .caseInsensitive) == .orderedSame }) ?? boardColumns.first ?? "Backlog"
    }
}

struct StableDecimalTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        NativeDraftTextField(title: title, text: $text, trimsWhitespaceOnCommit: true)
    }
}

struct StableDraftTextField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        NativeDraftTextField(title: title, text: $text, trimsWhitespaceOnCommit: false)
    }
}

private struct NativeDraftTextField: NSViewRepresentable {
    let title: String
    @Binding var text: String
    var trimsWhitespaceOnCommit: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, trimsWhitespaceOnCommit: trimsWhitespaceOnCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = LightweightDraftTextField()
        textField.placeholderString = title
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.usesSingleLineMode = true
        textField.lineBreakMode = .byTruncatingTail
        textField.stringValue = text
        context.coordinator.applyAppearance(to: textField, isEditing: false)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.placeholderString = title
        context.coordinator.trimsWhitespaceOnCommit = trimsWhitespaceOnCommit

        if !context.coordinator.isEditing, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var trimsWhitespaceOnCommit: Bool
        var isEditing = false

        init(text: Binding<String>, trimsWhitespaceOnCommit: Bool) {
            self._text = text
            self.trimsWhitespaceOnCommit = trimsWhitespaceOnCommit
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
            if let field = obj.object as? NSTextField {
                applyAppearance(to: field, isEditing: true)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            defer {
                isEditing = false
                if let field = obj.object as? NSTextField {
                    applyAppearance(to: field, isEditing: false)
                }
            }
            guard let field = obj.object as? NSTextField else { return }
            let committed = trimsWhitespaceOnCommit
                ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                : field.stringValue
            if field.stringValue != committed {
                field.stringValue = committed
            }
            text = committed
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                control.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        func applyAppearance(to field: NSTextField, isEditing: Bool) {
            field.layer?.borderColor = (isEditing ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.55)).cgColor
            field.layer?.borderWidth = isEditing ? 1.5 : 1
        }
    }
}

private final class LightweightDraftTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        cell = LightweightDraftTextFieldCell(textCell: "")
        isBezeled = false
        isBordered = false
        drawsBackground = true
        backgroundColor = NSColor.controlBackgroundColor.blended(withFraction: 0.35, of: .windowBackgroundColor) ?? .controlBackgroundColor
        focusRingType = .none
        wantsLayer = true
        font = .systemFont(ofSize: 13, weight: .regular)
        textColor = .labelColor
        isEditable = true
        isSelectable = true
        lineBreakMode = .byTruncatingTail
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.38).cgColor
        layer?.backgroundColor = backgroundColor?.cgColor
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width, height: max(30, size.height + 10))
    }

    override func layout() {
        super.layout()
        layer?.backgroundColor = backgroundColor?.cgColor
    }
}

private final class LightweightDraftTextFieldCell: NSTextFieldCell {
    private let horizontalInset: CGFloat = 10
    private let verticalInset: CGFloat = 6

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: rect.insetBy(dx: horizontalInset, dy: verticalInset), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: rect.insetBy(dx: horizontalInset, dy: verticalInset), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case portfolio = "Portfolio"
    case dashboard = "Dashboard"
    case planner = "Plan Builder"
    case agileBoard = "Agile Board"
    case statusCenter = "Status Center"
    case executive = "Executive Mode"
    case summary = "Summary"
    case validation = "Validation"
    case diagnostics = "Diagnostics"
    case dependencyExplorer = "Dependency Explorer"
    case resourceRisks = "Resource Risks"
    case criticalPath = "Critical Path"
    case tasks = "Tasks"
    case gantt = "Gantt Chart"
    case schedule = "Schedule"
    case milestones = "Milestones"
    case resources = "Resources"
    case earnedValue = "Earned Value"
    case workload = "Workload"
    case calendar = "Calendar"
    case eventsLeave = "Events & Leave"
    case timeline = "Timeline"
    case diff = "Compare"
    case helpCenter = "Guide & Help"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .portfolio: return "square.stack.3d.up"
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .planner: return "square.and.pencil"
        case .agileBoard: return "rectangle.3.group.bubble.left"
        case .statusCenter: return "checklist"
        case .executive: return "display"
        case .summary: return "doc.text"
        case .validation: return "checklist.unchecked"
        case .diagnostics: return "stethoscope"
        case .dependencyExplorer: return "network"
        case .resourceRisks: return "person.crop.circle.badge.exclamationmark"
        case .criticalPath: return "point.topleft.down.curvedto.point.bottomright.up"
        case .tasks: return "list.bullet.indent"
        case .gantt: return "chart.bar.xaxis"
        case .schedule: return "rectangle.split.2x1"
        case .milestones: return "diamond.fill"
        case .resources: return "person.2"
        case .earnedValue: return "chart.line.uptrend.xyaxis"
        case .workload: return "person.badge.clock"
        case .calendar: return "calendar"
        case .eventsLeave: return "calendar.badge.clock"
        case .timeline: return "rectangle.split.3x1"
        case .diff: return "arrow.triangle.2.circlepath"
        case .helpCenter: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @Binding var document: PlanningDocument
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PortfolioProjectPlan.updatedAt, order: .reverse)])
    private var portfolioPlans: [PortfolioProjectPlan]
    @StateObject private var store = ProjectStore()
    @State private var editableAnalysis: NativePlanAnalysis?
    @State private var selectedNav: NavigationItem?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var isFocusMode = false
    @State private var isPresentationMode = false
    @State private var searchText = ""
    @State private var searchSuggestionTasks: [ProjectTask] = []
    @State private var searchSuggestionWorkItem: DispatchWorkItem?
    @State private var navigateToTaskID: Int?
    @State private var showCommandPalette = false
    @State private var cachedFlaggedTaskIDs: Set<Int> = []
    @State private var editableWorkspaceError: String?
    @State private var documentActionMessage: String?
    @State private var selectedWorkspacePortfolioID: UUID?
    @State private var isRefreshingEditableAnalysis = false
    @State private var isSavingNativePlan = false
    @State private var isMaterializingEditableWorkspace = false
    @State private var transientEditablePortfolioPlan: PortfolioProjectPlan?
    @State private var editableAnalysisGeneration = 0
    @AppStorage("flaggedTaskIDs") private var flaggedTaskIDsData: Data = Data()

    init(document: Binding<PlanningDocument>) {
        self._document = document
        self._editableAnalysis = State(initialValue: nil)
        self._cachedFlaggedTaskIDs = State(initialValue: (try? JSONDecoder().decode(Set<Int>.self, from: UserDefaults.standard.data(forKey: "flaggedTaskIDs") ?? Data())) ?? [])
        self._selectedWorkspacePortfolioID = State(initialValue: document.wrappedValue.editablePortfolioID)
    }

    private var flaggedTaskIDs: Binding<Set<Int>> {
        Binding(
            get: {
                cachedFlaggedTaskIDs
            },
            set: { newValue in
                cachedFlaggedTaskIDs = newValue
                flaggedTaskIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            }
        )
    }

    private func computeSearchSuggestionTasks(for query: String, project: ProjectModel?) -> [ProjectTask] {
        guard let project, !query.isEmpty else { return [] }
        let search = query.lowercased()
        return project.tasks.filter { task in
            let directMatch =
                task.name?.lowercased().contains(search) == true ||
                task.wbs?.lowercased().contains(search) == true ||
                task.notes?.lowercased().contains(search) == true ||
                task.id.map(String.init)?.contains(search) == true ||
                task.customFields?.values.contains(where: { $0.displayString.lowercased().contains(search) }) == true
            let resourceMatch = project.assignments
                .filter { $0.taskUniqueID == task.uniqueID }
                .contains { assignment in
                    guard let resourceID = assignment.resourceUniqueID else { return false }
                    return project.resources.first(where: { $0.uniqueID == resourceID })?.name?.lowercased().contains(search) == true
                }
            return directMatch || resourceMatch
        }
        .prefix(10)
        .map { $0 }
    }

    private func scheduleSearchSuggestionsRefresh() {
        searchSuggestionWorkItem?.cancel()

        let query = searchText
        let project = currentProject
        let workItem = DispatchWorkItem {
            searchSuggestionTasks = computeSearchSuggestionTasks(for: query, project: project)
        }
        searchSuggestionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private var currentProject: ProjectModel? {
        if document.isEditablePlan {
            return editableAnalysis?.project
        }
        return store.project
    }

    private var editablePortfolioPlan: PortfolioProjectPlan? {
        guard let editablePortfolioID = document.editablePortfolioID else { return nil }
        return portfolioPlan(for: editablePortfolioID)
    }

    private var effectiveEditablePortfolioPlan: PortfolioProjectPlan? {
        guard document.isEditablePlan else { return nil }
        return editablePortfolioPlan
    }

    private var workspacePortfolioID: UUID? {
        selectedWorkspacePortfolioID ?? document.editablePortfolioID
    }

    private var effectiveWorkspacePortfolioPlan: PortfolioProjectPlan? {
        if let activeID = workspacePortfolioID {
            return portfolioPlan(for: activeID)
        }
        return nil
    }

    private var activeDetailPortfolioPlan: PortfolioProjectPlan? {
        guard document.isEditablePlan else { return nil }
        if let effectiveWorkspacePortfolioPlan {
            return effectiveWorkspacePortfolioPlan
        }
        if workspacePortfolioID == document.editablePortfolioID {
            return transientEditablePortfolioPlan
        }
        return nil
    }

    private var workspacePortfolioBinding: Binding<UUID?> {
        Binding(
            get: { workspacePortfolioID },
            set: { newValue in
                selectedWorkspacePortfolioID = newValue
                if document.isEditablePlan {
                    document.editablePortfolioID = newValue
                }
            }
        )
    }

    private var displayProject: ProjectModel? {
        if document.isEditablePlan {
            return editableAnalysis?.project
        }
        return currentProject
    }

    private func archiveEditablePlan(_ nativePlan: NativeProjectPlan) {
        if document.editablePortfolioID != nativePlan.portfolioID {
            document.editablePortfolioID = nativePlan.portfolioID
        }

        guard let encodedPlan = try? nativePlan.encodedData() else { return }
        if document.editablePlanData != encodedPlan {
            document.editablePlanData = encodedPlan
            document.editablePlanSeed = nil
        }
    }

    private func portfolioPlan(for id: UUID?) -> PortfolioProjectPlan? {
        guard let editablePortfolioID = id ?? document.editablePortfolioID else { return nil }
        if let documentPlan = document.nativePlan,
           documentPlan.portfolioID == editablePortfolioID || document.editablePortfolioID == editablePortfolioID,
           let recoveredPlan = recoverableStoredPlan(for: documentPlan) {
            return recoveredPlan
        }
        return portfolioPlans.first(where: { $0.portfolioID == editablePortfolioID })
    }

    private func isEmptyNativePlan(_ plan: NativeProjectPlan?) -> Bool {
        guard let plan else { return true }
        return plan.tasks.isEmpty && plan.resources.isEmpty && plan.assignments.isEmpty
    }

    private func normalizedPlanTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func recoverableStoredPlan(for documentPlan: NativeProjectPlan?) -> PortfolioProjectPlan? {
        guard document.isEditablePlan,
              isEmptyNativePlan(documentPlan) else {
            return nil
        }

        let populatedPlans = portfolioPlans.filter { !$0.isArchivedValue && $0.taskCount > 0 }
        let documentTitle = normalizedPlanTitle(documentPlan?.title ?? "")
        if !documentTitle.isEmpty,
           let titleMatch = populatedPlans.first(where: { normalizedPlanTitle($0.title) == documentTitle }) {
            return titleMatch
        }

        return populatedPlans.count == 1 ? populatedPlans.first : nil
    }

    private func shouldPreferStoredEditablePlan(_ storedPlan: NativeProjectPlan, over documentPlan: NativeProjectPlan?) -> Bool {
        guard !storedPlan.tasks.isEmpty || !storedPlan.resources.isEmpty || !storedPlan.assignments.isEmpty else {
            return false
        }
        guard let documentPlan else { return true }
        guard isEmptyNativePlan(documentPlan) else { return false }
        if documentPlan.portfolioID == storedPlan.portfolioID {
            return true
        }
        let documentTitle = normalizedPlanTitle(documentPlan.title)
        return !documentTitle.isEmpty && documentTitle == normalizedPlanTitle(storedPlan.title)
    }

    private func storedNativePlan(for portfolioPlan: PortfolioProjectPlan?) -> NativeProjectPlan? {
        guard let portfolioPlan else { return nil }
        return try? portfolioPlan.asNativePlan(in: modelContext)
    }

    private func preferredNativePlan(for portfolioPlan: PortfolioProjectPlan?) -> NativeProjectPlan? {
        let documentPlan = document.nativePlan
        if let storedPlan = storedNativePlan(for: portfolioPlan),
           shouldPreferStoredEditablePlan(storedPlan, over: documentPlan) {
            return storedPlan
        }
        return documentPlan ?? storedNativePlan(for: portfolioPlan)
    }

    private func normalizeEditablePlanResources(_ plan: PortfolioProjectPlan) {
        for resource in plan.resources {
            resource.accrueAt = resource.accrueAtValue
        }
    }

    private func seedNativePlanForEditableWorkspace() -> NativeProjectPlan? {
        let documentPlan = document.nativePlan
        if let recoveredPlan = recoverableStoredPlan(for: documentPlan),
           let storedPlan = storedNativePlan(for: recoveredPlan) {
            return storedPlan
        }

        if let storedPlan = preferredNativePlan(for: editablePortfolioPlan),
           shouldPreferStoredEditablePlan(storedPlan, over: document.nativePlan) {
            return storedPlan
        }

        if let nativePlan = document.nativePlan {
            return nativePlan
        }

        if let project = editableAnalysis?.project ?? store.project {
            return NativeProjectPlan(projectModel: project)
        }

        return nil
    }

    private func materializeEditableWorkspacePlan() -> PortfolioProjectPlan? {
        guard document.isEditablePlan else { return nil }

        guard var seedPlan = seedNativePlanForEditableWorkspace() else {
            let message = "Failed to materialize editable plan: missing seed data."
            editableWorkspaceError = message
            print(message)
            return nil
        }

        let documentPlan = document.nativePlan
        if let activePlanID = document.editablePortfolioID, seedPlan.portfolioID != activePlanID {
            if shouldPreferStoredEditablePlan(seedPlan, over: documentPlan) {
                document.editablePortfolioID = seedPlan.portfolioID
                selectedWorkspacePortfolioID = seedPlan.portfolioID
            } else {
                seedPlan.portfolioID = activePlanID
            }
        } else if document.editablePortfolioID == nil {
            document.editablePortfolioID = seedPlan.portfolioID
        }

        do {
            sanitizePortfolioStoreData()
            let upsertedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: seedPlan, in: modelContext)
            normalizeEditablePlanResources(upsertedPlan)
            archiveEditablePlan(seedPlan)
            return upsertedPlan
        } catch {
            let message = "Failed to materialize editable workspace plan: \(error)"
            editableWorkspaceError = message
            print(message)
            if case PortfolioProjectSynchronizerError.storeRecoveryRequired = error {
                return nil
            }
            print("Attempting repair and retrying editable plan materialization.")
            sanitizePortfolioStoreData()

            do {
                let upsertedPlan = try PortfolioProjectSynchronizer.upsert(nativePlan: seedPlan, in: modelContext)
                normalizeEditablePlanResources(upsertedPlan)
                archiveEditablePlan(seedPlan)
                editableWorkspaceError = nil
                return upsertedPlan
            } catch {
                let retryMessage = "Failed again to materialize editable workspace plan: \(error)"
                editableWorkspaceError = retryMessage
                print(retryMessage)
                return nil
            }
        }
    }

    private func sanitizePortfolioStoreData() {
        do {
            var didMutate = false

            let resourceDescriptor = FetchDescriptor<PortfolioPlanResource>()
            let resources = try modelContext.fetch(resourceDescriptor)
            for resource in resources {
                if resource.plan == nil {
                    modelContext.delete(resource)
                    didMutate = true
                    continue
                }

                let normalized = resource.accrueAtValue
                if resource.accrueAt != normalized {
                    resource.accrueAt = normalized
                    didMutate = true
                }
            }

            let taskDescriptor = FetchDescriptor<PortfolioPlanTask>()
            for task in try modelContext.fetch(taskDescriptor) where task.plan == nil {
                modelContext.delete(task)
                didMutate = true
            }

            let assignmentDescriptor = FetchDescriptor<PortfolioPlanAssignment>()
            for assignment in try modelContext.fetch(assignmentDescriptor) where assignment.task == nil {
                modelContext.delete(assignment)
                didMutate = true
            }

            let calendarDescriptor = FetchDescriptor<PortfolioPlanCalendar>()
            for calendar in try modelContext.fetch(calendarDescriptor) where calendar.plan == nil {
                modelContext.delete(calendar)
                didMutate = true
            }

            let sprintDescriptor = FetchDescriptor<PortfolioPlanSprint>()
            for sprint in try modelContext.fetch(sprintDescriptor) where sprint.plan == nil {
                modelContext.delete(sprint)
                didMutate = true
            }

            let workflowDescriptor = FetchDescriptor<PortfolioWorkflowColumn>()
            for column in try modelContext.fetch(workflowDescriptor) where column.plan == nil && column.typeWorkflow == nil {
                modelContext.delete(column)
                didMutate = true
            }

            let typeWorkflowDescriptor = FetchDescriptor<PortfolioTypeWorkflow>()
            for typeWorkflow in try modelContext.fetch(typeWorkflowDescriptor) where typeWorkflow.plan == nil {
                modelContext.delete(typeWorkflow)
                didMutate = true
            }

            let statusSnapshotDescriptor = FetchDescriptor<PortfolioStatusSnapshot>()
            for snapshot in try modelContext.fetch(statusSnapshotDescriptor) where snapshot.plan == nil {
                modelContext.delete(snapshot)
                didMutate = true
            }

            let sprintSnapshotDescriptor = FetchDescriptor<PortfolioSprintStatusSnapshot>()
            for snapshot in try modelContext.fetch(sprintSnapshotDescriptor) where snapshot.snapshot == nil {
                modelContext.delete(snapshot)
                didMutate = true
            }

            let planDescriptor = FetchDescriptor<PortfolioProjectPlan>()
            let plans = try modelContext.fetch(planDescriptor)
            for plan in plans {
                if plan.isArchived == nil {
                    plan.isArchived = false
                    didMutate = true
                }
            }

            if let documentPlan = document.nativePlan,
               isEmptyNativePlan(documentPlan) {
                let documentTitle = normalizedPlanTitle(documentPlan.title)
                let populatedReplacement = plans.first { plan in
                    plan.taskCount > 0
                        && normalizedPlanTitle(plan.title) == documentTitle
                        && plan.portfolioID != documentPlan.portfolioID
                }

                if let populatedReplacement {
                    for plan in plans where plan.portfolioID == documentPlan.portfolioID && plan.taskCount == 0 {
                        modelContext.delete(plan)
                        didMutate = true
                    }
                    document.editablePortfolioID = populatedReplacement.portfolioID
                    selectedWorkspacePortfolioID = populatedReplacement.portfolioID
                }
            }

            if didMutate {
                try modelContext.save()
            }
        } catch {
            print("Failed to sanitize persisted portfolio data: \(error)")
        }
    }

    private var showEditableWorkspaceError: Binding<Bool> {
        Binding(
            get: { editableWorkspaceError != nil },
            set: { newValue in
                if !newValue {
                    editableWorkspaceError = nil
                }
            }
        )
    }

    private func ensureEditablePortfolioPlanLoaded() {
        guard document.isEditablePlan else { return }
        if let documentPlan = document.nativePlan,
           let recoveredPlan = recoverableStoredPlan(for: documentPlan),
           let nativePlan = storedNativePlan(for: recoveredPlan) {
            normalizeEditablePlanResources(recoveredPlan)
            selectedWorkspacePortfolioID = recoveredPlan.portfolioID
            archiveEditablePlan(nativePlan)
            refreshEditableAnalysis()
            editableWorkspaceError = nil
            return
        }

        if let existingPlan = editablePortfolioPlan,
           let nativePlan = preferredNativePlan(for: existingPlan),
           shouldPreferStoredEditablePlan(nativePlan, over: document.nativePlan) {
            normalizeEditablePlanResources(existingPlan)
            selectedWorkspacePortfolioID = nativePlan.portfolioID
            archiveEditablePlan(nativePlan)
            refreshEditableAnalysis()
            editableWorkspaceError = nil
            return
        }

        if document.editablePlanSeed == nil,
           let existingPlan = editablePortfolioPlan {
            normalizeEditablePlanResources(existingPlan)
            editableWorkspaceError = nil
            return
        }
        scheduleEditableWorkspaceMaterialization(deferred: false)
    }

    private func scheduleEditableWorkspaceMaterialization(deferred: Bool = true) {
        guard document.isEditablePlan, !isMaterializingEditableWorkspace else { return }
        if document.editablePlanSeed == nil,
           let existingPlan = editablePortfolioPlan {
            normalizeEditablePlanResources(existingPlan)
            editableWorkspaceError = nil
            return
        }
        guard let seedPlan = seedNativePlanForEditableWorkspace() else { return }

        if transientEditablePortfolioPlan?.portfolioID != seedPlan.portfolioID {
            transientEditablePortfolioPlan = PortfolioProjectPlan(nativePlan: seedPlan)
        }

        isMaterializingEditableWorkspace = true
        Task { @MainActor in
            if deferred {
                try? await Task.sleep(nanoseconds: 350_000_000)
            } else {
                await Task.yield()
            }

            guard document.isEditablePlan else {
                isMaterializingEditableWorkspace = false
                return
            }

            _ = materializeEditableWorkspacePlan()
            isMaterializingEditableWorkspace = false
            refreshEditableAnalysis()
        }
    }

    private func refreshEditableWorkspaceState() {
        sanitizePortfolioStoreData()
        refreshEditableAnalysis()
        scheduleEditableWorkspaceMaterialization()
    }

    private func handleDocumentModeTask() async {
        if !document.isEditablePlan {
            if selectedWorkspacePortfolioID == nil {
                selectedWorkspacePortfolioID = defaultWorkspacePortfolioID()
            }
        }
        await handleDocumentModeChange()
    }

    private func handleViewAppear() {
        refreshCachedFlaggedTaskIDs()
        scheduleSearchSuggestionsRefresh()
        if selectedWorkspacePortfolioID == nil {
            selectedWorkspacePortfolioID = defaultWorkspacePortfolioID()
        }
    }

    private func handleNavigationNotification(_ notification: Notification) {
        if let item = notification.object as? NavigationItem {
            selectedNav = item
        }
    }

    private var editableWorkspaceAlertText: Text {
        Text(editableWorkspaceError ?? "The editable workspace could not be prepared. Open in read-only mode or re-import the file.")
    }

    private func defaultWorkspacePortfolioID() -> UUID? {
        if let recoveredPlan = recoverableStoredPlan(for: document.nativePlan) {
            return recoveredPlan.portfolioID
        }
        if let editableID = document.editablePortfolioID {
            return editableID
        }
        if let activePlanID = portfolioPlans.first(where: { !$0.isArchivedValue })?.portfolioID {
            return activePlanID
        }
        return portfolioPlans.first?.portfolioID
    }

    @ViewBuilder
    private var detailContent: some View {
        if !document.isEditablePlan && store.isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Converting MPP file...")
                    .foregroundStyle(.secondary)
            }
        } else if !document.isEditablePlan, let error = store.error {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text("Failed to load project")
                    .font(.headline)
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        } else if selectedNav == .portfolio {
            PortfolioDashboardView(activePortfolioID: workspacePortfolioBinding)
        } else if document.isEditablePlan, displayProject == nil {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.3)
                Text("Preparing plan workspace...")
                    .foregroundStyle(.secondary)
            }
        } else if let project = displayProject {
            detailView(for: selectedNav, project: project, portfolioPlan: activeDetailPortfolioPlan)
        } else {
            Text("No project loaded")
                .foregroundStyle(.secondary)
        }
    }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            SidebarView(selection: $selectedNav, showsPlanner: document.isEditablePlan)
        } detail: {
            // On macOS 26 the sidebar floats above a full-bleed detail pane
            // that only receives a leading safe-area inset. GeometryReader
            // reports the safe-area size, so pinning the content to that size
            // keeps every page's scroll canvas inside the visible viewport
            // instead of extending underneath the sidebar and off-screen.
            GeometryReader { proxy in
                detailContent
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        }
    }

    private var searchableRootView: some View {
        rootSplitView
        .searchable(text: $searchText, prompt: "Search tasks, IDs, WBS, resources, notes, or custom fields")
    }

    private var toolbarConfiguredView: some View {
        searchableRootView
        .task(id: document.editablePortfolioID) {
            await Task.yield()
            refreshEditableWorkspaceState()
        }
        .onChange(of: effectiveWorkspacePortfolioPlan?.updatedAt) { _, _ in
            refreshEditableAnalysis()
            guard document.isEditablePlan, !isMaterializingEditableWorkspace else { return }
            if let nativePlan = editableNativePlanSnapshotForArchiving() {
                archiveEditablePlan(nativePlan)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if shouldShowNativePlanSaveButton {
                    Button {
                        convertCurrentImportToNativePlan()
                    } label: {
                        Label(isSavingNativePlan ? "Saving Native Plan..." : "Save as .mppplan", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isSavingNativePlan)
                    .help("Save this imported MPP as a native .mppplan file and open it for editing.")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    togglePresentationMode()
                } label: {
                    Image(systemName: "play.rectangle.on.rectangle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .hoverHighlight()
                .help("Presentation mode: fullscreen, distraction-free executive view (⇧⌘F).")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    toggleFocusMode()
                } label: {
                    Image(systemName: isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .hoverHighlight()
                .tint(isFocusMode ? .orange : .accentColor)
                .help(isFocusMode ? "Exit focus mode and restore the sidebar." : "Enter focus mode and hide the sidebar.")
            }
        }
    }

    private var searchSuggestionsConfiguredView: AnyView {
        let baseView = toolbarConfiguredView
        return AnyView(
            baseView.searchSuggestions {
                searchSuggestionsMenuContent
            }
        )
    }

    @ViewBuilder
    private var searchSuggestionsMenuContent: some View {
        ForEach(searchSuggestionTasks) { task in
            searchSuggestionButton(for: task)
        }
    }

    private func searchSuggestionButton(for task: ProjectTask) -> some View {
        Button {
            selectedNav = .tasks
            navigateToTaskID = task.uniqueID
            searchText = ""
        } label: {
            HStack {
                searchSuggestionIcon(for: task)
                VStack(alignment: .leading) {
                    Text(task.displayName)
                        .font(.caption)
                    if let wbs = task.wbs {
                        Text(wbs)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func searchSuggestionIcon(for task: ProjectTask) -> some View {
        if task.milestone == true {
            Image(systemName: "diamond.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        } else if task.summary == true {
            Image(systemName: "folder.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
    }

    private var searchSuggestionSourceTaskCount: Int {
        currentProject?.tasks.count ?? 0
    }

    private var contentNavigationTitle: String {
        displayProject?.properties.projectTitle
        ?? currentProject?.properties.projectTitle
        ?? "Planroom"
    }

    private var appearConfiguredView: AnyView {
        AnyView(
            searchSuggestionsConfiguredView
                .onAppear(perform: handleViewAppear)
        )
    }

    private var searchRefreshConfiguredView: AnyView {
        AnyView(
            appearConfiguredView
                .onChange(of: searchText) { _, _ in
                    scheduleSearchSuggestionsRefresh()
                }
                .onChange(of: searchSuggestionSourceTaskCount) { _, _ in
                    scheduleSearchSuggestionsRefresh()
                }
                .onChange(of: flaggedTaskIDsData) { _, _ in
                    refreshCachedFlaggedTaskIDs()
                }
        )
    }

    private var documentLifecycleConfiguredView: AnyView {
        AnyView(
            searchRefreshConfiguredView
                .navigationTitle(contentNavigationTitle)
                .task(id: document.isEditablePlan) {
                    await handleDocumentModeTask()
                }
        )
    }

    private var editableLifecycleConfiguredView: AnyView {
        AnyView(
            documentLifecycleConfiguredView
                .onChange(of: document.editablePlanData) { _, _ in
                    refreshEditableAnalysis()
                    ensureEditablePortfolioPlanLoaded()
                }
                .onChange(of: workspacePortfolioID) { _, newValue in
                    if document.isEditablePlan {
                        document.editablePortfolioID = newValue
                    }
                    if newValue != nil {
                        refreshEditableAnalysis()
                    }
                }
        )
    }

    private var lifecycleConfiguredView: AnyView {
        AnyView(
            editableLifecycleConfiguredView
                .onReceive(NotificationCenter.default.publisher(for: .navigateToItem), perform: handleNavigationNotification)
        )
    }

    private var alertConfiguredView: some View {
        lifecycleConfiguredView
        .alert("Plan Edit Not Available", isPresented: showEditableWorkspaceError) {
            Button("OK", role: .cancel) {
                editableWorkspaceError = nil
            }
        } message: {
            editableWorkspaceAlertText
        }
        .alert("Document Action", isPresented: showDocumentActionMessage) {
            Button("OK", role: .cancel) {
                documentActionMessage = nil
            }
        } message: {
            Text(documentActionMessage ?? "The document action could not be completed.")
        }
    }

    var body: some View {
        alertConfiguredView
            .frame(minWidth: 1100, minHeight: 720)
            .background(WindowCloseConfigurator())
            .background(commandPaletteShortcut)
            .background(presentationShortcut)
            .overlay(alignment: .topTrailing) {
                if isPresentationMode {
                    Button {
                        togglePresentationMode()
                    } label: {
                        Label("Exit Presentation", systemImage: "xmark.circle.fill")
                            .font(.callout)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding()
                    .help("Exit presentation mode (⇧⌘F)")
                    .transition(.opacity)
                    .zIndex(400)
                }
            }
            .overlay {
                if showCommandPalette {
                    CommandPaletteView(
                        views: commandPaletteViews,
                        tasks: displayProject?.tasks ?? [],
                        onSelectView: { selectedNav = $0 },
                        onSelectTask: { taskID in
                            selectedNav = .tasks
                            navigateToTaskID = taskID
                        },
                        onDismiss: { showCommandPalette = false }
                    )
                    .transition(.opacity)
                    .zIndex(500)
                }
            }
    }

    // Hidden button carries the ⇧⌘F shortcut for Presentation Mode.
    private var presentationShortcut: some View {
        Button("") { togglePresentationMode() }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .opacity(0)
            .accessibilityHidden(true)
    }

    // Hidden button carries the ⌘K shortcut so the palette opens from anywhere
    // in the window.
    private var commandPaletteShortcut: some View {
        Button("") { showCommandPalette.toggle() }
            .keyboardShortcut("k", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private var commandPaletteViews: [NavigationItem] {
        var items: [NavigationItem] = [.portfolio, .dashboard, .executive, .summary]
        if document.isEditablePlan {
            items += [.planner, .agileBoard, .statusCenter]
        }
        items += [.tasks, .milestones, .gantt, .schedule, .timeline, .resources, .calendar,
                  .validation, .diagnostics, .dependencyExplorer, .resourceRisks, .criticalPath,
                  .earnedValue, .workload, .diff, .helpCenter]
        return items
    }

    @ViewBuilder
    private func detailView(
        for item: NavigationItem?,
        project: ProjectModel,
        portfolioPlan: PortfolioProjectPlan?
    ) -> some View {
        switch item {
        case .portfolio:
            PortfolioDashboardView(activePortfolioID: workspacePortfolioBinding)
        case .dashboard:
            DashboardView(project: project)
        case .planner:
            if let portfolioPlan {
                let initialPlan = portfolioPlan.portfolioID == document.editablePortfolioID
                    ? preferredNativePlan(for: portfolioPlan)
                    : nil
                PlanEditorView(planModel: portfolioPlan, initialPlan: initialPlan)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing editable workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                readOnlyImportUnavailableView(
                    title: "Read-Only Import",
                    description: "Convert this imported MPP to a native .mppplan document to edit tasks in the app."
                )
            }
        case .agileBoard:
            if let portfolioPlan {
                AgileBoardView(
                    planModel: portfolioPlan,
                    isFocusMode: $isFocusMode,
                    splitViewVisibility: $splitViewVisibility
                )
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing agile board workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                readOnlyImportUnavailableView(
                    title: "Read-Only Import",
                    description: "Convert this imported MPP to a native .mppplan document to manage backlog, sprints, and agile workflow in the app."
                )
            }
        case .statusCenter:
            if let portfolioPlan {
                StatusCenterView(planModel: portfolioPlan, project: project)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing status workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                readOnlyImportUnavailableView(
                    title: "Read-Only Import",
                    description: "Convert this imported MPP to a native .mppplan document to apply status updates in the app."
                )
            }
        case .executive:
            ExecutiveModeView(project: project)
        case .summary:
            ProjectSummaryView(project: project)
        case .validation:
            ProjectValidationView(
                project: project,
                resourceLeaves: portfolioPlan?.nativeResourceLeavesForUI ?? [],
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .diagnostics:
            ProjectDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .dependencyExplorer:
            DependencyGraphExplorerView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .resourceRisks:
            ResourceDiagnosticsView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .criticalPath:
            CriticalPathView(
                project: project,
                navigateToTaskID: $navigateToTaskID,
                selectedNav: $selectedNav
            )
        case .tasks:
            TaskTableView(
                tasks: project.rootTasks,
                allTasks: project.tasksByID,
                searchText: searchText,
                resources: project.resources,
                assignments: project.assignments,
                flaggedTaskIDs: flaggedTaskIDs,
                navigateToTaskID: $navigateToTaskID
            )
        case .gantt:
            GanttChartView(project: project, searchText: searchText, planModel: portfolioPlan)
        case .schedule:
            ScheduleView(project: project, searchText: searchText)
        case .milestones:
            MilestonesView(tasks: project.tasks, allTasks: project.tasksByID, searchText: searchText)
        case .resources:
            if let portfolioPlan {
                NativeResourcesEditorView(
                    planModel: portfolioPlan,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing resource workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ResourceSheetView(
                    resources: project.resources,
                    assignments: project.assignments,
                    calendars: project.calendars,
                    defaultCalendarID: project.properties.defaultCalendarUniqueId,
                    allTasks: project.tasksByID,
                    navigateToTaskID: $navigateToTaskID,
                    selectedNav: $selectedNav
                )
            }
        case .earnedValue:
            EarnedValueView(project: project)
        case .workload:
            WorkloadView(project: project, resourceLeaves: portfolioPlan?.nativeResourceLeavesForUI ?? [])
        case .calendar:
            if let portfolioPlan {
                NativeCalendarEditorView(planModel: portfolioPlan)
            } else if document.isEditablePlan {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("Preparing calendar workspace...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CalendarView(calendars: project.calendars)
            }
        case .eventsLeave:
            if let portfolioPlan {
                EventsLeaveManagerView(planModel: portfolioPlan)
            } else {
                ContentUnavailableView(
                    "Events & Leave",
                    systemImage: "calendar.badge.clock",
                    description: Text("Open an editable plan to add holidays, events, and resource leave.")
                )
            }
        case .timeline:
            TimelineView(project: project)
        case .diff:
            DiffView(project: project)
        case .helpCenter:
            AppGuideView(isEditablePlan: portfolioPlan != nil)
        case .none:
            Text("Select a view from the sidebar")
                .foregroundStyle(.secondary)
        }
    }

    private func refreshEditableAnalysis() {
        let requestID = editableAnalysisGeneration + 1
        editableAnalysisGeneration = requestID

        let nativePlan: NativeProjectPlan?
        if document.isEditablePlan,
           workspacePortfolioID == document.editablePortfolioID {
            nativePlan = preferredNativePlan(for: effectiveWorkspacePortfolioPlan ?? editablePortfolioPlan)
        } else if let editablePortfolioPlan = effectiveWorkspacePortfolioPlan {
            nativePlan = preferredNativePlan(for: editablePortfolioPlan)
        } else {
            nativePlan = document.nativePlan
        }

        guard let nativePlan else {
            editableAnalysis = nil
            isRefreshingEditableAnalysis = false
            return
        }

        isRefreshingEditableAnalysis = true
        if document.isEditablePlan {
            editableAnalysis = NativePlanAnalysis.buildPreview(from: nativePlan)
        }
        Task {
            let builtAnalysis = await NativePlanAnalysis.buildAsync(from: nativePlan)
            await MainActor.run {
                guard requestID == editableAnalysisGeneration else { return }
                editableAnalysis = builtAnalysis
                isRefreshingEditableAnalysis = false
            }
        }
    }

    private func editableNativePlanSnapshotForArchiving() -> NativeProjectPlan? {
        guard let editablePortfolioPlan = effectiveEditablePortfolioPlan else {
            return document.nativePlan
        }
        if let storedPlan = storedNativePlan(for: editablePortfolioPlan) {
            return storedPlan
        }

        let documentPlan = document.nativePlan
        if let documentPlan,
           documentPlan.tasks.isEmpty,
           documentPlan.resources.isEmpty,
           documentPlan.assignments.isEmpty {
            return nil
        }
        return documentPlan
    }

    private func shouldOpenDashboardForCurrentSelection() -> Bool {
        switch selectedNav {
        case .none, .portfolio, .planner, .agileBoard, .statusCenter:
            return true
        default:
            return false
        }
    }

    private var canConvertCurrentImportToNativePlan: Bool {
        !document.isEditablePlan && currentProject != nil
    }

    private var shouldShowNativePlanSaveButton: Bool {
        !document.isEditablePlan
    }

    private var showDocumentActionMessage: Binding<Bool> {
        Binding(
            get: { documentActionMessage != nil },
            set: { newValue in
                if !newValue {
                    documentActionMessage = nil
                }
            }
        )
    }

    @ViewBuilder
    private func readOnlyImportUnavailableView(title: String, description: String) -> some View {
        VStack(spacing: 14) {
            ContentUnavailableView(
                title,
                systemImage: "lock",
                description: Text(description)
            )

            if canConvertCurrentImportToNativePlan {
                Button {
                    convertCurrentImportToNativePlan()
                } label: {
                    Label("Convert to Native Plan", systemImage: "arrow.trianglehead.2.clockwise.rotate.90.page.on.clipboard")
                }
                .buttonStyle(.borderedProminent)
                .hoverHighlight()
            }
        }
        .topAlignedEmptyState()
    }

    @MainActor
    private func convertCurrentImportToNativePlan() {
        guard !isSavingNativePlan else { return }

        if store.isLoading {
            documentActionMessage = "The MPP file is still loading. Try saving as .mppplan again after conversion finishes."
            return
        }

        if let error = store.error {
            documentActionMessage = "The MPP file did not load, so it cannot be saved as a native plan yet: \(error)"
            return
        }

        guard let project = currentProject else {
            documentActionMessage = "There is no imported project loaded to convert."
            return
        }

        let nativePlan = NativeProjectPlan(projectModel: project)
        let panel = NSSavePanel()
        panel.title = "Save Native Plan"
        panel.prompt = "Save"
        panel.allowedContentTypes = [.mppplan]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedNativePlanFileName(for: nativePlan)

        isSavingNativePlan = true
        defer { isSavingNativePlan = false }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try nativePlan.encodedData().write(to: url, options: .atomic)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                DispatchQueue.main.async {
                    if let error {
                        documentActionMessage = "Saved the native plan, but opening it failed: \(error.localizedDescription)"
                    } else {
                        documentActionMessage = "Saved the native plan and opened it for editing."
                    }
                }
            }
        } catch {
            documentActionMessage = "Failed to save the native plan: \(error.localizedDescription)"
        }
    }

    private func suggestedNativePlanFileName(for nativePlan: NativeProjectPlan) -> String {
        let trimmedTitle = nativePlan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Converted Plan" : trimmedTitle
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return safeTitle.hasSuffix(".mppplan") ? safeTitle : "\(safeTitle).mppplan"
    }

    private func normalizedNavigationForCurrentDocument() -> NavigationItem {
        if document.isEditablePlan {
            switch selectedNav {
            case .none, .portfolio:
                return .dashboard
            case .some(let current):
                return current
            }
        }

        switch selectedNav {
        case .none, .portfolio, .planner, .agileBoard, .statusCenter:
            return .dashboard
        case .some(let current):
            return current
        }
    }

    private func handleDocumentModeChange() async {
        if document.isEditablePlan {
            store.reset()
            selectedWorkspacePortfolioID = document.editablePortfolioID
            refreshEditableAnalysis()
            selectedNav = normalizedNavigationForCurrentDocument()
            scheduleEditableWorkspaceMaterialization()
            return
        }

        editableAnalysis = nil
        let currentDocument = document
        await store.loadFromDocument(currentDocument)

        // Imported .mpp files stay read-only on open. Avoid mutating the
        // persisted portfolio workspace during launch because the viewer path
        // does not require SwiftData promotion to render the document.
        if shouldOpenDashboardForCurrentSelection() {
            selectedNav = .dashboard
        } else {
            selectedNav = normalizedNavigationForCurrentDocument()
        }
    }

    private func refreshCachedFlaggedTaskIDs() {
        cachedFlaggedTaskIDs = (try? JSONDecoder().decode(Set<Int>.self, from: flaggedTaskIDsData)) ?? []
    }

    private func toggleFocusMode() {
        let nextValue = !isFocusMode
        isFocusMode = nextValue
        splitViewVisibility = nextValue ? .detailOnly : .all
    }

    // Presentation Mode: a distraction-free executive view — hides the sidebar
    // and goes fullscreen. Toggle with ⇧⌘F.
    private func togglePresentationMode() {
        let next = !isPresentationMode
        isPresentationMode = next
        splitViewVisibility = next ? .detailOnly : .all
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            let isFullscreen = window.styleMask.contains(.fullScreen)
            if next != isFullscreen {
                window.toggleFullScreen(nil)
            }
        }
    }
}

private struct WindowCloseConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowCloseConfiguringView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowCloseConfiguringView)?.configureWindow()
    }
}

private final class WindowCloseConfiguringView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureWindow()
    }

    func configureWindow() {
        guard let window else { return }
        window.styleMask.insert(.closable)
        window.standardWindowButton(.closeButton)?.isEnabled = true
    }
}
