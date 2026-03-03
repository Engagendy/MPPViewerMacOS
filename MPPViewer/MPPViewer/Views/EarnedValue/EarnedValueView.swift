import SwiftUI
import Charts

struct EarnedValueView: View {
    let project: ProjectModel

    @State private var projectMetrics: EVMMetrics?
    @State private var taskMetrics: [(task: ProjectTask, metrics: EVMMetrics)] = []

    private var statusDate: Date {
        if let sd = project.properties.statusDate {
            return DateFormatting.parseMPXJDate(sd) ?? Date()
        }
        return Date()
    }

    var body: some View {
        Group {
            if let metrics = projectMetrics {
                content(metrics: metrics)
            } else {
                ProgressView("Computing EVM...")
            }
        }
        .task {
            let pm = EVMCalculator.projectMetrics(tasks: project.tasks, statusDate: statusDate)
            let tm = project.tasks
                .filter { $0.summary != true }
                .map { (task: $0, metrics: EVMCalculator.compute(for: $0, statusDate: statusDate)) }
                .filter { $0.metrics.bac > 0 }
            projectMetrics = pm
            taskMetrics = tm
        }
    }

    private func content(metrics: EVMMetrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // KPI Cards
                Text("Earned Value Analysis")
                    .font(.headline)

                if metrics.bac == 0 {
                    ContentUnavailableView(
                        "No Cost Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("This project has no baseline cost data for EVM analysis.")
                    )
                } else {
                    kpiCards(metrics: metrics)
                    sCurveChart(metrics: metrics)
                    taskTable()
                }
            }
            .padding()
        }
    }

    // MARK: - KPI Cards

    private func kpiCards(metrics: EVMMetrics) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            evmKPICard(
                title: "CPI",
                value: String(format: "%.2f", metrics.cpi),
                subtitle: "Cost Performance Index",
                icon: "dollarsign.circle.fill",
                isHealthy: metrics.cpi >= 1.0
            )
            evmKPICard(
                title: "SPI",
                value: String(format: "%.2f", metrics.spi),
                subtitle: "Schedule Performance Index",
                icon: "clock.fill",
                isHealthy: metrics.spi >= 1.0
            )
            evmKPICard(
                title: "EAC",
                value: formatCurrency(metrics.eac),
                subtitle: "Estimate at Completion",
                icon: "chart.line.uptrend.xyaxis",
                isHealthy: metrics.eac <= metrics.bac
            )
            evmKPICard(
                title: "VAC",
                value: formatCurrency(metrics.vac),
                subtitle: "Variance at Completion",
                icon: "plusminus.circle.fill",
                isHealthy: metrics.vac >= 0
            )
        }
    }

    private func evmKPICard(title: String, value: String, subtitle: String, icon: String, isHealthy: Bool) -> some View {
        KPICard(
            title: title,
            value: value,
            subtitle: subtitle,
            icon: icon,
            color: isHealthy ? .green : .red
        )
    }

    // MARK: - S-Curve Chart

    private func sCurveChart(metrics: EVMMetrics) -> some View {
        GroupBox("S-Curve") {
            VStack(alignment: .leading, spacing: 8) {
                let data = buildSCurveData(metrics: metrics)

                if data.isEmpty {
                    Text("Insufficient data for S-curve chart.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding()
                } else {
                    Chart(data) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(by: .value("Series", point.series))
                    }
                    .chartForegroundStyleScale([
                        "PV (Planned)": Color.blue,
                        "EV (Earned)": Color.green,
                        "AC (Actual)": Color.red,
                    ])
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 250)
                    .padding(4)
                }
            }
        }
    }

    private struct SCurvePoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let series: String
    }

    private func buildSCurveData(metrics: EVMMetrics) -> [SCurvePoint] {
        let allStarts = project.tasks.compactMap { $0.baselineStartDate ?? $0.startDate }
        let allFinishes = project.tasks.compactMap { $0.baselineFinishDate ?? $0.finishDate }
        guard let projectStart = allStarts.min(), let projectFinish = allFinishes.max() else { return [] }

        var data: [SCurvePoint] = []
        let calendar = Calendar.current
        let totalDays = max(1, calendar.dateComponents([.day], from: projectStart, to: projectFinish).day ?? 1)
        let step = max(1, totalDays / 20) // ~20 data points

        for dayOffset in stride(from: 0, through: totalDays, by: step) {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: projectStart) else { continue }

            // Cumulative PV up to this date
            var cumPV: Double = 0
            var cumEV: Double = 0
            var cumAC: Double = 0

            for task in project.tasks where task.summary != true {
                let bac = task.baselineCost ?? task.cost ?? 0
                guard bac > 0 else { continue }

                let plannedPct = EVMCalculator.computePlannedPercent(
                    baselineStart: task.baselineStartDate ?? task.startDate,
                    baselineFinish: task.baselineFinishDate ?? task.finishDate,
                    statusDate: date
                )
                cumPV += bac * plannedPct

                // EV and AC only up to status date
                if date <= statusDate {
                    let earnedPct = min(plannedPct, (task.percentComplete ?? 0) / 100.0)
                    cumEV += bac * earnedPct
                    cumAC += (task.actualCost ?? bac * earnedPct)
                }
            }

            data.append(SCurvePoint(date: date, value: cumPV, series: "PV (Planned)"))
            if date <= statusDate {
                data.append(SCurvePoint(date: date, value: cumEV, series: "EV (Earned)"))
                data.append(SCurvePoint(date: date, value: cumAC, series: "AC (Actual)"))
            }
        }

        return data
    }

    // MARK: - Task EVM Table

    private func taskTable() -> some View {
        GroupBox("Task-Level EVM") {
            if taskMetrics.isEmpty {
                Text("No tasks with cost data.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .padding()
            } else {
                Table(of: TaskEVMRow.self) {
                    TableColumn("Task") { row in
                        Text(row.name).lineLimit(1)
                    }
                    .width(min: 150, ideal: 250)

                    TableColumn("BAC") { row in
                        Text(formatCurrency(row.bac)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("PV") { row in
                        Text(formatCurrency(row.pv)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("EV") { row in
                        Text(formatCurrency(row.ev)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("AC") { row in
                        Text(formatCurrency(row.ac)).monospacedDigit()
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("CV") { row in
                        Text(formatCurrency(row.cv))
                            .monospacedDigit()
                            .foregroundStyle(row.cv >= 0 ? .green : .red)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("SV") { row in
                        Text(formatCurrency(row.sv))
                            .monospacedDigit()
                            .foregroundStyle(row.sv >= 0 ? .green : .red)
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("CPI") { row in
                        Text(String(format: "%.2f", row.cpi))
                            .monospacedDigit()
                            .foregroundStyle(row.cpi >= 1.0 ? .green : .red)
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("SPI") { row in
                        Text(String(format: "%.2f", row.spi))
                            .monospacedDigit()
                            .foregroundStyle(row.spi >= 1.0 ? .green : .red)
                    }
                    .width(min: 50, ideal: 60)
                } rows: {
                    ForEach(taskMetrics.map { TaskEVMRow(task: $0.task, metrics: $0.metrics) }) { row in
                        TableRow(row)
                    }
                }
                .frame(minHeight: 200)
            }
        }
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Table Row Model

private struct TaskEVMRow: Identifiable {
    let id: Int
    let name: String
    let bac: Double
    let pv: Double
    let ev: Double
    let ac: Double
    let cv: Double
    let sv: Double
    let cpi: Double
    let spi: Double

    init(task: ProjectTask, metrics: EVMMetrics) {
        self.id = task.uniqueID
        self.name = task.displayName
        self.bac = metrics.bac
        self.pv = metrics.pv
        self.ev = metrics.ev
        self.ac = metrics.ac
        self.cv = metrics.cv
        self.sv = metrics.sv
        self.cpi = metrics.cpi
        self.spi = metrics.spi
    }
}
