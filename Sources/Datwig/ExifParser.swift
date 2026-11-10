import Foundation
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

/// Identifies the metadata source from which the capture timestamp was resolved.
public enum DateSource: String, Sendable, CaseIterable {
    case exifDateTimeOriginal = "EXIF DateTimeOriginal"
    case exifDateTimeDigitized = "EXIF DateTimeDigitized"
    case tiffDateTime = "TIFF DateTime"
    case iptcDateTime = "IPTC Date/Time"
    case videoMetadata = "Video Creation Date"
    case fileCreationDate = "File Creation Date"
    case fileModificationDate = "File Modification Date"
    case fallbackCurrentDate = "Current Date (Fallback)"
}

/// The result of a capture date extraction operation.
public struct ExtractedDateResult: Sendable, Equatable {
    public let date: Date
    public let source: DateSource
    public let rawString: String?

    public init(date: Date, source: DateSource, rawString: String? = nil) {
        self.date = date
        self.source = source
        self.rawString = rawString
    }
}

/// Fast, lightweight metadata parser utilizing `ImageIO` without fully loading image bitmaps into memory.
public final class ExifParser: Sendable {
    public static let shared = ExifParser()

    public init() {}

    /// Extracts the capture timestamp from the specified file URL.
    ///
    /// Fallback hierarchy:
    /// 1. `kCGImagePropertyExifDateTimeOriginal`
    /// 2. `kCGImagePropertyExifDateTimeDigitized`
    /// 3. `kCGImagePropertyTIFFDateTime`
    /// 4. IPTC Date/Time Created
    /// 5. Video QuickTime/ISO metadata creation date (for video formats)
    /// 6. File creation date (`attributes[.creationDate]`)
    /// 7. File modification date (`attributes[.modificationDate]`)
    /// 8. Current date fallback
    public func extractDate(from url: URL) -> ExtractedDateResult {
        // 1. Attempt ImageIO extraction without decoding the bitmap into memory
        if let imageResult = extractFromImageIO(url: url) {
            return imageResult
        }

        // 2. Attempt Video metadata extraction if the file is a recognized video container
        if isVideoFile(url: url), let videoResult = extractFromVideo(url: url) {
            return videoResult
        }

        // 3. Fallback to file system attributes: creation date then modification date
        if let fileResult = extractFromFileSystem(url: url) {
            return fileResult
        }

        // 4. Final safety fallback
        return ExtractedDateResult(date: Date(), source: .fallbackCurrentDate)
    }

    // MARK: - ImageIO Extraction

