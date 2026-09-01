import Foundation

/// Built-in starter plans for the "New from Template" flow. Each template is a
/// compact blueprint (phases, tasks, milestones, FS dependencies with durations
/// in working days); `makePlan(anchoredTo:)` materializes it as a normal
/// `NativeProjectPlan` whose dates are computed by `PlanScheduler` from the
/// anchor date, so a template created today always starts today.
enum PlanTemplate: String, CaseIterable, Identifiable {
    case softwareRelease
    case constructionPhases
    case eventPlan
    case marketingCampaign
    case genericPhased

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .softwareRelease: return "Software Release"
        case .constructionPhases: return "Construction Phases"
        case .eventPlan: return "Event Plan"
        case .marketingCampaign: return "Marketing Campaign"
        case .genericPhased: return "Generic Phased Project"
        }
    }

    var summary: String {
        switch self {
        case .softwareRelease:
            return "Plan a software release: scope, development, code freeze, QA stabilization, and ship."
        case .constructionPhases:
            return "Classic construction sequence: permits, foundation, structure, systems, and finishing."
        case .eventPlan:
            return "Run an event end to end: budget, venue and vendors, promotion, and the event day itself."
        case .marketingCampaign:
            return "Launch a campaign: strategy, creative production, go-live, and measurement."
        case .genericPhased:
            return "A neutral four-phase skeleton: initiation, planning, execution, and closure."
        }
    }

    var systemImageName: String {
        switch self {
        case .softwareRelease: return "shippingbox"
        case .constructionPhases: return "building.2"
        case .eventPlan: return "party.popper"
        case .marketingCampaign: return "megaphone"
        case .genericPhased: return "square.stack.3d.up"
        }
    }

    /// A row in the template blueprint. `predecessors` are 1-based task IDs
    /// within the same template (row order == ID order).
    private struct TaskSpec {
        var name: String
        var level: Int = 1
        var days: Int = 1
        var milestone: Bool = false
        var predecessors: [Int] = []
    }

    /// Builds an unsaved plan from this template with all dates derived from
    /// `referenceDate` (defaults to today) by the shared scheduler.
    func makePlan(anchoredTo referenceDate: Date = Date()) -> NativeProjectPlan {
        let anchor = Calendar.current.startOfDay(for: referenceDate)
        var plan = NativeProjectPlan.empty()
        plan.title = displayName
        plan.statusDate = anchor
        plan.portfolioObjective = summary
        plan.tasks = taskSpecs.enumerated().map { index, spec in
            NativePlanTask(
                id: index + 1,
                name: spec.name,
                startDate: anchor,
                finishDate: Calendar.current.date(byAdding: .day, value: max(0, spec.days - 1), to: anchor) ?? anchor,
                durationDays: spec.milestone ? 1 : max(1, spec.days),
                outlineLevel: spec.level,
                isMilestone: spec.milestone,
                manuallyScheduled: false,
                percentComplete: 0,
                priority: 500,
                notes: "",
                predecessorTaskIDs: spec.predecessors.sorted(),
                baselineStartDate: nil,
                baselineFinishDate: nil,
                baselineDurationDays: nil,
                fixedCost: 0,
                baselineCost: nil,
                actualCost: nil,
                actualStartDate: nil,
                actualFinishDate: nil,
                constraintType: nil,
                constraintDate: nil,
                calendarUniqueID: nil,
                isActive: true,
                agileType: spec.milestone ? "Milestone" : "Story",
                boardStatus: "Backlog",
                storyPoints: nil,
                sprintID: nil,
                epicName: "",
                tags: []
            )
        }
        plan.reschedule()
        return plan
    }

    private var taskSpecs: [TaskSpec] {
        switch self {
        case .softwareRelease:
            return [
                TaskSpec(name: "Planning"),
                TaskSpec(name: "Define release scope", level: 2, days: 3),
                TaskSpec(name: "Write requirements", level: 2, days: 5, predecessors: [2]),
                TaskSpec(name: "Scope approved", level: 2, milestone: true, predecessors: [3]),
                TaskSpec(name: "Development"),
                TaskSpec(name: "Architecture & design", level: 2, days: 5, predecessors: [4]),
                TaskSpec(name: "Feature development", level: 2, days: 15, predecessors: [6]),
                TaskSpec(name: "Code freeze", level: 2, milestone: true, predecessors: [7]),
                TaskSpec(name: "Stabilization"),
                TaskSpec(name: "QA test pass", level: 2, days: 8, predecessors: [8]),
                TaskSpec(name: "Bug fixing", level: 2, days: 7, predecessors: [8]),
                TaskSpec(name: "Release candidate", level: 2, milestone: true, predecessors: [10, 11]),
                TaskSpec(name: "Release"),
                TaskSpec(name: "Release notes & docs", level: 2, days: 3, predecessors: [8]),
                TaskSpec(name: "Deploy to production", level: 2, days: 1, predecessors: [12, 14]),
                TaskSpec(name: "Release shipped", level: 2, milestone: true, predecessors: [15])
            ]
        case .constructionPhases:
            return [
                TaskSpec(name: "Pre-Construction"),
                TaskSpec(name: "Site survey", level: 2, days: 3),
                TaskSpec(name: "Permits & approvals", level: 2, days: 10, predecessors: [2]),
                TaskSpec(name: "Permits granted", level: 2, milestone: true, predecessors: [3]),
                TaskSpec(name: "Foundation"),
                TaskSpec(name: "Excavation", level: 2, days: 5, predecessors: [4]),
                TaskSpec(name: "Pour foundation", level: 2, days: 7, predecessors: [6]),
                TaskSpec(name: "Foundation cured", level: 2, milestone: true, predecessors: [7]),
                TaskSpec(name: "Structure"),
                TaskSpec(name: "Framing", level: 2, days: 15, predecessors: [8]),
                TaskSpec(name: "Roofing", level: 2, days: 7, predecessors: [10]),
                TaskSpec(name: "Systems"),
                TaskSpec(name: "Electrical rough-in", level: 2, days: 8, predecessors: [10]),
                TaskSpec(name: "Plumbing rough-in", level: 2, days: 8, predecessors: [10]),
                TaskSpec(name: "Inspection passed", level: 2, milestone: true, predecessors: [11, 13, 14]),
                TaskSpec(name: "Finishing"),
                TaskSpec(name: "Drywall & paint", level: 2, days: 10, predecessors: [15]),
                TaskSpec(name: "Fixtures & trim", level: 2, days: 7, predecessors: [17]),
                TaskSpec(name: "Final walkthrough", level: 2, milestone: true, predecessors: [18])
            ]
        case .eventPlan:
            return [
                TaskSpec(name: "Concept & Budget"),
                TaskSpec(name: "Define goals & audience", level: 2, days: 3),
                TaskSpec(name: "Set budget", level: 2, days: 2, predecessors: [2]),
                TaskSpec(name: "Budget approved", level: 2, milestone: true, predecessors: [3]),
                TaskSpec(name: "Venue & Vendors"),
                TaskSpec(name: "Shortlist venues", level: 2, days: 5, predecessors: [4]),
                TaskSpec(name: "Book venue", level: 2, days: 3, predecessors: [6]),
                TaskSpec(name: "Book catering & AV", level: 2, days: 5, predecessors: [7]),
                TaskSpec(name: "Promotion"),
                TaskSpec(name: "Design invitations", level: 2, days: 4, predecessors: [4]),
                TaskSpec(name: "Send invitations", level: 2, days: 1, predecessors: [7, 10]),
                TaskSpec(name: "Track RSVPs", level: 2, days: 10, predecessors: [11]),
                TaskSpec(name: "Event Delivery"),
                TaskSpec(name: "Final headcount to vendors", level: 2, days: 1, predecessors: [8, 12]),
                TaskSpec(name: "Run-of-show rehearsal", level: 2, days: 1, predecessors: [14]),
                TaskSpec(name: "Event day", level: 2, milestone: true, predecessors: [15]),
                TaskSpec(name: "Post-event debrief", level: 2, days: 2, predecessors: [16])
            ]
        case .marketingCampaign:
            return [
                TaskSpec(name: "Strategy"),
                TaskSpec(name: "Market research", level: 2, days: 5),
                TaskSpec(name: "Define messaging & channels", level: 2, days: 3, predecessors: [2]),
                TaskSpec(name: "Campaign brief approved", level: 2, milestone: true, predecessors: [3]),
                TaskSpec(name: "Creative"),
                TaskSpec(name: "Copywriting", level: 2, days: 5, predecessors: [4]),
                TaskSpec(name: "Design assets", level: 2, days: 7, predecessors: [4]),
                TaskSpec(name: "Creative review", level: 2, days: 2, predecessors: [6, 7]),
                TaskSpec(name: "Assets finalized", level: 2, milestone: true, predecessors: [8]),
                TaskSpec(name: "Launch"),
                TaskSpec(name: "Set up landing page & tracking", level: 2, days: 4, predecessors: [9]),
                TaskSpec(name: "Schedule social & email", level: 2, days: 2, predecessors: [9]),
                TaskSpec(name: "Campaign live", level: 2, milestone: true, predecessors: [11, 12]),
                TaskSpec(name: "Measure & Optimize"),
                TaskSpec(name: "Monitor performance", level: 2, days: 10, predecessors: [13]),
                TaskSpec(name: "Optimization sprint", level: 2, days: 5, predecessors: [15]),
                TaskSpec(name: "Campaign wrap report", level: 2, days: 2, predecessors: [16])
            ]
        case .genericPhased:
            return [
                TaskSpec(name: "Initiation"),
                TaskSpec(name: "Define objectives", level: 2, days: 3),
                TaskSpec(name: "Identify stakeholders", level: 2, days: 2, predecessors: [2]),
                TaskSpec(name: "Charter approved", level: 2, milestone: true, predecessors: [3]),
                TaskSpec(name: "Planning"),
                TaskSpec(name: "Build work breakdown", level: 2, days: 4, predecessors: [4]),
                TaskSpec(name: "Estimate & schedule", level: 2, days: 3, predecessors: [6]),
                TaskSpec(name: "Plan baselined", level: 2, milestone: true, predecessors: [7]),
                TaskSpec(name: "Execution"),
                TaskSpec(name: "Workstream A", level: 2, days: 10, predecessors: [8]),
                TaskSpec(name: "Workstream B", level: 2, days: 10, predecessors: [8]),
                TaskSpec(name: "Integration & review", level: 2, days: 4, predecessors: [10, 11]),
                TaskSpec(name: "Deliverables accepted", level: 2, milestone: true, predecessors: [12]),
                TaskSpec(name: "Closure"),
                TaskSpec(name: "Handover & documentation", level: 2, days: 3, predecessors: [13]),
                TaskSpec(name: "Lessons learned", level: 2, days: 1, predecessors: [15]),
                TaskSpec(name: "Project closed", level: 2, milestone: true, predecessors: [16])
            ]
        }
    }
}
