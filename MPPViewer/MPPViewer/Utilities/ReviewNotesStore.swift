import Foundation

struct ReviewNotesStore {
    static let key = "taskReviewNotes"

    static func decode(_ data: Data?) -> [Int: String] {
        guard let data, !data.isEmpty else { return [:] }
        return (try? JSONDecoder().decode([Int: String].self, from: data)) ?? [:]
    }

    static func currentNotes() -> [Int: String] {
        decode(UserDefaults.standard.data(forKey: key))
    }
}
