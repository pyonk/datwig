import XCTest
@testable import Datwig

final class DateOrganizerTests: XCTestCase {

    func testDirectoryStructureFormatting() {
        let settings = OrganizationSettings()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let targetDate = calendar.date(from: DateComponents(year: 2024, month: 8, day: 15, hour: 10, minute: 0))!

        // Test Preset: yyyy/yyyy-MM-dd
        settings.formatPreset = .yearThenDate
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate), "2024/2024-08-15")

        // Test Preset: yyyy/MM/dd
        settings.formatPreset = .yearMonthDay
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate), "2024/08/15")

        // Test Preset: yyyy-MM-dd
        settings.formatPreset = .flatDate
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate), "2024-08-15")

        // Test Preset: yyyy/MM - MMMM/yyyy-MM-dd
        settings.formatPreset = .yearMonthNameDay
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate), "2024/08 - August/2024-08-15")

        // Test Custom Pattern
        settings.formatPreset = .custom
        settings.customFormatPattern = "yyyy/'Vault'/MM/dd"
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate), "2024/Vault/08/15")
    }

    func testMediaExtensionFiltering() {
        let scanner = FileScanner()

        // Supported images
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "photo.jpg")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "photo.jpeg")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "shot.HEIC")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "capture.png")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "raw.CR3")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "sony.ARW")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "nikon.NEF")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "adobe.DNG")))

        // Supported videos
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "video.MOV")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "clip.mp4")))
        XCTAssertTrue(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "stream.MTS")))

        // Unsupported files
        XCTAssertFalse(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "document.pdf")))
        XCTAssertFalse(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "archive.zip")))
        XCTAssertFalse(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: "notes.txt")))
        XCTAssertFalse(scanner.isSupportedMediaFile(url: URL(fileURLWithPath: ".DS_Store")))
    }

    func testOrganizationReportFormatting() {
        let report = OrganizationReport(
            totalFound: 150,
            copiedCount: 140,
            skippedCount: 8,
            renamedCount: 2,
            errorCount: 0,
            totalBytesProcessed: 1024 * 1024 * 50, // 50 MB
            destinationDirectory: URL(fileURLWithPath: "/tmp/Datwig"),
            durationSeconds: 12.4
        )

        XCTAssertEqual(report.copiedCount, 140)
        XCTAssertEqual(report.skippedCount, 8)
        XCTAssertEqual(report.renamedCount, 2)
        XCTAssertFalse(report.formattedTotalBytes.isEmpty)
        XCTAssertEqual(report.formattedDuration, "12 seconds")
    }
}
