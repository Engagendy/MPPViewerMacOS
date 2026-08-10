import AppKit
import UniformTypeIdentifiers

/// Renders the Gantt chart as a scalable **SVG** document — true vector output
/// for executive decks and design tools, with an executive header/footer.
enum SVGExporter {

    struct GanttRow {
        let name: String
        let outlineLevel: Int
        let start: Date?
        let finish: Date?
        let isMilestone: Bool
        let isSummary: Bool
        let isCritical: Bool
        let percentComplete: Double
        let colorHex: String?
        /// Optional smaller second line under the name (e.g. type + dates).
        var subtitle: String? = nil
    }

    /// A full-height overlay band (holiday/event/leave) drawn behind the bars.
    struct Band {
        let name: String
        let start: Date
        let finish: Date
        let colorHex: String
    }

    @MainActor
    static func exportGantt(
        rows: [GanttRow],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String,
        fileName: String,
        bands: [Band] = []
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let svg = svgDocument(
            rows: rows,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            title: title,
            bands: bands,
            iconBase64: appIconBase64PNG()
        )
        try? svg.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Test hook exposing the pure SVG string builder without a save panel.
    static func svgForTesting(rows: [GanttRow], rangeStart: Date, rangeEnd: Date, pixelsPerDay: CGFloat, rowHeight: CGFloat, title: String) -> String {
        svgDocument(rows: rows, rangeStart: rangeStart, rangeEnd: rangeEnd, pixelsPerDay: pixelsPerDay, rowHeight: rowHeight, title: title)
    }

    // MARK: - Rendering

    private static let calendar = Calendar.current

    /// Base64-encoded PNG of the app icon for embedding a Planroom brand mark.
    @MainActor
    static func appIconBase64PNG(size: CGFloat = 48) -> String? {
        guard let icon = NSApp?.applicationIconImage else { return nil }
        let target = NSImage(size: NSSize(width: size, height: size))
        target.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return png.base64EncodedString()
    }

    /// A branded footer with the Planroom mark + wordmark and export stamp.
    private static func brandingFooter(y: CGFloat, xLeft: CGFloat, xRight: CGFloat, iconBase64: String?) -> String {
        var out = ""
        var textX = xLeft
        if let iconBase64 {
            out += "<image x=\"\(f(xLeft))\" y=\"\(f(y - 11))\" width=\"14\" height=\"14\" href=\"data:image/png;base64,\(iconBase64)\"/>\n"
            textX = xLeft + 18
        }
        out += text("Planroom", x: textX, y: y, size: 10, weight: "bold", fill: "#6B7280")
        let stamp = DateFormatter()
        stamp.dateStyle = .medium
        stamp.timeStyle = .short
        out += textAnchored("Exported \(stamp.string(from: Date()))", x: xRight, y: y, size: 9, fill: "#B0B0B0", anchor: "end")
        return out
    }

    private static let bandDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static func bandDateRange(_ band: Band) -> String {
        "\(bandDateFormatter.string(from: band.start)) – \(bandDateFormatter.string(from: band.finish))"
    }

    private static func days(from start: Date, to end: Date) -> Int {
        max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 1)
    }

