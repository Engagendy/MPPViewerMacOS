import Foundation

// MARK: - Root Model

struct ProjectModel {
    let properties: ProjectProperties
    let tasks: [ProjectTask]
    let resources: [ProjectResource]
    let assignments: [ResourceAssignment]
    let calendars: [ProjectCalendar]

    // Derived
    let rootTasks: [ProjectTask]
    let tasksByID: [Int: ProjectTask]
}

// MARK: - Project Properties (matches MPXJ "property_values")

struct ProjectProperties: Codable {
    let projectTitle: String?
    let author: String?
    let lastAuthor: String?
    let manager: String?
    let company: String?
    let startDate: String?
    let finishDate: String?
    let statusDate: String?
    let creationDate: String?
    let lastSaved: String?
    let currencySymbol: String?
    let currencyCode: String?
    let comments: String?
    let subject: String?
    let category: String?
    let keywords: String?
    let defaultCalendarUniqueId: Int?
    let shortApplicationName: String?
    let fullApplicationName: String?

    enum CodingKeys: String, CodingKey {
        case projectTitle = "project_title"
        case author
        case lastAuthor = "last_author"
        case manager
        case company
        case startDate = "start_date"
        case finishDate = "finish_date"
        case statusDate = "status_date"
        case creationDate = "creation_date"
        case lastSaved = "last_saved"
        case currencySymbol = "currency_symbol"
        case currencyCode = "currency_code"
        case comments
        case subject
        case category
        case keywords
        case defaultCalendarUniqueId = "default_calendar_unique_id"
        case shortApplicationName = "short_application_name"
        case fullApplicationName = "full_application_name"
    }
}

// MARK: - Task

final class ProjectTask: Codable, Identifiable {
    let uniqueID: Int
    let id: Int?
    let name: String?
    let wbs: String?
    let outlineLevel: Int?
    let outlineNumber: String?
    let start: String?
    let finish: String?
    let actualStart: String?
    let actualFinish: String?
    let duration: Int?          // seconds
    let actualDuration: Int?    // seconds
    let remainingDuration: Int? // seconds
    let percentComplete: Double?
    let percentWorkComplete: Double?
    let milestone: Bool?
    let summary: Bool?
    let critical: Bool?
    let cost: Double?
    let work: Int?              // seconds
    let notes: String?
    let priority: Int?
    let parentTaskUniqueID: Int?
    let constraintType: String?
    let constraintDate: String?
    let predecessors: [TaskRelation]?
    let successors: [TaskRelation]?
    let active: Bool?
    let guid: String?
    let type: String?

    // Baseline fields
    let baselineStart: String?
    let baselineFinish: String?
    let baselineDuration: Int?
    let baselineCost: Double?
    let baselineWork: Int?
    let actualCost: Double?

    // EVM fields
    let bcws: Double?
    let bcwp: Double?
    let acwp: Double?
    let cv: Double?
    let sv: Double?

    // Custom fields (decoded from extra keys like text1, number1, cost1, flag1, date1, etc.)
    var customFields: [String: AnyCodable]? = nil

    // Derived (not decoded)
    var children: [ProjectTask] = []

    var displayName: String {
        name ?? "Unnamed Task"
    }

    var durationDisplay: String {
        guard let dur = duration else { return "" }
        return DurationFormatting.formatSeconds(dur)
    }

    var percentCompleteDisplay: String {
        guard let pct = percentComplete else { return "" }
        return "\(Int(pct))%"
    }

    var startDate: Date? {
        start.flatMap { DateFormatting.parseMPXJDate($0) }
    }

    var finishDate: Date? {
        finish.flatMap { DateFormatting.parseMPXJDate($0) }
    }

    var baselineStartDate: Date? {
        baselineStart.flatMap { DateFormatting.parseMPXJDate($0) }
    }

    var baselineFinishDate: Date? {
        baselineFinish.flatMap { DateFormatting.parseMPXJDate($0) }
    }

    var hasBaseline: Bool {
        baselineStart != nil || baselineFinish != nil
    }

    var startVarianceDays: Int? {
        guard let bs = baselineStartDate, let s = startDate else { return nil }
        return Calendar.current.dateComponents([.day], from: bs, to: s).day
    }

    var finishVarianceDays: Int? {
        guard let bf = baselineFinishDate, let f = finishDate else { return nil }
        return Calendar.current.dateComponents([.day], from: bf, to: f).day
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case uniqueID = "unique_id"
        case id
        case name
        case wbs
        case outlineLevel = "outline_level"
        case outlineNumber = "outline_number"
        case start
        case finish
        case actualStart = "actual_start"
        case actualFinish = "actual_finish"
        case duration
        case actualDuration = "actual_duration"
        case remainingDuration = "remaining_duration"
        case percentComplete = "percent_complete"
        case percentWorkComplete = "percent_work_complete"
        case milestone
        case summary
        case critical
        case cost
        case work
        case notes
        case priority
        case parentTaskUniqueID = "parent_task_unique_id"
        case constraintType = "constraint_type"
        case constraintDate = "constraint_date"
        case predecessors
        case successors
        case active
        case guid
        case type
        case baselineStart = "baseline_start"
        case baselineFinish = "baseline_finish"
        case baselineDuration = "baseline_duration"
        case baselineCost = "baseline_cost"
        case baselineWork = "baseline_work"
        case actualCost = "actual_cost"
        case bcws, bcwp, acwp, cv, sv
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }

