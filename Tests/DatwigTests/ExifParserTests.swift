import XCTest
@testable import Datwig

final class ExifParserTests: XCTestCase {

    func testStandardExifDateFormatUsesCurrentTimeZoneByDefault() {
        let dateString = "2024:08:15 14:30:25"
        let parsed = ExifDateParser.parse(dateString)
        XCTAssertNotNil(parsed, "Standard EXIF date string should be parsed successfully")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed!)

        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 15)
        XCTAssertEqual(components.hour, 14)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 25)
    }

    func testExifLocalTimePreservedAcrossTimeZonesRegression() throws {
        // Regression test for JST (UTC+9) late-afternoon photo shifting to next day when wrongly parsed as UTC
        let jst = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let dateString = "2026:11:03 16:18:59"

        let parsed = try XCTUnwrap(ExifDateParser.parse(dateString, defaultTimeZone: jst))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 18)
        XCTAssertEqual(components.second, 59)

        let settings = OrganizationSettings()
        settings.formatPreset = .yearThenDate
        XCTAssertEqual(settings.relativeSubdirectory(for: parsed, timeZone: jst), "2026/2026-11-03")
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

    func testStandardExifWithTimezoneOffset() throws {
        let offsetString = "2024:05:01 09:15:00+02:00"
        let parsed = try XCTUnwrap(ExifDateParser.parse(offsetString), "EXIF with timezone offset should parse")

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: parsed)
        XCTAssertEqual(components.year, 2024)
        XCTAssertEqual(components.month, 5)
        XCTAssertEqual(components.day, 1)
        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 15)
    }

    func testDateOnlyFormat() throws {
        let dateOnly = "2022:11:30"
        let jst = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let parsed = try XCTUnwrap(ExifDateParser.parse(dateOnly, defaultTimeZone: jst))

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = calendar.dateComponents([.year, .month, .day], from: parsed)

        XCTAssertEqual(components.year, 2022)
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 30)
    }

    func testIPTCDateAndTimeParsing() throws {
        let datePart = "20240410"
        let timePart = "123000"
        let jst = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let parsed = try XCTUnwrap(
            ExifDateParser.parseIPTC(date: datePart, time: timePart, defaultTimeZone: jst),
            "IPTC separated date and time should parse"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jst
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)

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