    private static func svgDocument(
        rows: [GanttRow],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String,
        bands: [Band] = [],
        iconBase64: String? = nil
    ) -> String {
        let leftWidth: CGFloat = 260
        let titleHeight: CGFloat = 44
        let headerHeight: CGFloat = 34
        let footerHeight: CGFloat = 26
        let padding: CGFloat = 24
        let barInset: CGFloat = 4

        let totalDays = days(from: rangeStart, to: rangeEnd)
        let chartWidth = CGFloat(totalDays) * pixelsPerDay

        func x(for date: Date) -> CGFloat {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: rangeStart), to: calendar.startOfDay(for: date)).day ?? 0
            return padding + leftWidth + CGFloat(offset) * pixelsPerDay
        }
        func chipWidth(_ name: String) -> CGFloat { CGFloat(name.count) * 5.6 + 12 }

        // Pack overlapping band titles into stacked lane rows so they never
        // collide, and size the lane to fit however many rows that needs. Each
        // lane row is tall enough for the name chip plus a dates line beneath.
        let laneRowHeight: CGFloat = 30
        let laneTop = titleHeight + headerHeight
        var laneRowEnds: [CGFloat] = []
        var placedBands: [(band: Band, x1: CGFloat, w: CGFloat, chipW: CGFloat, laneRow: Int)] = []
        for band in bands.sorted(by: { x(for: $0.start) < x(for: $1.start) }) {
            let x1 = x(for: band.start)
            let x2 = x(for: band.finish) + pixelsPerDay
            let w = max(pixelsPerDay, x2 - x1)
            let cw = max(chipWidth(band.name), CGFloat(bandDateRange(band).count) * 5.4 + 4)
            let footprint = max(w, cw)
            var assigned = laneRowEnds.firstIndex(where: { x1 >= $0 }) ?? -1
            if assigned == -1 { assigned = laneRowEnds.count; laneRowEnds.append(0) }
            laneRowEnds[assigned] = x1 + footprint + 6
            placedBands.append((band, x1, w, cw, assigned))
        }
        let laneHeight: CGFloat = bands.isEmpty ? 0 : (CGFloat(laneRowEnds.count) * laneRowHeight + 8)

        let bodyTop = laneTop + laneHeight
        let width = padding * 2 + leftWidth + chartWidth
        let height = bodyTop + CGFloat(rows.count) * rowHeight + footerHeight + padding
        let bandsBottom = height - footerHeight - padding

        var body = ""

        // Background
        body += rect(x: 0, y: 0, w: width, h: height, fill: "#FFFFFF")

        // Title + export stamp
        body += text(escape(title), x: padding, y: 28, size: 18, weight: "bold", fill: "#1A1A1A")
        let stampFormatter = DateFormatter()
        stampFormatter.dateStyle = .medium
        stampFormatter.timeStyle = .short
        body += textAnchored(escape("Exported \(stampFormatter.string(from: Date()))"), x: width - padding, y: 28, size: 10, fill: "#8A8F98", anchor: "end")

        // Month header + gridlines. Labels are suppressed when they would
        // overlap the previous one (long plans exported at small zoom).
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        var currentMonth = -1
        var lastLabelRight: CGFloat = -.greatestFiniteMagnitude
        for day in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: day, to: rangeStart) else { continue }
            let month = calendar.component(.month, from: date)
            let colX = padding + leftWidth + CGFloat(day) * pixelsPerDay
            if month != currentMonth {
                currentMonth = month
                body += line(x1: colX, y1: titleHeight, x2: colX, y2: bandsBottom, stroke: "#E5E5E5", width: 0.5)
                let label = monthFormatter.string(from: date)
                let labelWidth = CGFloat(label.count) * 6.0
                if colX + 4 > lastLabelRight + 6 {
                    body += text(escape(label), x: colX + 4, y: titleHeight + 20, size: 10, fill: "#8A8F98")
                    lastLabelRight = colX + 4 + labelWidth
                }
            }
        }

        // Header separator + left column divider
        body += line(x1: padding, y1: bodyTop, x2: width - padding, y2: bodyTop, stroke: "#D0D0D0", width: 1)
        body += line(x1: padding + leftWidth, y1: titleHeight, x2: padding + leftWidth, y2: bandsBottom, stroke: "#D0D0D0", width: 1)

        // Overlay bands (holidays / events / leave). Fill spans the rows; the
        // title chip sits in the dedicated lane above the rows.
        for placed in placedBands {
            let color = placed.band.colorHex
            body += rect(x: placed.x1, y: bodyTop, w: placed.w, h: bandsBottom - bodyTop, fill: color, opacity: 0.12)
            body += line(x1: placed.x1, y1: laneTop, x2: placed.x1, y2: bandsBottom, stroke: color, width: 1)
            body += line(x1: placed.x1 + placed.w, y1: laneTop, x2: placed.x1 + placed.w, y2: bandsBottom, stroke: color, width: 1)
            let chipY = laneTop + CGFloat(placed.laneRow) * laneRowHeight + 3
            let chipW = chipWidth(placed.band.name)
            body += rect(x: placed.x1 + 2, y: chipY, w: chipW, h: 13, fill: color, opacity: 0.95, rx: 6)
            body += text(escape(placed.band.name), x: placed.x1 + 7, y: chipY + 10, size: 9, weight: "bold", fill: "#FFFFFF")
            // Dates on a second line beneath the title chip.
            body += text(escape(bandDateRange(placed.band)), x: placed.x1 + 4, y: chipY + 24, size: 9, weight: "normal", fill: color)
        }

        // Rows
        for (index, row) in rows.enumerated() {
            let rowY = bodyTop + CGFloat(index) * rowHeight
            if index % 2 == 1 {
                body += rect(x: padding, y: rowY, w: width - padding * 2, h: rowHeight, fill: "#000000", opacity: 0.02)
            }

            // Name (indented). When a subtitle is present it stacks on a
            // smaller second line so nothing gets truncated onto one line.
            let indent = CGFloat(max(0, row.outlineLevel - 1)) * 12
            let nameWeight = row.isSummary ? "bold" : "normal"
            let nameFill = row.isCritical ? "#E5484D" : "#1A1A1A"
            let nameMaxChars = Int((leftWidth - indent - 8) / 6.2)
            if let subtitle = row.subtitle, !subtitle.isEmpty {
                body += text(escape(truncate(row.name, max: nameMaxChars)), x: padding + 4 + indent, y: rowY + rowHeight * 0.46, size: 11, weight: "bold", fill: nameFill)
                body += text(escape(truncate(subtitle, max: Int((leftWidth - indent - 8) / 5.4))), x: padding + 4 + indent, y: rowY + rowHeight * 0.82, size: 9, weight: "normal", fill: "#8A8F98")
            } else {
                body += text(escape(truncate(row.name, max: nameMaxChars)), x: padding + 4 + indent, y: rowY + rowHeight * 0.68, size: 11, weight: nameWeight, fill: nameFill)
            }

            guard let start = row.start else { continue }
            let barY = rowY + barInset
            let barH = rowHeight - barInset * 2
            let color = row.colorHex ?? (row.isCritical ? "#E5484D" : "#2F6FEB")

            if row.isMilestone {
                let cx = x(for: start)
                let cy = rowY + rowHeight / 2
                let s = barH * 0.55
                let points = "\(f(cx)),\(f(cy - s)) \(f(cx + s)),\(f(cy)) \(f(cx)),\(f(cy + s)) \(f(cx - s)),\(f(cy))"
                body += "<polygon points=\"\(points)\" fill=\"\(row.colorHex ?? "#F5871F")\"/>\n"
            } else if let finish = row.finish {
                let startX = x(for: start)
                let barWidth = max(2, x(for: finish) - startX)
                if row.isSummary {
                    let bracketH = barH * 0.35
                    let bracketY = rowY + rowHeight * 0.42
                    let summaryColor = row.colorHex ?? "#8A8F98"
                    body += rect(x: startX, y: bracketY, w: barWidth, h: bracketH, fill: summaryColor, rx: 1)
                } else {
                    body += rect(x: startX, y: barY, w: barWidth, h: barH, fill: color, opacity: 0.3, rx: 3)
                    let fillWidth = barWidth * CGFloat(min(1, max(0, row.percentComplete / 100.0)))
                    if fillWidth > 0 {
                        body += rect(x: startX, y: barY, w: fillWidth, h: barH, fill: color, rx: 3)
                    }
                }
            }
        }

        // Footer — Planroom brand mark + wordmark.
        body += brandingFooter(y: height - padding + 6, xLeft: padding, xRight: width - padding, iconBase64: iconBase64)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(f(width))" height="\(f(height))" viewBox="0 0 \(f(width)) \(f(height))" font-family="-apple-system, Helvetica, Arial, sans-serif">
        \(body)</svg>
        """
    }

    // MARK: - Workload export

    struct WorkloadWeek {
        let dayOffset: Int
        let allocationPercent: Double
        let isOver: Bool
    }

    struct WorkloadLeave {
        let start: Date
        let finish: Date
        let name: String
        let colorHex: String
    }

    struct WorkloadRow {
        let name: String
        let peakPercent: Double
        let isOverAllocated: Bool
        let weeks: [WorkloadWeek]
        let leaves: [WorkloadLeave]
    }

    @MainActor
    static func exportWorkload(
        rows: [WorkloadRow],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String,
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "svg") ?? .data]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let svg = workloadDocument(
            rows: rows,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            title: title,
            iconBase64: appIconBase64PNG()
        )
        try? svg.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func workloadDocument(
        rows: [WorkloadRow],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String,
        iconBase64: String? = nil
    ) -> String {
        let leftWidth: CGFloat = 200
        let titleHeight: CGFloat = 44
        let headerHeight: CGFloat = 34
        let footerHeight: CGFloat = 26
        let padding: CGFloat = 24
        let barInset: CGFloat = 4

        let totalDays = days(from: rangeStart, to: rangeEnd)
        let chartWidth = CGFloat(totalDays) * pixelsPerDay
        let bodyTop = titleHeight + headerHeight
        let width = padding * 2 + leftWidth + chartWidth
        let height = bodyTop + CGFloat(rows.count) * rowHeight + footerHeight + padding

        func x(forDayOffset offset: Int) -> CGFloat {
            padding + leftWidth + CGFloat(offset) * pixelsPerDay
        }
        func x(for date: Date) -> CGFloat {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: rangeStart), to: calendar.startOfDay(for: date)).day ?? 0
            return padding + leftWidth + CGFloat(offset) * pixelsPerDay
        }

        var body = ""
        body += rect(x: 0, y: 0, w: width, h: height, fill: "#FFFFFF")
        body += text(escape(title + " — Resource Workload"), x: padding, y: 28, size: 18, weight: "bold", fill: "#1A1A1A")

        // Month header — labels suppressed when they'd overlap the previous one.
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        var currentMonth = -1
        var lastLabelRight: CGFloat = -.greatestFiniteMagnitude
        for day in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: day, to: rangeStart) else { continue }
            let month = calendar.component(.month, from: date)
            let colX = padding + leftWidth + CGFloat(day) * pixelsPerDay
            if month != currentMonth {
                currentMonth = month
                body += line(x1: colX, y1: titleHeight, x2: colX, y2: height - footerHeight - padding, stroke: "#E5E5E5", width: 0.5)
                let label = monthFormatter.string(from: date)
                if colX + 4 > lastLabelRight + 6 {
                    body += text(escape(label), x: colX + 4, y: titleHeight + 20, size: 10, fill: "#8A8F98")
                    lastLabelRight = colX + 4 + CGFloat(label.count) * 6.0
                }
            }
        }

        body += line(x1: padding, y1: bodyTop, x2: width - padding, y2: bodyTop, stroke: "#D0D0D0", width: 1)
        body += line(x1: padding + leftWidth, y1: titleHeight, x2: padding + leftWidth, y2: height - footerHeight - padding, stroke: "#D0D0D0", width: 1)

        for (index, row) in rows.enumerated() {
            let rowY = bodyTop + CGFloat(index) * rowHeight
            if index % 2 == 1 {
                body += rect(x: padding, y: rowY, w: width - padding * 2, h: rowHeight, fill: "#000000", opacity: 0.02)
            }

            // Name + peak
            let nameFill = row.isOverAllocated ? "#E5484D" : "#1A1A1A"
            body += text(escape(truncate(row.name, max: Int((leftWidth - 12) / 6.2))), x: padding + 4, y: rowY + rowHeight * 0.5, size: 11, weight: "bold", fill: nameFill)
            body += text(escape("Peak \(Int(row.peakPercent))%"), x: padding + 4, y: rowY + rowHeight * 0.82, size: 9, fill: "#8A8F98")

            // Leave bands (full row height, behind bars)
            for leave in row.leaves {
                let x1 = x(for: leave.start)
                let x2 = x(for: leave.finish) + pixelsPerDay
                let w = max(pixelsPerDay, x2 - x1)
                body += rect(x: x1, y: rowY + 1, w: w, h: rowHeight - 2, fill: leave.colorHex, opacity: 0.22)
                let reason = leave.name.isEmpty ? "Leave" : leave.name
                if w > 34 {
                    body += text(escape(reason), x: x1 + 4, y: rowY + rowHeight * 0.5, size: 9, weight: "bold", fill: leave.colorHex)
                }
            }

            // Capacity line at 100%
            let maxBarHeight = rowHeight - barInset * 2
            body += line(x1: padding + leftWidth, y1: rowY + barInset, x2: width - padding, y2: rowY + barInset, stroke: "#B0B0B0", width: 0.5)

            // Week allocation bars. Heights are clamped to the row so
            // over-allocated (>100%) bars never spill into the row above or the
            // date header; over-allocation is conveyed by the red fill.
            for week in row.weeks where week.allocationPercent > 0 {
                let xStart = x(forDayOffset: week.dayOffset)
                let barWidth = max(2, 7 * pixelsPerDay - 2)
                let pct = min(1.0, week.allocationPercent / 100.0)
                let barH = maxBarHeight * CGFloat(pct)
                let barY = rowY + barInset + (maxBarHeight - barH)
                let color = week.isOver ? "#E5484D" : "#3BA55D"
                body += rect(x: xStart, y: barY, w: barWidth, h: barH, fill: color, opacity: 0.8, rx: 2)
            }
        }

        body += brandingFooter(y: height - padding + 6, xLeft: padding, xRight: width - padding, iconBase64: iconBase64)

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(f(width))" height="\(f(height))" viewBox="0 0 \(f(width)) \(f(height))" font-family="-apple-system, Helvetica, Arial, sans-serif">
        \(body)</svg>
        """
    }

    // MARK: - SVG primitives

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    private static func rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, fill: String, opacity: Double = 1, rx: CGFloat = 0) -> String {
        let op = opacity < 1 ? " fill-opacity=\"\(String(format: "%.2f", opacity))\"" : ""
        let radius = rx > 0 ? " rx=\"\(f(rx))\"" : ""
        return "<rect x=\"\(f(x))\" y=\"\(f(y))\" width=\"\(f(w))\" height=\"\(f(h))\" fill=\"\(fill)\"\(op)\(radius)/>\n"
    }

    private static func line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, stroke: String, width: CGFloat) -> String {
        "<line x1=\"\(f(x1))\" y1=\"\(f(y1))\" x2=\"\(f(x2))\" y2=\"\(f(y2))\" stroke=\"\(stroke)\" stroke-width=\"\(f(width))\"/>\n"
    }

    private static func text(_ content: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: String = "normal", fill: String) -> String {
        "<text x=\"\(f(x))\" y=\"\(f(y))\" font-size=\"\(f(size))\" font-weight=\"\(weight)\" fill=\"\(fill)\">\(content)</text>\n"
    }

    private static func textAnchored(_ content: String, x: CGFloat, y: CGFloat, size: CGFloat, fill: String, anchor: String) -> String {
        "<text x=\"\(f(x))\" y=\"\(f(y))\" font-size=\"\(f(size))\" fill=\"\(fill)\" text-anchor=\"\(anchor)\">\(content)</text>\n"
    }

    private static func truncate(_ value: String, max: Int) -> String {
        guard max > 1, value.count > max else { return value }
        return String(value.prefix(max - 1)) + "…"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
