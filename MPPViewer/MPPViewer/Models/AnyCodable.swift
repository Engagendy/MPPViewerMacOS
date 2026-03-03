import Foundation

struct AnyCodable: Codable {
    let value: Any

    var displayString: String {
        switch value {
        case let b as Bool:
            return b ? "Yes" : "No"
        case let i as Int:
            return String(i)
        case let d as Double:
            return String(format: "%.2f", d)
        case let s as String:
            return s
        default:
            return "\(value)"
        }
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) {
            value = b
        } else if let i = try? container.decode(Int.self) {
            value = i
        } else if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = s
        } else {
            value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let b as Bool:
            try container.encode(b)
        case let i as Int:
            try container.encode(i)
        case let d as Double:
            try container.encode(d)
        case let s as String:
            try container.encode(s)
        default:
            try container.encode("\(value)")
        }
    }
}