    private static let customFieldPattern = try! NSRegularExpression(pattern: "^(text|number|cost|flag|date|start|finish|duration|outline_code|enterprise_custom_field)\\d+$")

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        uniqueID = try container.decode(Int.self, forKey: .uniqueID)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        wbs = try container.decodeIfPresent(String.self, forKey: .wbs)
        outlineLevel = try container.decodeIfPresent(Int.self, forKey: .outlineLevel)
        outlineNumber = try container.decodeIfPresent(String.self, forKey: .outlineNumber)
        start = try container.decodeIfPresent(String.self, forKey: .start)
        finish = try container.decodeIfPresent(String.self, forKey: .finish)
        actualStart = try container.decodeIfPresent(String.self, forKey: .actualStart)
        actualFinish = try container.decodeIfPresent(String.self, forKey: .actualFinish)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        actualDuration = try container.decodeIfPresent(Int.self, forKey: .actualDuration)
        remainingDuration = try container.decodeIfPresent(Int.self, forKey: .remainingDuration)
        percentComplete = try container.decodeIfPresent(Double.self, forKey: .percentComplete)
        percentWorkComplete = try container.decodeIfPresent(Double.self, forKey: .percentWorkComplete)
        milestone = try container.decodeIfPresent(Bool.self, forKey: .milestone)
        summary = try container.decodeIfPresent(Bool.self, forKey: .summary)
        critical = try container.decodeIfPresent(Bool.self, forKey: .critical)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost)
        work = try container.decodeIfPresent(Int.self, forKey: .work)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        parentTaskUniqueID = try container.decodeIfPresent(Int.self, forKey: .parentTaskUniqueID)
        constraintType = try container.decodeIfPresent(String.self, forKey: .constraintType)
        constraintDate = try container.decodeIfPresent(String.self, forKey: .constraintDate)
        predecessors = try container.decodeIfPresent([TaskRelation].self, forKey: .predecessors)
        successors = try container.decodeIfPresent([TaskRelation].self, forKey: .successors)
        active = try container.decodeIfPresent(Bool.self, forKey: .active)
        guid = try container.decodeIfPresent(String.self, forKey: .guid)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        baselineStart = try container.decodeIfPresent(String.self, forKey: .baselineStart)
        baselineFinish = try container.decodeIfPresent(String.self, forKey: .baselineFinish)
        baselineDuration = try container.decodeIfPresent(Int.self, forKey: .baselineDuration)
        baselineCost = try container.decodeIfPresent(Double.self, forKey: .baselineCost)
        baselineWork = try container.decodeIfPresent(Int.self, forKey: .baselineWork)
        actualCost = try container.decodeIfPresent(Double.self, forKey: .actualCost)
        bcws = try container.decodeIfPresent(Double.self, forKey: .bcws)
        bcwp = try container.decodeIfPresent(Double.self, forKey: .bcwp)
        acwp = try container.decodeIfPresent(Double.self, forKey: .acwp)
        cv = try container.decodeIfPresent(Double.self, forKey: .cv)
        sv = try container.decodeIfPresent(Double.self, forKey: .sv)

        // Decode custom fields from remaining keys
        let knownKeys = Set(CodingKeys.allCases.map { $0.rawValue })
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        var customs: [String: AnyCodable] = [:]

        for key in dynamicContainer.allKeys {
            guard !knownKeys.contains(key.stringValue) else { continue }
            let range = NSRange(key.stringValue.startIndex..., in: key.stringValue)
            if Self.customFieldPattern.firstMatch(in: key.stringValue, range: range) != nil {
                if let val = try? dynamicContainer.decode(AnyCodable.self, forKey: key) {
                    customs[key.stringValue] = val
                }
            }
        }

        customFields = customs.isEmpty ? nil : customs
    }
}

// MARK: - Task Relation (matches MPXJ predecessor format)

struct TaskRelation: Codable, Identifiable {
    var id: String { "\(taskUniqueID ?? uniqueID ?? 0)-\(type ?? "FS")" }

    let uniqueID: Int?
    let taskUniqueID: Int?
    let type: String?  // FS, SS, FF, SF
    let lag: Int?      // seconds

    /// The unique ID of the related task
    var targetTaskUniqueID: Int {
        taskUniqueID ?? uniqueID ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case taskUniqueID = "task_unique_id"
        case type
        case lag
    }
}

// MARK: - Resource

struct ProjectResource: Codable, Identifiable {
    let uniqueID: Int?
    let id: Int?
    let name: String?
    let type: String?
    let maxUnits: Double?
    let standardRate: Double?
    let overtimeRate: Double?
    let costPerUse: Double?
    let emailAddress: String?
    let group: String?
    let initials: String?
    let notes: String?
    let calendarUniqueID: Int?
    let accrueAt: String?
    let active: Bool?
    let guid: String?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case id
        case name
        case type
        case maxUnits = "max_units"
        case standardRate = "standard_rate"
        case overtimeRate = "overtime_rate"
        case costPerUse = "cost_per_use"
        case emailAddress = "email_address"
        case group
        case initials
        case notes
        case calendarUniqueID = "calendar_unique_id"
        case accrueAt = "accrue_at"
        case active
        case guid
    }
}