    private func extractFromImageIO(url: URL) -> ExtractedDateResult? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            return nil
        }

        let propertyOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, propertyOptions as CFDictionary) as? [CFString: Any] else {
            return nil
        }

        // 1. Check EXIF Dictionary
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            // Priority 1: DateTimeOriginal
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let date = ExifDateParser.parse(dateString) {
                return ExtractedDateResult(date: date, source: .exifDateTimeOriginal, rawString: dateString)
            }

            // Priority 2: DateTimeDigitized
            if let dateString = exif[kCGImagePropertyExifDateTimeDigitized] as? String,
               let date = ExifDateParser.parse(dateString) {
                return ExtractedDateResult(date: date, source: .exifDateTimeDigitized, rawString: dateString)
            }
        }

        // 2. Check TIFF Dictionary
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let dateString = tiff[kCGImagePropertyTIFFDateTime] as? String,
               let date = ExifDateParser.parse(dateString) {
                return ExtractedDateResult(date: date, source: .tiffDateTime, rawString: dateString)
            }
        }

        // 3. Check IPTC Dictionary
        if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            if let dateString = iptc[kCGImagePropertyIPTCDateCreated] as? String {
                let timeString = iptc[kCGImagePropertyIPTCTimeCreated] as? String
                if let date = ExifDateParser.parseIPTC(date: dateString, time: timeString) {
                    let combined = [dateString, timeString].compactMap { $0 }.joined(separator: " ")
                    return ExtractedDateResult(date: date, source: .iptcDateTime, rawString: combined)
                }
            }
        }

        return nil
    }

    // MARK: - Video Metadata Extraction

    private func extractFromVideo(url: URL) -> ExtractedDateResult? {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let formats = asset.availableMetadataFormats

        for format in formats {
            let metadata = asset.metadata(forFormat: format)
            for item in metadata {
                if let commonKey = item.commonKey, commonKey == .commonKeyCreationDate {
                    if let dateVal = item.dateValue {
                        return ExtractedDateResult(date: dateVal, source: .videoMetadata, rawString: nil)
                    }
                    if let stringVal = item.stringValue, let parsed = ExifDateParser.parse(stringVal) {
                        return ExtractedDateResult(date: parsed, source: .videoMetadata, rawString: stringVal)
                    }
                }

                if let identifier = item.identifier,
                   identifier == .quickTimeMetadataCreationDate || identifier == .commonIdentifierCreationDate {
                    if let dateVal = item.dateValue {
                        return ExtractedDateResult(date: dateVal, source: .videoMetadata, rawString: nil)
                    }
                    if let stringVal = item.stringValue, let parsed = ExifDateParser.parse(stringVal) {
                        return ExtractedDateResult(date: parsed, source: .videoMetadata, rawString: stringVal)
                    }
                }
            }
        }

        return nil
    }

    // MARK: - File System Attributes Extraction

    private func extractFromFileSystem(url: URL) -> ExtractedDateResult? {
        do {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])

            // Priority: File creation date
            if let creationDate = values.creationDate {
                return ExtractedDateResult(date: creationDate, source: .fileCreationDate)
            }

            // Fallback: Modification date
            if let modDate = values.contentModificationDate {
                return ExtractedDateResult(date: modDate, source: .fileModificationDate)
            }
        } catch {
            // Attempt standard POSIX attributes if resourceValues fails
            let path = url.path(percentEncoded: false)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path) {
                if let creationDate = attributes[.creationDate] as? Date {
                    return ExtractedDateResult(date: creationDate, source: .fileCreationDate)
                }
                if let modDate = attributes[.modificationDate] as? Date {
                    return ExtractedDateResult(date: modDate, source: .fileModificationDate)
                }
            }
        }

        return nil
    }

    private func isVideoFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "3gp", "ts", "mts", "m2ts"]
        if videoExtensions.contains(ext) {
            return true
        }

        if let utType = UTType(filenameExtension: ext), utType.conforms(to: .movie) || utType.conforms(to: .video) {
            return true
        }

        return false
    }
}

// MARK: - Thread-Safe EXIF Date Parsing

/// High-performance, thread-safe date string parser for various camera and video EXIF date formats.
public enum ExifDateParser {
    // Thread-local or lazily initialized formatters using standard POSIX locale
    private static let iso8601WithMillis: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let customPatterns: [String] = [
        "yyyy:MM:dd HH:mm:ss",
        "yyyy:MM:dd HH:mm:ssZZZZZ",
        "yyyy:MM:dd HH:mm:ssxxx",
        "yyyy:MM:dd HH:mm:ssZ",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm:ssZZZZZ",
        "yyyy-MM-dd HH:mm:ssxxx",
        "yyyy:MM:dd",
        "yyyy-MM-dd",
        "yyyyMMdd HHmmss"
    ]

    /// Parses an EXIF or ISO timestamp string into a `Date`.
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Fast ISO 8601 attempts
        if let date = iso8601WithMillis.date(from: trimmed) {
            return date
        }
        if let date = iso8601Standard.date(from: trimmed) {
            return date
        }

        // Custom formatters with cached thread-local patterns
        for pattern in customPatterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        return nil
    }

    /// Parses IPTC separate date (`yyyyMMdd`) and time (`HHmmss` or `HHmmss+ZZZZ`) strings.
    public static func parseIPTC(date: String, time: String?) -> Date? {
        let cleanDate = date.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTime = time?.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines) ?? "000000"

        let combined = "\(cleanDate) \(cleanTime)"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let patterns = [
            "yyyyMMdd HHmmssZZZZZ",
            "yyyyMMdd HHmmssZ",
            "yyyyMMdd HHmmss",
            "yyyyMMdd"
        ]

        for pattern in patterns {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: combined) {
                return date
            }
        }

        return nil
    }
}
