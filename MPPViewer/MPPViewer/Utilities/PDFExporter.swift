import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum PDFExporter {

    /// Formatted timestamp for file names (no special characters).
    static var fileNameTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: Date())
    }

    /// Formatted timestamp for display inside PDFs.
    static var displayTimestamp: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }

    /// Fallback bitmap path: export a SwiftUI view (including Canvas) to PDF
    /// via NSHostingView capture. Prefer `exportGanttVectorPDF` for Gantt-style
    /// content; this remains only for charts without a vector renderer (e.g.
    /// the workload heat bars).
    @MainActor
    static func exportGanttToPDF<V: View>(
        view: V,
        contentSize: CGSize,
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render the SwiftUI view (including Canvas) to a bitmap via NSHostingView
        let hostingView = NSHostingView(rootView: view.frame(width: contentSize.width, height: contentSize.height))
        hostingView.frame = CGRect(origin: .zero, size: contentSize)
        hostingView.appearance = NSAppearance(named: .aqua)

        // Force display preparation without recursively forcing layout during an active layout pass.
        hostingView.needsLayout = true
        hostingView.displayIfNeeded()

        // Capture to bitmap
        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else { return }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)

        guard let cgImage = bitmapRep.cgImage else { return }

        // Write to PDF — landscape letter pages
        let pageWidth: CGFloat = 792   // 11 inches at 72 dpi
        let pageHeight: CGFloat = 612  // 8.5 inches at 72 dpi
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)

        // Scale image to fit page width
        let scale = min(1.0, pageWidth / imageWidth)
        let scaledWidth = imageWidth * scale
        let scaledHeight = imageHeight * scale
        let pagesNeeded = max(1, Int(ceil(scaledHeight / pageHeight)))

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: pageHeight))
        guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }

        for page in 0..<pagesNeeded {
            pdfContext.beginPDFPage(nil)

            // PDF coordinate system: origin at bottom-left, y goes up
            // We want to draw the image top-down across pages
            let yOffsetInImage = CGFloat(page) * pageHeight / scale
            let remainingHeight = imageHeight - yOffsetInImage
            let drawHeight = min(pageHeight / scale, remainingHeight)

            // Crop a horizontal strip from the image for this page
            let cropRect = CGRect(
                x: 0,
                y: yOffsetInImage,
                width: imageWidth,
                height: drawHeight
            )

            if let croppedImage = cgImage.cropping(to: cropRect) {
                let drawRect = CGRect(
                    x: 0,
                    y: pageHeight - drawHeight * scale,
                    width: scaledWidth,
                    height: drawHeight * scale
                )
                pdfContext.draw(croppedImage, in: drawRect)
            }

            drawBrandingFooter(in: pdfContext, pageWidth: pageWidth)

            pdfContext.endPDFPage()
        }

        pdfContext.closePDF()
    }

    /// Draws a Planroom brand mark + wordmark along the bottom of a PDF page.
    @MainActor
    private static func drawBrandingFooter(in ctx: CGContext, pageWidth: CGFloat) {
        let footerHeight: CGFloat = 26
        // White strip so the branding stays legible over chart content.
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: footerHeight))
        ctx.restoreGState()

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        var textX: CGFloat = 16
        if let icon = NSApp?.applicationIconImage {
            icon.draw(in: CGRect(x: 16, y: 5, width: 16, height: 16))
            textX = 38
        }
        let brand: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        NSAttributedString(string: "Planroom", attributes: brand).draw(at: CGPoint(x: textX, y: 7))

        let stampFormatter = DateFormatter()
        stampFormatter.dateStyle = .medium
        stampFormatter.timeStyle = .short
        let stamp: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let stampString = NSAttributedString(string: "Exported \(stampFormatter.string(from: Date()))", attributes: stamp)
        let stampSize = stampString.size()
        stampString.draw(at: CGPoint(x: pageWidth - stampSize.width - 16, y: 8))

        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Task List PDF Export

    /// Export a task list as a clean vector PDF table.
    @MainActor
    static func exportTaskListToPDF(
        tasks: [ProjectTask],
        allTasks: [Int: ProjectTask],
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Page setup — landscape letter
        let pageWidth: CGFloat = 792
        let pageHeight: CGFloat = 612
        let margin: CGFloat = 40
        let usableWidth = pageWidth - margin * 2
        let rowHeight: CGFloat = 18
        let headerHeight: CGFloat = 24
        let titleHeight: CGFloat = 36

        // Column definitions: (title, width fraction, alignment)
        struct Col {
            let title: String
            let widthFraction: CGFloat
            let alignment: CTTextAlignment
        }
        let columns: [Col] = [
            Col(title: "ID", widthFraction: 0.05, alignment: .right),
            Col(title: "WBS", widthFraction: 0.07, alignment: .left),
            Col(title: "Name", widthFraction: 0.38, alignment: .left),
            Col(title: "Duration", widthFraction: 0.10, alignment: .right),
            Col(title: "Start", widthFraction: 0.12, alignment: .left),
            Col(title: "Finish", widthFraction: 0.12, alignment: .left),
            Col(title: "% Done", widthFraction: 0.08, alignment: .right),
            Col(title: "Predecessors", widthFraction: 0.08, alignment: .left),
        ]

        // Build row data
        struct RowData {
            let values: [String]
            let isSummary: Bool
            let isMilestone: Bool
            let isCritical: Bool
            let indent: Int
        }

        func buildRows(_ taskList: [ProjectTask]) -> [RowData] {
            var rows: [RowData] = []
            for task in taskList {
                let predText: String = {
                    guard let preds = task.predecessors, !preds.isEmpty else { return "" }
                    return preds.compactMap { rel -> String? in
                        guard let predTask = allTasks[rel.targetTaskUniqueID] else { return nil }
                        let taskID = predTask.id.map(String.init) ?? "\(rel.targetTaskUniqueID)"
                        let suffix = rel.type == "FS" ? "" : (rel.type ?? "")
                        return taskID + suffix
                    }.joined(separator: ", ")
                }()

                let values = [
                    task.id.map(String.init) ?? "",
                    task.wbs ?? "",
                    task.displayName,
                    task.durationDisplay,
                    DateFormatting.shortDate(task.start),
                    DateFormatting.shortDate(task.finish),
                    task.percentCompleteDisplay,
                    predText,
                ]
                rows.append(RowData(
                    values: values,
                    isSummary: task.summary == true,
                    isMilestone: task.milestone == true,
                    isCritical: task.critical == true,
                    indent: max(0, (task.outlineLevel ?? 1) - 1)
                ))
                if !task.children.isEmpty {
                    rows.append(contentsOf: buildRows(task.children))
                }
            }
            return rows
        }

        let rows = buildRows(tasks)

        // Fonts
        let headerFont = NSFont.boldSystemFont(ofSize: 9)
        let bodyFont = NSFont.systemFont(ofSize: 8)
        let boldBodyFont = NSFont.boldSystemFont(ofSize: 8)
        let titleFont = NSFont.boldSystemFont(ofSize: 14)

        // Word-wrap the Name column instead of truncating; rows grow to fit.
        let nameParagraph = NSMutableParagraphStyle()
        nameParagraph.lineBreakMode = .byWordWrapping

        let contentStartY = pageHeight - margin - titleHeight
        let bottomLimit = margin + 12
        let nameColWidth = usableWidth * columns[2].widthFraction - 8

        func nameAttributed(_ row: RowData) -> NSAttributedString {
            var text = row.values[2]
            if row.indent > 0 {
                let prefix = String(repeating: "    ", count: row.indent)
                let marker = row.isMilestone ? "\u{25C6} " : ""
                text = prefix + marker + text
            } else if row.isMilestone {
                text = "\u{25C6} " + text
            }
            let font = row.isSummary ? boldBodyFont : bodyFont
            let color: NSColor = row.isCritical ? .systemRed : .labelColor
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: nameParagraph
            ])
        }

        func heightForRow(_ row: RowData) -> CGFloat {
            let framesetter = CTFramesetterCreateWithAttributedString(nameAttributed(row))
            let size = CTFramesetterSuggestFrameSizeWithConstraints(
                framesetter,
                CFRange(location: 0, length: 0),
                nil,
                CGSize(width: nameColWidth, height: .greatestFiniteMagnitude),
                nil
            )
            return max(rowHeight, ceil(size.height) + 6)
        }

        let rowHeights = rows.map(heightForRow)

        // Paginate by accumulating variable row heights.
        var pages: [[Int]] = []
        var current: [Int] = []
        let pageBodyHeight = contentStartY - headerHeight - bottomLimit
        var available = pageBodyHeight
        for (idx, h) in rowHeights.enumerated() {
            if h > available, !current.isEmpty {
                pages.append(current)
                current = []
                available = pageBodyHeight
            }
            current.append(idx)
            available -= h
        }
        if !current.isEmpty { pages.append(current) }
        if pages.isEmpty { pages = [[]] }
        let totalPages = pages.count

        var mediaBox = CGRect(origin: .zero, size: CGSize(width: pageWidth, height: pageHeight))
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }

        for (page, pageRows) in pages.enumerated() {
            ctx.beginPDFPage(nil)

            // Title
            let titleText = fileName.replacingOccurrences(of: ".pdf", with: "")
            let titleStr = NSAttributedString(string: titleText,
                attributes: [.font: titleFont, .foregroundColor: NSColor.labelColor])
            let titleLine = CTLineCreateWithAttributedString(titleStr)
            ctx.textPosition = CGPoint(x: margin, y: pageHeight - margin - 16)
            CTLineDraw(titleLine, ctx)

            // Export date/time — right-aligned on title row
            let exportDateStr = NSAttributedString(string: "Exported: \(displayTimestamp)",
                attributes: [.font: bodyFont, .foregroundColor: NSColor.secondaryLabelColor])
            let exportDateLine = CTLineCreateWithAttributedString(exportDateStr)
            let exportDateWidth = CTLineGetTypographicBounds(exportDateLine, nil, nil, nil)
            ctx.textPosition = CGPoint(x: pageWidth - margin - exportDateWidth, y: pageHeight - margin - 16)
            CTLineDraw(exportDateLine, ctx)

            // Page number
            let pageStr = NSAttributedString(string: "Page \(page + 1) of \(totalPages)",
                attributes: [.font: bodyFont, .foregroundColor: NSColor.secondaryLabelColor])
            let pageLine = CTLineCreateWithAttributedString(pageStr)
            let pageLineWidth = CTLineGetTypographicBounds(pageLine, nil, nil, nil)
            ctx.textPosition = CGPoint(x: pageWidth - margin - pageLineWidth, y: margin - 12)
            CTLineDraw(pageLine, ctx)

            var y = contentStartY

            // Header row background
            ctx.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
            ctx.fill(CGRect(x: margin, y: y - headerHeight, width: usableWidth, height: headerHeight))

            // Header text
            var xOffset: CGFloat = margin
            for col in columns {
                let colWidth = usableWidth * col.widthFraction
                let attrStr = NSAttributedString(string: col.title,
                    attributes: [.font: headerFont, .foregroundColor: NSColor.labelColor])
                let line = CTLineCreateWithAttributedString(attrStr)
                let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                let textX = col.alignment == .right ? xOffset + colWidth - CGFloat(lineWidth) - 4 : xOffset + 4
                ctx.textPosition = CGPoint(x: textX, y: y - headerHeight + 7)
                CTLineDraw(line, ctx)
                xOffset += colWidth
            }

            ctx.setStrokeColor(NSColor.separatorColor.cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: margin, y: y - headerHeight))
            ctx.addLine(to: CGPoint(x: margin + usableWidth, y: y - headerHeight))
            ctx.strokePath()

            y -= headerHeight

            // Data rows
            for (localIdx, rowIdx) in pageRows.enumerated() {
                let row = rows[rowIdx]
                let h = rowHeights[rowIdx]
                let rowY = y - h

                if localIdx % 2 == 1 {
                    ctx.setFillColor(NSColor.black.withAlphaComponent(0.03).cgColor)
                    ctx.fill(CGRect(x: margin, y: rowY, width: usableWidth, height: h))
                }
                if row.isSummary {
                    ctx.setFillColor(NSColor.systemGray.withAlphaComponent(0.08).cgColor)
                    ctx.fill(CGRect(x: margin, y: rowY, width: usableWidth, height: h))
                }

                xOffset = margin
                for (colIdx, col) in columns.enumerated() {
                    let colWidth = usableWidth * col.widthFraction

                    if colIdx == 2 {
                        // Wrapped, top-aligned name cell.
                        let framesetter = CTFramesetterCreateWithAttributedString(nameAttributed(row))
                        let cellRect = CGRect(x: xOffset + 4, y: rowY + 2, width: colWidth - 8, height: h - 4)
                        let framePath = CGPath(rect: cellRect, transform: nil)
                        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), framePath, nil)
                        CTFrameDraw(frame, ctx)
                    } else {
                        let text = row.values[colIdx]
                        let font = row.isSummary ? boldBodyFont : bodyFont
                        let textColor: NSColor = row.isCritical ? .systemRed : .labelColor
                        let attrStr = NSAttributedString(string: text,
                            attributes: [.font: font, .foregroundColor: textColor])
                        let line = CTLineCreateWithAttributedString(attrStr)
                        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
                        let textX = col.alignment == .right ? xOffset + colWidth - CGFloat(lineWidth) - 4 : xOffset + 4
                        // Align single-line cells with the name's first line (top of the row).
                        ctx.textPosition = CGPoint(x: textX, y: rowY + h - rowHeight + 5)
                        CTLineDraw(line, ctx)
                    }
                    xOffset += colWidth
                }

                ctx.setStrokeColor(NSColor.separatorColor.withAlphaComponent(0.3).cgColor)
                ctx.setLineWidth(0.25)
                ctx.move(to: CGPoint(x: margin, y: rowY))
                ctx.addLine(to: CGPoint(x: margin + usableWidth, y: rowY))
                ctx.strokePath()

                y -= h
            }

            ctx.endPDFPage()
        }

        ctx.closePDF()
    }
}