// MARK: - Resource Assignment

struct ResourceAssignment: Codable, Identifiable {
    var id: Int { uniqueID ?? 0 }

    let uniqueID: Int?
    let taskUniqueID: Int?
    let resourceUniqueID: Int?
    let assignmentUnits: Double?
    let work: Int?          // seconds
    let actualWork: Int?    // seconds
    let remainingWork: Int? // seconds
    let start: String?
    let finish: String?
    let cost: Double?
    let guid: String?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case taskUniqueID = "task_unique_id"
        case resourceUniqueID = "resource_unique_id"
        case assignmentUnits = "assignment_units"
        case work
        case actualWork = "actual_work"
        case remainingWork = "remaining_work"
        case start
        case finish
        case cost
        case guid
    }
}

// MARK: - Calendar (matches MPXJ day-based structure)

struct ProjectCalendar: Codable, Identifiable {
    var id: String { name ?? uniqueID.map(String.init) ?? UUID().uuidString }

    let uniqueID: Int?
    let name: String?
    let parentUniqueID: Int?
    let type: String?
    let personal: Bool?

    let sunday: CalendarDayInfo?
    let monday: CalendarDayInfo?
    let tuesday: CalendarDayInfo?
    let wednesday: CalendarDayInfo?
    let thursday: CalendarDayInfo?
    let friday: CalendarDayInfo?
    let saturday: CalendarDayInfo?

    let exceptions: [CalendarException]?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case name
        case parentUniqueID = "parent_unique_id"
        case type
        case personal
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday
        case exceptions
    }

    /// Returns whether a given weekday (1=Sunday, 7=Saturday) is a working day.
    /// Does NOT resolve parent calendars — use `resolvedIsWorkingDay` for that.
    func isWorkingDay(weekday: Int) -> Bool {
        let dayInfo = dayForWeekday(weekday)
        guard let dayInfo else { return weekday >= 2 && weekday <= 6 }
        if dayInfo.isDefault { return weekday >= 2 && weekday <= 6 }
        return dayInfo.isWorking
    }

    /// Returns the working status for a weekday, resolving through parent calendars.
    func resolvedIsWorkingDay(weekday: Int, calendarsByID: [Int: ProjectCalendar]) -> Bool {
        let dayInfo = dayForWeekday(weekday)

        // If we have a definite answer (working or non_working), use it
        if let dayInfo, !dayInfo.isDefault {
            return dayInfo.isWorking
        }

        // Type is "default" or nil — inherit from parent
        if let parentID = parentUniqueID, let parent = calendarsByID[parentID] {
            return parent.resolvedIsWorkingDay(weekday: weekday, calendarsByID: calendarsByID)
        }

        // No parent — fallback to Mon-Fri
        return weekday >= 2 && weekday <= 6
    }

    /// Returns the working hours for a weekday, resolving through parent calendars.
    func resolvedHours(weekday: Int, calendarsByID: [Int: ProjectCalendar]) -> [CalendarHours]? {
        let dayInfo = dayForWeekday(weekday)

        if let dayInfo, !dayInfo.isDefault {
            return dayInfo.hours
        }

        if let parentID = parentUniqueID, let parent = calendarsByID[parentID] {
            return parent.resolvedHours(weekday: weekday, calendarsByID: calendarsByID)
        }

        return nil
    }

    func dayForWeekday(_ weekday: Int) -> CalendarDayInfo? {
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return nil
        }
    }
}

struct CalendarDayInfo: Codable {
    let type: String?    // "working", "non_working", "default"
    let hours: [CalendarHours]?

    var isWorking: Bool {
        type?.lowercased() == "working"
    }

    var isDefault: Bool {
        type == nil || type?.lowercased() == "default"
    }
}

struct CalendarHours: Codable {
    let from: String?
    let to: String?
}

struct CalendarException: Codable, Identifiable {
    var id: String { name ?? "\(from ?? "")-\(to ?? "")" }

    let name: String?
    let from: String?
    let to: String?
    let type: String?  // "non_working", "working"

    var isWorking: Bool {
        type == "working"
    }

    var fromDate: Date? {
        from.flatMap { DateFormatting.parseSimpleDate($0) }
    }

    var toDate: Date? {
        to.flatMap { DateFormatting.parseSimpleDate($0) }
    }
}

// MARK: - Raw JSON Structure (matches MPXJ output)

struct MPXJOutput: Codable {
    let propertyValues: ProjectProperties?
    let tasks: [ProjectTask]?
    let resources: [ProjectResource]?
    let assignments: [ResourceAssignment]?
    let calendars: [ProjectCalendar]?

    enum CodingKeys: String, CodingKey {
        case propertyValues = "property_values"
        case tasks
        case resources
        case assignments
        case calendars
    }
}
