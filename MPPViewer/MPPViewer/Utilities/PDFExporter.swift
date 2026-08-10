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

    /// Export a SwiftUI view (including Canvas) to PDF using NSHostingView bitmap capture.
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
