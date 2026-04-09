import Foundation

enum ReviewStatus: String, Codable, CaseIterable, Identifiable {
    case notReviewed = "Not Reviewed"
    case inReview = "In Review"
    case waiting = "Waiting"
    case resolved = "Resolved"

    var id: String { rawValue }

    var isResolved: Bool {
        self == .resolved
    }
}

struct TaskReviewAnnotation: Codable {
    var note: String
    var status: ReviewStatus
    var needsFollowUp: Bool
    var updatedAt: Date?

    init(
        note: String = "",
        status: ReviewStatus = .notReviewed,
        needsFollowUp: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.note = note
        self.status = status
        self.needsFollowUp = needsFollowUp
        self.updatedAt = updatedAt
    }

    var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasContent: Bool {
        !trimmedNote.isEmpty || status != .notReviewed || needsFollowUp
    }

    var isUnresolved: Bool {
        hasContent && (!status.isResolved || needsFollowUp)
    }
}

struct ReviewNotesStore {
    static let key = "taskReviewNotes"

    static func decode(_ data: Data?) -> [Int: String] {
        decodeAnnotations(data).compactMapValues { annotation in
            annotation.trimmedNote.isEmpty ? nil : annotation.note
        }
    }

    static func decodeAnnotations(_ data: Data?) -> [Int: TaskReviewAnnotation] {
        guard let data, !data.isEmpty else { return [:] }
        let decoder = JSONDecoder()
        if let annotations = try? decoder.decode([Int: TaskReviewAnnotation].self, from: data) {
            return annotations
        }
        if let legacyNotes = try? decoder.decode([Int: String].self, from: data) {
            return legacyNotes.mapValues { TaskReviewAnnotation(note: $0) }
        }
        return [:]
    }

    static func encodeAnnotations(_ annotations: [Int: TaskReviewAnnotation]) -> Data {
        let pruned = annotations.filter { $0.value.hasContent }
        let encoder = JSONEncoder()
        return (try? encoder.encode(pruned)) ?? Data()
    }

    static func currentNotes() -> [Int: String] {
        decode(UserDefaults.standard.data(forKey: key))
    }

    static func currentAnnotations() -> [Int: TaskReviewAnnotation] {
        decodeAnnotations(UserDefaults.standard.data(forKey: key))
    }
}
