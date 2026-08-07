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
    }

    @MainActor
    static func exportGantt(
        rows: [GanttRow],
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

        let svg = svgDocument(
            rows: rows,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            pixelsPerDay: pixelsPerDay,
            rowHeight: rowHeight,
            title: title
        )
        try? svg.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// Test hook exposing the pure SVG string builder without a save panel.
    static func svgForTesting(rows: [GanttRow], rangeStart: Date, rangeEnd: Date, pixelsPerDay: CGFloat, rowHeight: CGFloat, title: String) -> String {
        svgDocument(rows: rows, rangeStart: rangeStart, rangeEnd: rangeEnd, pixelsPerDay: pixelsPerDay, rowHeight: rowHeight, title: title)
    }

    // MARK: - Rendering

    private static let calendar = Calendar.current

    private static func days(from start: Date, to end: Date) -> Int {
        max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 1)
    }

    private static func svgDocument(
        rows: [GanttRow],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String
    ) -> String {
        let leftWidth: CGFloat = 260
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

        func x(for date: Date) -> CGFloat {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: rangeStart), to: calendar.startOfDay(for: date)).day ?? 0
            return padding + leftWidth + CGFloat(offset) * pixelsPerDay
        }

        var body = ""

        // Background
        body += rect(x: 0, y: 0, w: width, h: height, fill: "#FFFFFF")

        // Title + export stamp
        body += text(escape(title), x: padding, y: 28, size: 18, weight: "bold", fill: "#1A1A1A")
        let stampFormatter = DateFormatter()
        stampFormatter.dateStyle = .medium
        stampFormatter.timeStyle = .short
        body += textAnchored(escape("Exported \(stampFormatter.string(from: Date()))"), x: width - padding, y: 28, size: 10, fill: "#8A8F98", anchor: "end")

        // Month header + gridlines
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        var currentMonth = -1
        for day in 0..<totalDays {
            guard let date = calendar.date(byAdding: .day, value: day, to: rangeStart) else { continue }
            let month = calendar.component(.month, from: date)
            let colX = padding + leftWidth + CGFloat(day) * pixelsPerDay
            if month != currentMonth {
                currentMonth = month
                body += line(x1: colX, y1: titleHeight, x2: colX, y2: height - footerHeight - padding, stroke: "#E5E5E5", width: 0.5)
                // Only label months with room, to avoid overlap.
                if pixelsPerDay * 28 >= 52 {
                    body += text(escape(monthFormatter.string(from: date)), x: colX + 4, y: titleHeight + 20, size: 10, fill: "#8A8F98")
                }
            }
        }

        // Header separator + left column divider
        body += line(x1: padding, y1: bodyTop, x2: width - padding, y2: bodyTop, stroke: "#D0D0D0", width: 1)
        body += line(x1: padding + leftWidth, y1: titleHeight, x2: padding + leftWidth, y2: height - footerHeight - padding, stroke: "#D0D0D0", width: 1)

        // Rows
        for (index, row) in rows.enumerated() {
            let rowY = bodyTop + CGFloat(index) * rowHeight
            if index % 2 == 1 {
                body += rect(x: padding, y: rowY, w: width - padding * 2, h: rowHeight, fill: "#000000", opacity: 0.02)
            }

            // Name (indented)
            let indent = CGFloat(max(0, row.outlineLevel - 1)) * 12
            let nameWeight = row.isSummary ? "bold" : "normal"
            let nameFill = row.isCritical ? "#E5484D" : "#1A1A1A"
            body += text(escape(truncate(row.name, max: Int((leftWidth - indent - 8) / 6.2))), x: padding + 4 + indent, y: rowY + rowHeight * 0.68, size: 11, weight: nameWeight, fill: nameFill)

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

        // Footer
        body += text("Generated by MPP Viewer", x: padding, y: height - padding + 6, size: 9, fill: "#B0B0B0")

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
