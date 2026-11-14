import XCTest
@testable import Datwig

final class DateOrganizerTests: XCTestCase {

    func testDirectoryStructureFormatting() {
        let settings = OrganizationSettings()
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let targetDate = calendar.date(from: DateComponents(year: 2024, month: 8, day: 15, hour: 10, minute: 0))!

        // Test Preset: yyyy/yyyy-MM-dd
        settings.formatPreset = .yearThenDate
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate, timeZone: utc), "2024/2024-08-15")

        // Test Preset: yyyy/MM/dd
        settings.formatPreset = .yearMonthDay
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate, timeZone: utc), "2024/08/15")

        // Test Preset: yyyy-MM-dd
        settings.formatPreset = .flatDate
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate, timeZone: utc), "2024-08-15")

        // Test Preset: yyyy/MM - MMMM/yyyy-MM-dd
        settings.formatPreset = .yearMonthNameDay
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate, timeZone: utc), "2024/08 - August/2024-08-15")

        // Test Custom Pattern
        settings.formatPreset = .custom
        settings.customFormatPattern = "yyyy/'Vault'/MM/dd"
        XCTAssertEqual(settings.relativeSubdirectory(for: targetDate, timeZone: utc), "2024/Vault/08/15")
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

    @MainActor
    func testConfirmationWorkflowDoesNotCopyBeforeConfirmAndRecordsLog() async throws {
        let fm = FileManager.default
        let rootTemp = fm.temporaryDirectory.appendingPathComponent("datwig_workflow_test_\(UUID().uuidString)", isDirectory: true)
        let sourceDir = rootTemp.appendingPathComponent("source", isDirectory: true)
        let destDir = rootTemp.appendingPathComponent("dest", isDirectory: true)

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: rootTemp)
        }

        let fileA = sourceDir.appendingPathComponent("IMG_0001.jpg")
        let fileB = sourceDir.appendingPathComponent("IMG_0002.jpg")
        try Data("photo-a".utf8).write(to: fileA)
        try Data("photo-b".utf8).write(to: fileB)

        let settings = OrganizationSettings()
        settings.destinationURL = destDir
        settings.formatPreset = .yearThenDate
        settings.duplicatePolicy = .skipIdentical
        settings.includeSubdirectories = true

        let organizer = DateOrganizer(settings: settings)
        organizer.prepareBatch(urls: [sourceDir])

        // Wait for scan & dry-run preview to reach .ready
        for _ in 0..<100 {
            if case .ready = organizer.state { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard case .ready(let preview) = organizer.state else {
            return XCTFail("Expected .ready state after prepareBatch, got \(organizer.state)")
        }

        XCTAssertEqual(preview.totalFiles, 2)
        XCTAssertFalse(preview.folderBuckets.isEmpty)

        // Ensure zero files were copied to destination prior to explicit confirmation
        let destContentsBeforeConfirm = try fm.contentsOfDirectory(atPath: destDir.path(percentEncoded: false))
        XCTAssertTrue(destContentsBeforeConfirm.isEmpty, "Destination must stay empty before user confirms")

        organizer.confirmAndStart()

        // Wait for copy pipeline to complete
        for _ in 0..<100 {
            if case .completed = organizer.state { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard case .completed(let report) = organizer.state else {
            return XCTFail("Expected .completed state after confirmAndStart, got \(organizer.state)")
        }

        XCTAssertEqual(report.totalFound, 2)
        XCTAssertEqual(report.copiedCount, 2)
        XCTAssertEqual(report.errorCount, 0)
        XCTAssertEqual(organizer.processedItems.count, 2)

        let logText = organizer.exportLogText()
        XCTAssertTrue(logText.contains("=== Datwig Processing Log ==="))
        XCTAssertTrue(logText.contains("[COPIED]"))
        XCTAssertTrue(logText.contains("IMG_0001.jpg"))
        XCTAssertTrue(logText.contains("IMG_0002.jpg"))
    }
}
