import Foundation
import SwiftUI
import Observation

/// The high-level lifecycle state of the media organization pipeline.
public enum OrganizerState: Equatable, Sendable {
    case idle
    case scanning(discoveredCount: Int)
    case ready(preview: BatchPreview)
    case processing(current: Int, total: Int, currentFileName: String)
    case completed(report: OrganizationReport)
    case cancelled
    case failed(message: String)

    public var isBusy: Bool {
        switch self {
        case .scanning, .processing:
            return true
        default:
            return false
        }
    }
}

/// The core orchestration engine coordinating file scanning, metadata extraction,
/// pre-copy confirmation, conflict resolution, and safe asynchronous copying.
@Observable
@MainActor
public final class DateOrganizer {
    public static let shared = DateOrganizer()

    // MARK: - Published Observable State

    public private(set) var state: OrganizerState = .idle
    public private(set) var progress: Double = 0.0
    public private(set) var statusMessage: String = "Ready to organize"
    public private(set) var currentFileName: String = ""
    public private(set) var recentItems: [MediaItem] = []
    public private(set) var processedItems: [MediaItem] = []
    public private(set) var lastReport: OrganizationReport? = nil

    // MARK: - Dependencies

    public var settings: OrganizationSettings
    private let exifParser: ExifParser
    private let duplicateResolver: DuplicateResolver
    private let fileScanner: FileScanner

    // Internal execution state
    private var activeTask: Task<Void, Never>? = nil
    private var preparedSourceURLs: [URL] = []
    private var preparedItems: [MediaItem] = []

    public init(
        settings: OrganizationSettings = .shared,
        exifParser: ExifParser = .shared,
        duplicateResolver: DuplicateResolver = .shared,
        fileScanner: FileScanner = .shared
    ) {
        self.settings = settings
        self.exifParser = exifParser
        self.duplicateResolver = duplicateResolver
        self.fileScanner = fileScanner
    }

    // MARK: - Ingestion Entry Points (Scan & Preview First)

    /// Invokes the native macOS `NSOpenPanel` for user file/directory selection and scans for confirmation.
    public func selectSourceViaPicker() {
        guard !state.isBusy else { return }

        if let selectedURL = DirectoryPicker.pickSource() {
            prepareBatch(urls: [selectedURL])
        }
    }

    /// Receives drag-and-dropped file URLs and scans them for confirmation before copying.
    public func handleDrop(urls: [URL]) {
        guard !state.isBusy else { return }
        guard !urls.isEmpty else { return }

        prepareBatch(urls: urls)
    }

    /// Scans the selected files/directories and builds a dry-run preview without copying any files.
    public func prepareBatch(urls: [URL]) {
        cancelActiveTaskOnly()
        preparedSourceURLs = urls
        preparedItems = []
        processedItems.removeAll()
        recentItems.removeAll()
        lastReport = nil

        activeTask = Task { [weak self] in
            await self?.runScanAndPreview(urls: urls)
        }
    }

    /// Recomputes the preview folder buckets if the user changes format settings while in `.ready` state.
    public func refreshPreview() {
        guard case .ready = state, !preparedItems.isEmpty else { return }
        let preview = buildBatchPreview(sourceURLs: preparedSourceURLs, items: preparedItems)
        state = .ready(preview: preview)
    }

    /// Begins copying the prepared batch after explicit user confirmation.
    public func confirmAndStart() {
        guard case .ready = state, !preparedItems.isEmpty else { return }

        activeTask = Task { [weak self] in
            await self?.runCopyPipeline()
        }
    }

    /// Legacy convenience method that prepares a batch for confirmation.
    public func startProcessing(urls: [URL]) {
        prepareBatch(urls: urls)
    }

    /// Requests cooperative cancellation of the running scanning or organization task.
    public func cancel() {
        if let task = activeTask {
            task.cancel()
            activeTask = nil
            state = .cancelled
            statusMessage = "Operation cancelled"
        }
    }

    /// Resets state back to `.idle` for another batch.
    public func reset() {
        cancelActiveTaskOnly()
        preparedSourceURLs.removeAll()
        preparedItems.removeAll()
        processedItems.removeAll()
        recentItems.removeAll()
        lastReport = nil
        state = .idle
        progress = 0.0
        statusMessage = "Ready to organize"
        currentFileName = ""
    }

    // MARK: - Log Export

