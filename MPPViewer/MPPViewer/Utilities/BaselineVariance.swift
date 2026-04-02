import SwiftUI

struct BaselineVarianceDescriptor {
    let label: String
    let color: Color
    let days: Int
}

extension ProjectTask {
    var baselineVarianceDays: Int? {
        finishVarianceDays ?? startVarianceDays
    }

    var baselineVarianceDescriptor: BaselineVarianceDescriptor? {
        guard let days = baselineVarianceDays else { return nil }
        let prefix = days > 0 ? "+" : ""
        let indicator = finishVarianceDays != nil ? "F" : (startVarianceDays != nil ? "S" : "Δ")
        let label = "\(indicator)\(prefix)\(days)d"
        let color: Color
        if days > 0 {
            color = indicator == "F" ? .red : .orange
        } else if days < 0 {
            color = .green
        } else {
            color = .gray
        }
        return BaselineVarianceDescriptor(label: label, color: color, days: days)
    }
}
