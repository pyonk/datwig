import XCTest
@testable import Datwig

final class ExifParserTests: XCTestCase {

    func testStandardExifDateFormat() {
        let dateString = "2024:08:15 14:30:25"
        let parsed = ExifDateParser.parse(dateString)
        XCTAssertNotNil(parsed, "Standard EXIF date string should be parsed successfully")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed!)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 25)
    }

    func testISO8601WithTimezoneAndMillis() {
        let isoString = "2023-12-25T18:45:10.500Z"
        let parsed = ExifDateParser.parse(isoString)
        XCTAssertNotNil(parsed, "ISO 8601 with fractional seconds and UTC Z should parse")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed!)

        XCTAssertEqual(components.year, 2023)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.day, 25)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 45)
    }

    func testStandardExifWithTimezoneOffset() {
        let offsetString = "2024:05:01 09:15:00+02:00"
        let parsed = ExifDateParser.parse(offsetString)
        XCTAssertNotNil(parsed, "EXIF with timezone offset should parse")
    }

    func testDateOnlyFormat() {
        let dateOnly = "2022:11:30"
        let parsed = ExifDateParser.parse(dateOnly)
        XCTAssertNotNil(parsed)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: parsed!)

        XCTAssertEqual(components.year, 2022)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 30)
    }

    func testIPTCDateAndTimeParsing() {
        let datePart = "20240410"
        let timePart = "123000"
        let parsed = ExifDateParser.parseIPTC(date: datePart, time: timePart)
        XCTAssertNotNil(parsed, "IPTC separated date and time should parse")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed!)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 10)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 0)
    }

    func testInvalidDateStringReturnsNil() {
        XCTAssertNil(ExifDateParser.parse(""))
        XCTAssertNil(ExifDateParser.parse("not-a-real-date"))
        XCTAssertNil(ExifDateParser.parse("2024/99/99 99:99:99"))
    }

    func testFileSystemFallbackHierarchy() throws {
        // Create temporary test file without EXIF metadata
        let tempDir = FileManager.default.temporaryDirectory
        let tempFileURL = tempDir.appendingPathComponent("datwig_test_\(UUID().uuidString).dat")
        let sampleData = "Datwig Test File".data(using: .utf8)!
        try sampleData.write(to: tempFileURL)

        defer {
            try? FileManager.default.removeItem(at: tempFileURL)
        }

        let parser = ExifParser()
        let result = parser.extractDate(from: tempFileURL)

        // For non-image files, it should fall back to file creation or modification date
        XCTAssert(
            result.source == .fileCreationDate || result.source == .fileModificationDate,
            "Expected file system date fallback, got \(result.source)"
        )
        XCTAssertNotNil(result.date)
    }
}
