import XCTest
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
}
