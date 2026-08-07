import Foundation
import Compression

/// Minimal reader/writer for the modern `.xlsx` (Office Open XML) format so
/// exports open cleanly in Excel/Numbers without the "old format" warning that
/// the legacy SpreadsheetML `.xls` produced, and filled-in templates can be
/// re-imported.
enum XLSX {

    // MARK: - Writing

    /// Builds a single-sheet `.xlsx` workbook from a header row plus data rows.
    static func workbook(headers: [String], rows: [[String]], sheetName: String) -> Data {
        let allRows = [headers] + rows
        let sheetXML = sheetXML(rows: allRows)
        let safeSheetName = sanitizedSheetName(sheetName)

        var zip = ZipWriter()
        zip.addFile(path: "[Content_Types].xml", contents: contentTypesXML)
        zip.addFile(path: "_rels/.rels", contents: rootRelsXML)
        zip.addFile(path: "xl/workbook.xml", contents: workbookXML(sheetName: safeSheetName))
        zip.addFile(path: "xl/_rels/workbook.xml.rels", contents: workbookRelsXML)
        zip.addFile(path: "xl/worksheets/sheet1.xml", contents: sheetXML)
        return zip.finalize()
    }

    private static func sanitizedSheetName(_ name: String) -> String {
        // Excel sheet names cap at 31 chars and forbid a few characters.
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "[]:*?/\\")).joined(separator: " ")
        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        let base = trimmed.isEmpty ? "Sheet1" : trimmed
        return String(base.prefix(31))
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="\(escapeXML(sheetName))" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """
    }

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    </Relationships>
    """

    private static func sheetXML(rows: [[String]]) -> String {
        var sheetData = ""
        for (rowIndex, row) in rows.enumerated() {
            let rowNumber = rowIndex + 1
            var cells = ""
            for (columnIndex, value) in row.enumerated() {
                let reference = "\(columnLetters(columnIndex))\(rowNumber)"
                // Inline strings keep every value as text so numeric-looking
                // WBS/IDs aren't reformatted by Excel.
                cells += "<c r=\"\(reference)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
            }
            sheetData += "<row r=\"\(rowNumber)\">\(cells)</row>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheetData)</sheetData>
        </worksheet>
        """
    }

    private static func columnLetters(_ index: Int) -> String {
        var value = index
        var letters = ""
        repeat {
            let remainder = value % 26
            letters = String(UnicodeScalar(65 + remainder)!) + letters
            value = value / 26 - 1
        } while value >= 0
        return letters
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    // MARK: - Reading

    /// Reads the first worksheet of an `.xlsx` file into rows of string cells.
    static func readRows(from url: URL) -> [[String]]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let archive = ZipReader(data: data)

        let sharedStrings = archive.data(for: "xl/sharedStrings.xml").flatMap { parseSharedStrings($0) } ?? []

        // The first worksheet is usually sheet1.xml, but fall back to any sheet.
        let sheetData = archive.data(for: "xl/worksheets/sheet1.xml")
            ?? archive.firstSheetData()
        guard let sheetData else { return nil }

        return parseSheet(sheetData, sharedStrings: sharedStrings)
    }

    private static func parseSharedStrings(_ data: Data) -> [String] {
        guard let doc = try? XMLDocument(data: data, options: []) else { return [] }
        guard let items = try? doc.nodes(forXPath: "//*[local-name()='si']") else { return [] }
        return items.map { item in
            let texts = (try? item.nodes(forXPath: ".//*[local-name()='t']")) ?? []
            return texts.compactMap { $0.stringValue }.joined()
        }
    }

    private static func parseSheet(_ data: Data, sharedStrings: [String]) -> [[String]]? {
        guard let doc = try? XMLDocument(data: data, options: []) else { return nil }
        guard let rowNodes = try? doc.nodes(forXPath: "//*[local-name()='row']") else { return nil }

        var rows: [[String]] = []
        for rowNode in rowNodes {
            guard let cellNodes = try? rowNode.nodes(forXPath: "./*[local-name()='c']") else { continue }
            var row: [String] = []
            var nextColumn = 0

            for cellNode in cellNodes {
                guard let cell = cellNode as? XMLElement else { continue }
                let column = cell.attribute(forName: "r").flatMap { columnIndex(fromReference: $0.stringValue ?? "") } ?? nextColumn
                while row.count < column { row.append("") }

                let type = cell.attribute(forName: "t")?.stringValue
                let value: String
                if type == "inlineStr" {
                    let texts = (try? cell.nodes(forXPath: ".//*[local-name()='t']")) ?? []
                    value = texts.compactMap { $0.stringValue }.joined()
                } else if type == "s" {
                    let raw = (try? cell.nodes(forXPath: "./*[local-name()='v']"))?.first?.stringValue ?? ""
                    value = Int(raw).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
                } else {
                    value = (try? cell.nodes(forXPath: "./*[local-name()='v']"))?.first?.stringValue ?? ""
                }

                row.append(value.trimmingCharacters(in: .newlines))
                nextColumn = column + 1
            }

            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                rows.append(row)
            }
        }

        return rows.isEmpty ? nil : rows
    }

    private static func columnIndex(fromReference reference: String) -> Int? {
        let letters = reference.prefix { $0.isLetter }
        guard !letters.isEmpty else { return nil }
        var index = 0
        for scalar in letters.uppercased().unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { return nil }
            index = index * 26 + Int(scalar.value - 64)
        }
        return index - 1
    }
}

// MARK: - Minimal ZIP writer (STORED, uncompressed)

private struct ZipWriter {
    private struct Entry {
        let path: String
        let crc: UInt32
        let size: Int
        let offset: Int
    }

    private var body = Data()
    private var entries: [Entry] = []

    mutating func addFile(path: String, contents: String) {
        let fileData = Data(contents.utf8)
        let crc = crc32(fileData)
        let offset = body.count
        let nameData = Data(path.utf8)

        // Local file header
        var header = Data()
        header.appendUInt32(0x04034b50)
        header.appendUInt16(20)          // version needed
        header.appendUInt16(0)           // flags
        header.appendUInt16(0)           // method: stored
        header.appendUInt16(0)           // mod time
        header.appendUInt16(0x21)        // mod date (1980-01-01 valid-ish)
        header.appendUInt32(crc)
        header.appendUInt32(UInt32(fileData.count)) // compressed size
        header.appendUInt32(UInt32(fileData.count)) // uncompressed size
        header.appendUInt16(UInt16(nameData.count))
        header.appendUInt16(0)           // extra length
        header.append(nameData)

        body.append(header)
        body.append(fileData)
        entries.append(Entry(path: path, crc: crc, size: fileData.count, offset: offset))
    }

    mutating func finalize() -> Data {
        let centralDirectoryOffset = body.count
        var central = Data()
        for entry in entries {
            let nameData = Data(entry.path.utf8)
            central.appendUInt32(0x02014b50)
            central.appendUInt16(20)      // version made by
            central.appendUInt16(20)      // version needed
            central.appendUInt16(0)       // flags
            central.appendUInt16(0)       // method
            central.appendUInt16(0)       // mod time
            central.appendUInt16(0x21)    // mod date
            central.appendUInt32(entry.crc)
            central.appendUInt32(UInt32(entry.size))
            central.appendUInt32(UInt32(entry.size))
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)       // extra
            central.appendUInt16(0)       // comment
            central.appendUInt16(0)       // disk number
            central.appendUInt16(0)       // internal attrs
            central.appendUInt32(0)       // external attrs
            central.appendUInt32(UInt32(entry.offset))
            central.append(nameData)
        }

        let centralDirectorySize = central.count
        var end = Data()
        end.appendUInt32(0x06054b50)
        end.appendUInt16(0)               // disk
        end.appendUInt16(0)               // disk with CD
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt16(UInt16(entries.count))
        end.appendUInt32(UInt32(centralDirectorySize))
        end.appendUInt32(UInt32(centralDirectoryOffset))
        end.appendUInt16(0)               // comment length

        var result = body
        result.append(central)
        result.append(end)
        return result
    }
}

// MARK: - Minimal ZIP reader (STORED + DEFLATE)

private struct ZipReader {
    private let data: Data
    private var index: [String: (method: UInt16, offset: Int, compressedSize: Int, uncompressedSize: Int)] = [:]

    init(data: Data) {
        self.data = data
        parseCentralDirectory()
    }

    func data(for path: String) -> Data? {
        guard let entry = index[path] else { return nil }
        // Local header: 30 bytes fixed + name + extra, then the file data.
        let localOffset = entry.offset
        guard data.count >= localOffset + 30 else { return nil }
        let nameLength = Int(readUInt16(at: localOffset + 26))
        let extraLength = Int(readUInt16(at: localOffset + 28))
        let dataStart = localOffset + 30 + nameLength + extraLength
        guard data.count >= dataStart + entry.compressedSize else { return nil }
        let compressed = data.subdata(in: dataStart ..< dataStart + entry.compressedSize)

        if entry.method == 0 {
            return compressed
        }
        return inflate(compressed, expectedSize: entry.uncompressedSize)
    }

    func firstSheetData() -> Data? {
        let sheetPath = index.keys
            .filter { $0.hasPrefix("xl/worksheets/") && $0.hasSuffix(".xml") }
            .sorted()
            .first
        return sheetPath.flatMap { data(for: $0) }
    }

    private mutating func parseCentralDirectory() {
        // Find the End of Central Directory record by scanning backwards.
        let signature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return }
        var eocd = -1
        var i = bytes.count - 22
        while i >= 0 {
            if bytes[i] == signature[0], bytes[i+1] == signature[1], bytes[i+2] == signature[2], bytes[i+3] == signature[3] {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { return }

        let entryCount = Int(readUInt16(at: eocd + 10))
        var offset = Int(readUInt32(at: eocd + 16))

        for _ in 0..<entryCount {
            guard offset + 46 <= bytes.count, readUInt32(at: offset) == 0x02014b50 else { break }
            let method = readUInt16(at: offset + 10)
            let compressedSize = Int(readUInt32(at: offset + 20))
            let uncompressedSize = Int(readUInt32(at: offset + 24))
            let nameLength = Int(readUInt16(at: offset + 28))
            let extraLength = Int(readUInt16(at: offset + 30))
            let commentLength = Int(readUInt16(at: offset + 32))
            let localOffset = Int(readUInt32(at: offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart ..< nameStart + nameLength], as: UTF8.self)
            index[name] = (method, localOffset, compressedSize, uncompressedSize)
            offset = nameStart + nameLength + extraLength + commentLength
        }
    }

    private func inflate(_ input: Data, expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return Data() }
        let capacity = expectedSize
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            input.withUnsafeBytes { source -> Int in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return output.prefix(written)
    }

    private func readUInt16(at offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}

// MARK: - Byte helpers

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

private let crc32Table: [UInt32] = {
    (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }
}()

private func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xffffffff
    for byte in data {
        crc = crc32Table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
    }
    return crc ^ 0xffffffff
}