    /// Generates a formatted plain-text report and per-file processing log.
    public func exportLogText() -> String {
        var lines: [String] = []
        lines.append("=== Datwig Processing Log ===")

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("Generated: \(dateFormatter.string(from: Date()))")

        if let report = lastReport {
            lines.append("Destination: \(report.destinationDirectory.path(percentEncoded: false))")
            lines.append("Total Found: \(report.totalFound) | Copied: \(report.copiedCount) | Renamed: \(report.renamedCount) | Skipped: \(report.skippedCount) | Errors: \(report.errorCount)")
            lines.append("Duration: \(report.formattedDuration) | Data Copied: \(report.formattedTotalBytes)")
        } else {
            lines.append("Status: Cancelled / Incomplete")
            lines.append("Destination: \(settings.destinationURL.path(percentEncoded: false))")
        }

        lines.append("")
        lines.append("--- File Details (\(processedItems.count) items) ---")

        for (idx, item) in processedItems.enumerated() {
            let statusLabel: String
            let detail: String
            switch item.status {
            case .copied(let dest):
                statusLabel = "COPIED"
                detail = "-> \(dest.path(percentEncoded: false))"
            case .renamed(let dest):
                statusLabel = "RENAMED"
                detail = "-> \(dest.path(percentEncoded: false))"
            case .skipped(let reason):
                statusLabel = "SKIPPED"
                if let target = item.targetURL {
                    detail = "\(reason) (\(target.path(percentEncoded: false)))"
                } else {
                    detail = reason
                }
            case .failed(let err):
                statusLabel = "FAILED"
                detail = "Error: \(err)"
            case .pending, .copying:
                statusLabel = "PENDING"
                detail = ""
            }

            let dateSrc = item.dateSource?.rawValue ?? "Unknown"
            lines.append("[\(idx + 1)] [\(statusLabel)] \(item.fileName) | Date: \(item.formattedCaptureDate) (\(dateSrc)) | Source: \(item.sourceURL.path(percentEncoded: false)) \(detail)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Phase 1: Scan & Preview (Non-destructive)

    private func runScanAndPreview(urls: [URL]) async {
        self.state = .scanning(discoveredCount: 0)
        self.statusMessage = "Scanning files and folders..."
        self.progress = 0.0

        let discoveredItems = await fileScanner.scan(
            inputURLs: urls,
            includeSubdirectories: settings.includeSubdirectories
        ) { [weak self] count in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = .scanning(discoveredCount: count)
                self.statusMessage = "Discovered \(count) media file\(count == 1 ? "" : "s")..."
            }
        }

        if Task.isCancelled {
            self.state = .cancelled
            self.statusMessage = "Scanning cancelled"
            return
        }

        guard !discoveredItems.isEmpty else {
            self.state = .failed(message: "No supported media files found in the selected location.")
            self.statusMessage = "No media files found"
            return
        }

        // Fast header-only metadata extraction for dry-run preview
        self.statusMessage = "Reading capture timestamps for \(discoveredItems.count) files..."
        var parsedItems: [MediaItem] = []
        parsedItems.reserveCapacity(discoveredItems.count)

        for (index, var item) in discoveredItems.enumerated() {
            if Task.isCancelled {
                self.state = .cancelled
                self.statusMessage = "Scanning cancelled"
                return
            }

            let dateResult = exifParser.extractDate(from: item.sourceURL)
            item.captureDate = dateResult.date
            item.dateSource = dateResult.source
            parsedItems.append(item)

            if index % 25 == 0 {
                await Task.yield()
            }
        }

        self.preparedItems = parsedItems
        let preview = buildBatchPreview(sourceURLs: urls, items: parsedItems)
        self.state = .ready(preview: preview)
        self.statusMessage = "Ready to organize \(parsedItems.count) file\(parsedItems.count == 1 ? "" : "s")"
    }

    private func buildBatchPreview(sourceURLs: [URL], items: [MediaItem]) -> BatchPreview {
        var bucketCounts: [String: (count: Int, bytes: Int64)] = [:]
        var totalBytes: Int64 = 0

        for item in items {
            let date = item.captureDate ?? Date()
            let relPath = settings.relativeSubdirectory(for: date)
            let existing = bucketCounts[relPath] ?? (0, 0)
            bucketCounts[relPath] = (existing.count + 1, existing.bytes + item.fileSize)
            totalBytes += item.fileSize
        }

        let buckets = bucketCounts.map { key, value in
            FolderPreviewBucket(relativePath: key, fileCount: value.count, totalBytes: value.bytes)
        }.sorted { $0.relativePath < $1.relativePath }

        let destinationRoot = settings.destinationURL
        let sampleItems = items.prefix(50).map { item -> MediaItem in
            var copy = item
            let date = item.captureDate ?? Date()
            let relPath = settings.relativeSubdirectory(for: date)
            copy.targetURL = destinationRoot
                .appendingPathComponent(relPath, isDirectory: true)
                .appendingPathComponent(item.fileName)
            return copy
        }

        return BatchPreview(
            sourceURLs: sourceURLs,
            totalFiles: items.count,
            totalBytes: totalBytes,
            folderBuckets: buckets,
            sampleItems: sampleItems
        )
    }

    // MARK: - Phase 2: Copy Pipeline

    private func runCopyPipeline() async {
        let startTime = Date()
        let itemsToProcess = self.preparedItems
        let totalCount = itemsToProcess.count

        self.processedItems.removeAll()
        self.recentItems.removeAll()
        self.progress = 0.0
        self.statusMessage = "Starting organization of \(totalCount) files..."

        let destinationRoot = settings.destinationURL
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            self.state = .failed(message: "Could not create destination directory: \(error.localizedDescription)")
            self.statusMessage = "Destination error"
            return
        }

        var copiedCount = 0
        var skippedCount = 0
        var renamedCount = 0
        var errorCount = 0
        var totalBytesProcessed: Int64 = 0

        for (index, item) in itemsToProcess.enumerated() {
            if Task.isCancelled {
                self.state = .cancelled
                self.statusMessage = "Organization cancelled by user"
                return
            }

            self.currentFileName = item.fileName
            self.state = .processing(current: index + 1, total: totalCount, currentFileName: item.fileName)
            self.statusMessage = "Processing \(index + 1) of \(totalCount): \(item.fileName)"
            self.progress = Double(index) / Double(totalCount)

            var processedItem = item
            let captureDate: Date
            if let existingDate = item.captureDate {
                captureDate = existingDate
            } else {
                let dateResult = exifParser.extractDate(from: item.sourceURL)
                captureDate = dateResult.date
                processedItem.captureDate = dateResult.date
                processedItem.dateSource = dateResult.source
            }

            // Compute target subdirectory using current settings
            let relativeSubdir = settings.relativeSubdirectory(for: captureDate)
            let targetDirectory = destinationRoot.appendingPathComponent(relativeSubdir, isDirectory: true)

            if !fileManager.fileExists(atPath: targetDirectory.path(percentEncoded: false)) {
                do {
                    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
                } catch {
                    errorCount += 1
                    processedItem.status = .failed(error: error.localizedDescription)
                    recordProcessedItem(processedItem)
                    continue
                }
            }

            let initialTargetURL = targetDirectory.appendingPathComponent(item.fileName)

            let resolution = duplicateResolver.resolve(
                sourceURL: item.sourceURL,
                targetURL: initialTargetURL,
                policy: settings.duplicatePolicy,
                fileManager: fileManager
            )

            do {
                switch resolution {
                case .copy(let destination):
                    try fileManager.copyItem(at: item.sourceURL, to: destination)
                    processedItem.targetURL = destination
                    processedItem.status = .copied(destination: destination)
                    copiedCount += 1
                    totalBytesProcessed += item.fileSize

                case .rename(let destination):
                    try fileManager.copyItem(at: item.sourceURL, to: destination)
                    processedItem.targetURL = destination
                    processedItem.status = .renamed(destination: destination)
                    renamedCount += 1
                    totalBytesProcessed += item.fileSize

                case .skip(let existing):
                    processedItem.targetURL = existing
                    processedItem.status = .skipped(reason: "Identical file already exists at destination")
                    skippedCount += 1

                case .overwrite(let destination):
                    if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.copyItem(at: item.sourceURL, to: destination)
                    processedItem.targetURL = destination
                    processedItem.status = .copied(destination: destination)
                    copiedCount += 1
                    totalBytesProcessed += item.fileSize
                }
            } catch {
                errorCount += 1
                processedItem.status = .failed(error: error.localizedDescription)
            }

            recordProcessedItem(processedItem)

            if index % 10 == 0 {
                await Task.yield()
            }
        }

        self.progress = 1.0

        let duration = Date().timeIntervalSince(startTime)
        let report = OrganizationReport(
            totalFound: totalCount,
            copiedCount: copiedCount,
            skippedCount: skippedCount,
            renamedCount: renamedCount,
            errorCount: errorCount,
            totalBytesProcessed: totalBytesProcessed,
            destinationDirectory: destinationRoot,
            durationSeconds: duration
        )

        self.lastReport = report
        self.state = .completed(report: report)
        self.statusMessage = "Successfully organized \(copiedCount + renamedCount) files"
    }

    private func recordProcessedItem(_ item: MediaItem) {
        processedItems.append(item)
        recentItems.insert(item, at: 0)
        if recentItems.count > 8 {
            recentItems.removeLast()
        }
    }

    private func cancelActiveTaskOnly() {
        activeTask?.cancel()
        activeTask = nil
    }
}
