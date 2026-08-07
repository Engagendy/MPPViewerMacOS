import XCTest
import SwiftUI
import AppKit
@testable import MPPViewer

@MainActor
final class CSVTaskImportTests: XCTestCase {

    // Windows/Excel exports terminate lines with CRLF, which Swift folds
    // into a single Character. The parser must not leak it into fields.
    func testParseCSVRowsHandlesCRLFLineEndings() {
        let csv = "Task ID,WBS,Task Name,Duration,Notes\r\n"
            + "1,1,Kickoff,1d,Milestone note\r\n"
            + "2,1.1,\"Discovery, and scoping\",5d,Large\r\n"
            + "3,1.2,Draft,5d,\r\n"

        let rows = CSVExporter.parseCSVRows(csv)

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0], ["Task ID", "WBS", "Task Name", "Duration", "Notes"])
        XCTAssertEqual(rows[1], ["1", "1", "Kickoff", "1d", "Milestone note"])
        XCTAssertEqual(rows[2][2], "Discovery, and scoping")
        XCTAssertEqual(rows[3][0], "3")
    }

    func testTaskImportFromCRLFCSV() {
        let csv = "Task ID,WBS,Task Name,Outline Level,Start,Finish,Duration,Milestone,Manual Scheduling,Active,Notes\r\n"
            + "1,1,Phase 1,1,,,,No,No,Yes,\r\n"
            + "2,1.1,Build Feature,2,2027-01-01,2027-03-25,60d,No,Yes,Yes,Extra Large\r\n"
            + "3,1.2,Review,2,2027-01-01,2027-01-28,20d,No,Yes,Yes,Small\r\n"

        let rows = CSVExporter.parseCSVRows(csv)
        XCTAssertEqual(rows.count, 4)

        let headers = rows[0]
        let dataRows = Array(rows.dropFirst())
        let mapping = CSVExporter.defaultTaskMapping(for: headers)
        XCTAssertNotNil(mapping[.name] ?? nil)
        XCTAssertNotNil(mapping[.notes] ?? nil)

        let session = CSVTaskImportSession(
            fileName: "import.csv",
            headers: headers,
            dataRows: dataRows,
            previewRows: Array(dataRows.prefix(5)),
            mapping: mapping
        )

        let result = CSVExporter.applyTaskImport(session, into: NativeProjectPlan.empty())
        XCTAssertNotNil(result)
        guard let result else { return }

        XCTAssertEqual(result.plan.tasks.count, 3)
        let feature = result.plan.tasks.first(where: { $0.name == "Build Feature" })
        XCTAssertEqual(feature?.notes, "Extra Large")
        XCTAssertEqual(feature?.durationDays, 60)
        XCTAssertEqual(feature?.outlineLevel, 2)
    }

    func testCustomFieldsRoundTripAndSurfaceInProjectModel() throws {
        var plan = NativeProjectPlan.empty()
        var task = plan.makeTask(name: "Wage Protection System")
        task.customFields = ["Domain": "Payments", "Workstream": "Phase 2"]
        plan.tasks.append(task)

        let decoded = try NativeProjectPlan.decode(from: plan.encodedData())
        XCTAssertEqual(decoded.tasks.first?.customFields["Domain"], "Payments")

        let project = decoded.asProjectModel()
        let projectTask = project.tasks.first(where: { $0.name == "Wage Protection System" })
        XCTAssertEqual(projectTask?.customFields?["Domain"]?.displayString, "Payments")
        XCTAssertEqual(projectTask?.customFields?["Workstream"]?.displayString, "Phase 2")
    }

    func testRelocateTaskSubtreeAcrossParents() {
        var plan = NativeProjectPlan.empty()

        func addTask(_ id: Int, _ name: String, level: Int) {
            var task = plan.makeTask(name: name)
            task.id = id
            task.outlineLevel = level
            plan.tasks.append(task)
        }

        addTask(1, "MD", level: 1)
        addTask(2, "Phase 2", level: 2)
        addTask(3, "Task A", level: 3)
        addTask(4, "Task B", level: 3)
        addTask(5, "Phase 3", level: 2)
        addTask(6, "Task C", level: 3)

        // Move Task B out of Phase 2 to become the first child of Phase 3.
        XCTAssertTrue(plan.relocateTaskSubtree(taskID: 4, anchorTaskID: 5, placeAfterAnchor: true))
        XCTAssertEqual(plan.tasks.map(\.id), [1, 2, 3, 5, 4, 6])
        XCTAssertEqual(plan.tasks[4].outlineLevel, 3)

        // Moving a task to the very top clamps it to a root-level row.
        XCTAssertTrue(plan.relocateTaskSubtree(taskID: 6, anchorTaskID: 1, placeAfterAnchor: false))
        XCTAssertEqual(plan.tasks.first?.id, 6)
        XCTAssertEqual(plan.tasks.first?.outlineLevel, 1)

        // A summary moves with its whole subtree.
        XCTAssertTrue(plan.relocateTaskSubtree(taskID: 2, anchorTaskID: 4, placeAfterAnchor: true))
        XCTAssertEqual(plan.tasks.map(\.id), [6, 1, 5, 4, 2, 3])

        // Relocating into its own subtree is refused.
        XCTAssertFalse(plan.relocateTaskSubtree(taskID: 2, anchorTaskID: 3, placeAfterAnchor: true))
    }

    func testBarColorRoundTripsAndSurfacesInProjectModel() throws {
        var plan = NativeProjectPlan.empty()
        var task = plan.makeTask(name: "Wage Protection System")
        task.barColorHex = "#2FA84F"
        plan.tasks.append(task)

        let decoded = try NativeProjectPlan.decode(from: plan.encodedData())
        XCTAssertEqual(decoded.tasks.first?.barColorHex, "#2FA84F")

        let project = decoded.asProjectModel()
        XCTAssertEqual(project.tasks.first(where: { $0.name == "Wage Protection System" })?.barColorHex, "#2FA84F")
    }

    func testHostedViewRendersNonBlankForPrinting() throws {
        // Reproduces the print pipeline: a SwiftUI view hosted in an offscreen
        // window must actually render pixels (a detached hosting view prints
        // blank pages).
        let content = VStack(alignment: .leading, spacing: 4) {
            Text("Task List").font(.title2)
            Rectangle().fill(Color.black).frame(width: 180, height: 24)
            Text("Wage Protection System   60d   01/03/2027")
        }
        .padding()
        .frame(width: 400, height: 200)

        let host = NSHostingView(rootView: AnyView(content))
        host.frame = CGRect(x: 0, y: 0, width: 400, height: 200)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)

        var nonWhiteSamples = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let isWhite = color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95
                if !isWhite { nonWhiteSamples += 1 }
            }
        }
        XCTAssertGreaterThan(nonWhiteSamples, 0, "Hosted view rendered blank — print would produce white pages")

        window.contentView = nil
    }

    func testGanttSVGExportProducesValidVectorMarkup() {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let finish = cal.date(from: DateComponents(year: 2027, month: 3, day: 25))!
        let rows: [SVGExporter.GanttRow] = [
            .init(name: "MD", outlineLevel: 1, start: start, finish: finish, isMilestone: false, isSummary: true, isCritical: false, percentComplete: 0, colorHex: nil),
            .init(name: "Wage Protection System", outlineLevel: 2, start: start, finish: finish, isMilestone: false, isSummary: false, isCritical: true, percentComplete: 40, colorHex: "#2FA84F"),
            .init(name: "Kickoff", outlineLevel: 2, start: start, finish: start, isMilestone: true, isSummary: false, isCritical: false, percentComplete: 100, colorHex: nil)
        ]

        let svg = SVGExporter.svgForTesting(rows: rows, rangeStart: start, rangeEnd: finish, pixelsPerDay: 6, rowHeight: 24, title: "MD Phases <Plan>")

        XCTAssertTrue(svg.hasPrefix("<?xml"))
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains("</svg>"))
        XCTAssertTrue(svg.contains("<rect"))
        XCTAssertTrue(svg.contains("<polygon"), "milestone should render as a diamond polygon")
        XCTAssertTrue(svg.contains("#2FA84F"), "custom bar color should be present")
        XCTAssertTrue(svg.contains("MD Phases &lt;Plan&gt;"), "title should be XML-escaped")
        XCTAssertFalse(svg.contains("<Plan>"), "raw angle brackets must be escaped")
    }

    func testXLSXWriteReadRoundTrip() throws {
        let headers = ["Task ID", "Task Name", "Notes"]
        let rows = [
            ["1", "MD", "Root, with comma"],
            ["2", "Phase 2", "Quote \" and <angle> & amp"],
            ["3", "Wage Protection System", "Extra Large"]
        ]

        let data = XLSX.workbook(headers: headers, rows: rows, sheetName: "Task List")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mpp_xlsx_test.xlsx")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Valid xlsx files begin with the ZIP local-file-header signature "PK".
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b])

        let readBack = try XCTUnwrap(XLSX.readRows(from: tempURL))
        XCTAssertEqual(readBack.count, 4)
        XCTAssertEqual(readBack[0], headers)
        XCTAssertEqual(readBack[2], ["2", "Phase 2", "Quote \" and <angle> & amp"])
        XCTAssertEqual(readBack[3][2], "Extra Large")
    }

    func testColorHexParsingAndSerialization() {
        XCTAssertNotNil(Color(hex: "#2F6FEB"))
        XCTAssertNotNil(Color(hex: "2F6FEB"))
        XCTAssertNil(Color(hex: "nope"))
        XCTAssertNil(Color(hex: "#12345"))
        XCTAssertEqual(Color(hex: "#FF0000")?.hexString, "#FF0000")
    }
}
