import Foundation

/// Current processing status of a media item in the organization pipeline.
public enum MediaProcessingStatus: Sendable, Equatable {
    case pending
    case copying
    case copied(destination: URL)
    case skipped(reason: String)
    case renamed(destination: URL)
    case failed(error: String)

    public var isSuccess: Bool {
        switch self {
        case .copied, .renamed:
            return true
        default:
            return false
        }
    }
}

/// Represents a media file discovered during scanning or queued for organization.
public struct MediaItem: Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public let fileName: String
    public let fileSize: Int64
    public var captureDate: Date?
    public var dateSource: DateSource?
    public var targetURL: URL?
    public var status: MediaProcessingStatus

    public init(
        id: UUID = UUID(),
        sourceURL: URL,
        fileName: String? = nil,
        fileSize: Int64 = 0,
        captureDate: Date? = nil,
        dateSource: DateSource? = nil,
        targetURL: URL? = nil,
        status: MediaProcessingStatus = .pending
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName ?? sourceURL.lastPathComponent
        self.fileSize = fileSize
        self.captureDate = captureDate
        self.dateSource = dateSource
        self.targetURL = targetURL
        self.status = status
    }

    /// Human-readable file size string (e.g. "24.5 MB").
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// File extension in lower case (e.g. "jpg", "cr3", "mp4").
    public var fileExtension: String {
        sourceURL.pathExtension.lowercased()
    }
}

/// Summary report emitted upon completion of an organization batch.
public struct OrganizationReport: Sendable, Equatable {
    public let totalFound: Int
    public let copiedCount: Int
    public let skippedCount: Int
    public let renamedCount: Int
    public let errorCount: Int
    public let totalBytesProcessed: Int64
    public let destinationDirectory: URL
    public let durationSeconds: TimeInterval

    public init(
        totalFound: Int,
        copiedCount: Int,
        skippedCount: Int,
        renamedCount: Int,
        errorCount: Int,
        totalBytesProcessed: Int64,
        destinationDirectory: URL,
        durationSeconds: TimeInterval
    ) {
        self.totalFound = totalFound
        self.copiedCount = copiedCount
        self.skippedCount = skippedCount
        self.renamedCount = renamedCount
        self.errorCount = errorCount
        self.totalBytesProcessed = totalBytesProcessed
        self.destinationDirectory = destinationDirectory
        self.durationSeconds = durationSeconds
    }

    public var formattedTotalBytes: String {
        ByteCountFormatter.string(fromByteCount: totalBytesProcessed, countStyle: .file)
    }

    public var formattedDuration: String {
        if durationSeconds < 1.0 {
            return String(format: "%.1f seconds", durationSeconds)
        } else if durationSeconds < 60.0 {
            return String(format: "%.0f seconds", durationSeconds)
        } else {
            let minutes = Int(durationSeconds) / 60
            let seconds = Int(durationSeconds) % 60
            return "\(minutes)m \(seconds)s"
        }
    }
}
