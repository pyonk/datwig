import Foundation
import SwiftUI
import Observation

/// The high-level lifecycle state of the media organization pipeline.
public enum OrganizerState: Equatable, Sendable {
    case idle
    case scanning(discoveredCount: Int)
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
/// conflict resolution, and safe asynchronous copying.
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
    public private(set) var lastReport: OrganizationReport? = nil

    // MARK: - Dependencies

    public var settings: OrganizationSettings
    private let exifParser: ExifParser
    private let duplicateResolver: DuplicateResolver
    private let fileScanner: FileScanner

    // Internal execution task for cancellation
    private var activeTask: Task<Void, Never>? = nil

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

    // MARK: - Ingestion Entry Points

    /// Invokes the native macOS `NSOpenPanel` for user file/directory selection and routes into the pipeline.
    public func selectSourceViaPicker() {
        guard !state.isBusy else { return }

        if let selectedURL = DirectoryPicker.pickSource() {
            startProcessing(urls: [selectedURL])
        }
    }

    /// Receives drag-and-dropped file URLs and routes them into the common pipeline.
    public func handleDrop(urls: [URL]) {
        guard !state.isBusy else { return }
        guard !urls.isEmpty else { return }

        startProcessing(urls: urls)
    }

    /// Initiates the background ingestion and organization workflow.
    public func startProcessing(urls: [URL]) {
        cancel()

        activeTask = Task { [weak self] in
            await self?.runPipeline(urls: urls)
        }
    }

    /// Requests cooperative cancellation of the running organization task.
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
        cancel()
        state = .idle
        progress = 0.0
        statusMessage = "Ready to organize"
        currentFileName = ""
        recentItems.removeAll()
        lastReport = nil
    }

    // MARK: - Core Execution Pipeline

    private func runPipeline(urls: [URL]) async {
        let startTime = Date()
        self.state = .scanning(discoveredCount: 0)
        self.statusMessage = "Scanning files and folders..."
        self.progress = 0.0
        self.recentItems.removeAll()

        // Phase 1: File Discovery
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

        let totalCount = discoveredItems.count
        self.statusMessage = "Starting organization of \(totalCount) files..."

        // Ensure root destination folder exists
        let destinationRoot = settings.destinationURL
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        } catch {
            self.state = .failed(message: "Could not create destination directory: \(error.localizedDescription)")
            self.statusMessage = "Destination error"
            return
        }

        // Phase 2: Processing and Copying
        var copiedCount = 0
        var skippedCount = 0
        var renamedCount = 0
        var errorCount = 0
        var totalBytesProcessed: Int64 = 0

        for (index, item) in discoveredItems.enumerated() {
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

            // 1. Extract capture timestamp without loading entire image into memory
            let dateResult = exifParser.extractDate(from: item.sourceURL)
            processedItem.captureDate = dateResult.date
            processedItem.dateSource = dateResult.source

            // 2. Compute target subdirectory according to user formatting pattern
            let relativeSubdir = settings.relativeSubdirectory(for: dateResult.date)
            let targetDirectory = destinationRoot.appendingPathComponent(relativeSubdir, isDirectory: true)

            // 3. Ensure target date subfolder exists
            if !fileManager.fileExists(atPath: targetDirectory.path(percentEncoded: false)) {
                do {
                    try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
                } catch {
                    errorCount += 1
                    processedItem.status = .failed(error: error.localizedDescription)
                    recordRecentItem(processedItem)
                    continue
                }
            }

            let initialTargetURL = targetDirectory.appendingPathComponent(item.fileName)

            // 4. Resolve filename collisions safely and non-destructively
            let resolution = duplicateResolver.resolve(
                sourceURL: item.sourceURL,
                targetURL: initialTargetURL,
                policy: settings.duplicatePolicy,
                fileManager: fileManager
            )

            // 5. Execute safe copy
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

            recordRecentItem(processedItem)

            // Small cooperative yield every 10 items to maintain UI fluidity
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

    private func recordRecentItem(_ item: MediaItem) {
        recentItems.insert(item, at: 0)
        if recentItems.count > 8 {
            recentItems.removeLast()
        }
    }
}