// MARK: - Vector Gantt PDF

extension PDFExporter {

    private static func nsColor(_ hex: String, alpha: CGFloat = 1) -> NSColor {
        (Color(hex: hex).map { NSColor($0) } ?? .systemBlue).withAlphaComponent(alpha)
    }

    private static func drawText(
        _ string: String,
        at point: CGPoint,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor,
        anchorRight: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        var origin = point
        if anchorRight {
            origin.x -= attributed.size().width
        }
        attributed.draw(at: origin)
    }

    /// True-vector Gantt PDF mirroring the SVG export's layout (months,
    /// stacked event/leave lane, task rows with date subtitles, baselines,
    /// dependency arrows, branding footer). Crisp at any zoom and far smaller
    /// than the bitmap capture path. Tall projects paginate: the title, month
    /// header and band lane repeat on every page like a table header.
    @MainActor
    static func exportGanttVectorPDF(
        rows: [SVGExporter.GanttRow],
        bands: [SVGExporter.Band],
        rangeStart: Date,
        rangeEnd: Date,
        pixelsPerDay: CGFloat,
        rowHeight: CGFloat,
        title: String,
        fileName: String
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let calendar = Calendar.current
        let leftWidth: CGFloat = 260
        let titleHeight: CGFloat = 44
        let headerHeight: CGFloat = 34
        let footerHeight: CGFloat = 26
        let padding: CGFloat = 24
        let barInset: CGFloat = 4

        let totalDays = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: rangeStart), to: calendar.startOfDay(for: rangeEnd)).day ?? 1)
        let chartWidth = CGFloat(totalDays) * pixelsPerDay

        func x(for date: Date) -> CGFloat {
            let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: rangeStart), to: calendar.startOfDay(for: date)).day ?? 0
            return padding + leftWidth + CGFloat(offset) * pixelsPerDay
        }

        let bandFormatter = DateFormatter()
        bandFormatter.locale = Locale(identifier: "en_US_POSIX")
        bandFormatter.dateFormat = "MMM d, yyyy"
        func bandDates(_ band: SVGExporter.Band) -> String {
            "\(bandFormatter.string(from: band.start)) – \(bandFormatter.string(from: band.finish))"
        }

        // Pack overlapping band titles into stacked lane rows (same as SVG).
        let laneRowHeight: CGFloat = 30
        var laneRowEnds: [CGFloat] = []
        var placedBands: [(band: SVGExporter.Band, x1: CGFloat, width: CGFloat, laneRow: Int)] = []
        for band in bands.sorted(by: { x(for: $0.start) < x(for: $1.start) }) {
            let x1 = x(for: band.start)
            let x2 = x(for: band.finish) + pixelsPerDay
            let width = max(pixelsPerDay, x2 - x1)
            let chipWidth = max(CGFloat(band.name.count) * 6.0 + 14, CGFloat(bandDates(band).count) * 5.4 + 4)
            let footprint = max(width, chipWidth)
            var row = laneRowEnds.firstIndex(where: { x1 >= $0 }) ?? -1
            if row == -1 { row = laneRowEnds.count; laneRowEnds.append(0) }
            laneRowEnds[row] = x1 + footprint + 6
            placedBands.append((band, x1, width, row))
        }
        let laneTop = titleHeight + headerHeight
        let laneHeight: CGFloat = bands.isEmpty ? 0 : CGFloat(laneRowEnds.count) * laneRowHeight + 8
        let bodyTop = laneTop + laneHeight
        let pageWidth = padding * 2 + leftWidth + chartWidth

        // Pagination: chunk rows so no page grows taller than maxPageHeight.
        // Chrome (title, month header, band lane, footer) repeats per page.
        let maxPageHeight: CGFloat = 1224
        let chromeHeight = bodyTop + footerHeight + padding
        let rowCapacity = max(1, Int((maxPageHeight - chromeHeight) / rowHeight))
        var pageRanges: [Range<Int>] = []
        if rows.isEmpty {
            pageRanges = [0..<0]
        } else {
            var lower = 0
            while lower < rows.count {
                let upper = min(rows.count, lower + rowCapacity)
                pageRanges.append(lower..<upper)
                lower = upper
            }
        }
        let maxRowsOnAPage = pageRanges.map(\.count).max() ?? 0
        let pageHeight = chromeHeight + CGFloat(maxRowsOnAPage) * rowHeight

        // Global row index by task id, for routing dependency arrows.
        var rowIndexByID: [Int: Int] = [:]
        for (index, row) in rows.enumerated() {
            if let id = row.uniqueID { rowIndexByID[id] = index }
        }

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }

        let stampFormatter = DateFormatter()
        stampFormatter.dateStyle = .medium
        stampFormatter.timeStyle = .short
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM yyyy"
        let gridColor = NSColor(calibratedWhite: 0.9, alpha: 1)

        for (pageIndex, pageRange) in pageRanges.enumerated() {
            ctx.beginPDFPage(nil)
            ctx.saveGState()

            // Draw top-down via a flipped NSGraphicsContext.
            ctx.translateBy(x: 0, y: pageHeight)
            ctx.scaleBy(x: 1, y: -1)
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx

            let rowsOnPage = pageRange.count
            let bandsBottom = bodyTop + CGFloat(rowsOnPage) * rowHeight

            // Background + title + stamp
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            drawText(title, at: CGPoint(x: padding, y: 14), size: 18, weight: .bold, color: NSColor(calibratedWhite: 0.1, alpha: 1))
            drawText("Exported \(stampFormatter.string(from: Date()))", at: CGPoint(x: pageWidth - padding, y: 18), size: 10, color: .tertiaryLabelColor, anchorRight: true)

            // Month header with overlap suppression
            var currentMonth = -1
            var lastLabelRight: CGFloat = -.greatestFiniteMagnitude
            for dayOffset in 0..<totalDays {
                guard let date = calendar.date(byAdding: .day, value: dayOffset, to: rangeStart) else { continue }
                let month = calendar.component(.month, from: date)
                let colX = padding + leftWidth + CGFloat(dayOffset) * pixelsPerDay
                if month != currentMonth {
                    currentMonth = month
                    ctx.setStrokeColor(gridColor.cgColor)
                    ctx.setLineWidth(0.5)
                    ctx.stroke(CGRect(x: colX, y: titleHeight, width: 0, height: bandsBottom - titleHeight))
                    let label = monthFormatter.string(from: date)
                    if colX + 4 > lastLabelRight + 6 {
                        drawText(label, at: CGPoint(x: colX + 4, y: titleHeight + 8), size: 10, color: .secondaryLabelColor)
                        lastLabelRight = colX + 4 + CGFloat(label.count) * 6.0
                    }
                }
            }

            // Separators
            ctx.setStrokeColor(NSColor(calibratedWhite: 0.82, alpha: 1).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: padding, y: bodyTop, width: pageWidth - padding * 2, height: 0))
            ctx.stroke(CGRect(x: padding + leftWidth, y: titleHeight, width: 0, height: bandsBottom - titleHeight))

            // Bands + lane chips
            for placed in placedBands {
                let color = nsColor(placed.band.colorHex)
                ctx.setFillColor(color.withAlphaComponent(0.12).cgColor)
                ctx.fill(CGRect(x: placed.x1, y: bodyTop, width: placed.width, height: bandsBottom - bodyTop))
                ctx.setStrokeColor(color.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(CGRect(x: placed.x1, y: laneTop, width: 0, height: bandsBottom - laneTop))
                ctx.stroke(CGRect(x: placed.x1 + placed.width, y: laneTop, width: 0, height: bandsBottom - laneTop))

                let chipY = laneTop + CGFloat(placed.laneRow) * laneRowHeight + 3
                let chipWidth = CGFloat(placed.band.name.count) * 6.0 + 14
                let chipPath = CGPath(roundedRect: CGRect(x: placed.x1 + 2, y: chipY, width: chipWidth, height: 13), cornerWidth: 6, cornerHeight: 6, transform: nil)
                ctx.addPath(chipPath)
                ctx.setFillColor(color.withAlphaComponent(0.95).cgColor)
                ctx.fillPath()
                drawText(placed.band.name, at: CGPoint(x: placed.x1 + 7, y: chipY + 1.5), size: 9, weight: .bold, color: .white)
                drawText(bandDates(placed.band), at: CGPoint(x: placed.x1 + 4, y: chipY + 15), size: 9, color: color)
            }

            // Rows
            for (localIndex, index) in pageRange.enumerated() {
                let row = rows[index]
                let rowY = bodyTop + CGFloat(localIndex) * rowHeight
                if index % 2 == 1 {
                    ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.02).cgColor)
                    ctx.fill(CGRect(x: padding, y: rowY, width: pageWidth - padding * 2, height: rowHeight))
                }

                let indent = CGFloat(max(0, row.outlineLevel - 1)) * 12
                let nameColor: NSColor = row.isCritical ? nsColor("#E5484D") : NSColor(calibratedWhite: 0.1, alpha: 1)
                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    drawText(row.name, at: CGPoint(x: padding + 4 + indent, y: rowY + rowHeight * 0.12), size: 11, weight: .bold, color: nameColor)
                    drawText(subtitle, at: CGPoint(x: padding + 4 + indent, y: rowY + rowHeight * 0.55), size: 9, color: .secondaryLabelColor)
                } else {
                    drawText(row.name, at: CGPoint(x: padding + 4 + indent, y: rowY + rowHeight * 0.3), size: 11, weight: row.isSummary ? .bold : .regular, color: nameColor)
                }

                guard let start = row.start else { continue }
                let hasBaseline = !row.isMilestone && !row.isSummary && row.baselineStart != nil && row.baselineFinish != nil
                let barY = rowY + barInset
                let barHeight = hasBaseline ? rowHeight * 0.46 : rowHeight - barInset * 2
                let barColor = nsColor(row.colorHex ?? (row.isCritical ? "#E5484D" : "#2F6FEB"))

                if row.isMilestone {
                    let cx = x(for: start)
                    let cy = rowY + rowHeight / 2
                    let s = (rowHeight - barInset * 2) * 0.55
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: cx, y: cy - s))
                    ctx.addLine(to: CGPoint(x: cx + s, y: cy))
                    ctx.addLine(to: CGPoint(x: cx, y: cy + s))
                    ctx.addLine(to: CGPoint(x: cx - s, y: cy))
                    ctx.closePath()
                    ctx.setFillColor(nsColor(row.colorHex ?? "#F5871F").cgColor)
                    ctx.fillPath()
                } else if let finish = row.finish {
                    let startX = x(for: start)
                    let barWidth = max(2, x(for: finish) - startX)
                    if row.isSummary {
                        ctx.setFillColor(nsColor(row.colorHex ?? "#8A8F98").cgColor)
                        ctx.fill(CGRect(x: startX, y: rowY + rowHeight * 0.42, width: barWidth, height: (rowHeight - barInset * 2) * 0.35))
                    } else {
                        let barRect = CGRect(x: startX, y: barY, width: barWidth, height: barHeight)
                        ctx.addPath(CGPath(roundedRect: barRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
                        ctx.setFillColor(barColor.withAlphaComponent(0.3).cgColor)
                        ctx.fillPath()
                        let fillWidth = barWidth * CGFloat(min(1, max(0, row.percentComplete / 100.0)))
                        if fillWidth > 0 {
                            ctx.addPath(CGPath(roundedRect: CGRect(x: startX, y: barY, width: fillWidth, height: barHeight), cornerWidth: 3, cornerHeight: 3, transform: nil))
                            ctx.setFillColor(barColor.cgColor)
                            ctx.fillPath()
                        }
                    }
                }

                // Baseline bar (gray, under the current bar) — mirrors the
                // on-screen Baseline toggle.
                if hasBaseline, let baselineStart = row.baselineStart, let baselineFinish = row.baselineFinish {
                    let baselineX = x(for: baselineStart)
                    let baselineWidth = max(2, x(for: baselineFinish) - baselineX)
                    let baselineRect = CGRect(x: baselineX, y: rowY + rowHeight * 0.62, width: baselineWidth, height: rowHeight * 0.2)
                    ctx.addPath(CGPath(roundedRect: baselineRect, cornerWidth: 2, cornerHeight: 2, transform: nil))
                    ctx.setFillColor(NSColor(calibratedWhite: 0.6, alpha: 0.8).cgColor)
                    ctx.fillPath()
                }
            }

            // Dependency arrows — same right-angle routing as the on-screen
            // GanttDependencyView, clipped to this page's row area so arrows
            // spanning pages render their visible segments on each page.
            drawDependencyArrows(
                in: ctx,
                rows: rows,
                rowIndexByID: rowIndexByID,
                pageRange: pageRange,
                bodyTop: bodyTop,
                rowHeight: rowHeight,
                clipRect: CGRect(x: padding, y: bodyTop, width: pageWidth - padding * 2, height: CGFloat(rowsOnPage) * rowHeight),
                x: x
            )

            // Branding footer + page number
            var brandX = padding
            if let icon = NSApp?.applicationIconImage {
                icon.draw(in: CGRect(x: padding, y: pageHeight - padding - 8, width: 14, height: 14))
                brandX += 18
            }
            drawText("Planroom", at: CGPoint(x: brandX, y: pageHeight - padding - 6), size: 10, weight: .bold, color: .secondaryLabelColor)
            if pageRanges.count > 1 {
                drawText("Page \(pageIndex + 1) of \(pageRanges.count)", at: CGPoint(x: pageWidth - padding, y: pageHeight - padding - 6), size: 9, color: .tertiaryLabelColor, anchorRight: true)
            }

            NSGraphicsContext.restoreGraphicsState()
            ctx.restoreGState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
    }

    /// Routes predecessor→successor arrows with the same geometry as the
    /// on-screen `GanttDependencyView`: endpoints chosen by relation type
    /// (FS/SS/FF/SF), right-angle elbows at the midpoint, small arrowhead.
    private static func drawDependencyArrows(
        in ctx: CGContext,
        rows: [SVGExporter.GanttRow],
        rowIndexByID: [Int: Int],
        pageRange: Range<Int>,
        bodyTop: CGFloat,
        rowHeight: CGFloat,
        clipRect: CGRect,
        x: (Date) -> CGFloat
    ) {
        guard !rows.isEmpty else { return }

        func pageY(forGlobalRow index: Int) -> CGFloat {
            bodyTop + (CGFloat(index) - CGFloat(pageRange.lowerBound)) * rowHeight + rowHeight / 2
        }

        ctx.saveGState()
        ctx.clip(to: clipRect)
        let arrowColor = NSColor(calibratedWhite: 0.4, alpha: 0.55)

        for (succIndex, row) in rows.enumerated() {
            guard !row.links.isEmpty, let succStart = row.start else { continue }
            let succEnd = row.finish ?? succStart

            for link in row.links {
                guard let predIndex = rowIndexByID[link.predecessorID] else { continue }
                let pred = rows[predIndex]
                guard let predStart = pred.start else { continue }
                let predEnd = pred.finish ?? predStart

                // Skip arrows entirely outside this page's rows.
                let minRow = min(predIndex, succIndex)
                let maxRow = max(predIndex, succIndex)
                guard maxRow >= pageRange.lowerBound, minRow < pageRange.upperBound else { continue }

                let startPoint: CGPoint
                let endPoint: CGPoint
                switch link.type {
                case "SS":
                    startPoint = CGPoint(x: x(predStart), y: pageY(forGlobalRow: predIndex))
                    endPoint = CGPoint(x: x(succStart), y: pageY(forGlobalRow: succIndex))
                case "FF":
                    startPoint = CGPoint(x: x(predEnd), y: pageY(forGlobalRow: predIndex))
                    endPoint = CGPoint(x: x(succEnd), y: pageY(forGlobalRow: succIndex))
                case "SF":
                    startPoint = CGPoint(x: x(predStart), y: pageY(forGlobalRow: predIndex))
                    endPoint = CGPoint(x: x(succEnd), y: pageY(forGlobalRow: succIndex))
                default: // FS
                    startPoint = CGPoint(x: x(predEnd), y: pageY(forGlobalRow: predIndex))
                    endPoint = CGPoint(x: x(succStart), y: pageY(forGlobalRow: succIndex))
                }

                ctx.beginPath()
                ctx.move(to: startPoint)
                let midX = (startPoint.x + endPoint.x) / 2
                if abs(startPoint.y - endPoint.y) > 1 {
                    ctx.addLine(to: CGPoint(x: midX, y: startPoint.y))
                    ctx.addLine(to: CGPoint(x: midX, y: endPoint.y))
                }
                ctx.addLine(to: endPoint)
                ctx.setStrokeColor(arrowColor.cgColor)
                ctx.setLineWidth(1)
                ctx.strokePath()

                let arrowSize: CGFloat = 4
                ctx.beginPath()
                ctx.move(to: endPoint)
                ctx.addLine(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y - arrowSize))
                ctx.addLine(to: CGPoint(x: endPoint.x - arrowSize, y: endPoint.y + arrowSize))
                ctx.closePath()
                ctx.setFillColor(arrowColor.cgColor)
                ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }
}
