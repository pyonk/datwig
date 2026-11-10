import Foundation
import UniformTypeIdentifiers

/// Fast directory traversal and media file discovery engine.
public final class FileScanner: Sendable {
    public static let shared = FileScanner()

    public static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tiff", "tif",
        "gif", "bmp", "webp", "raw", "cr2", "cr3", "nef",
        "arw", "dng", "orf", "rw2", "pef", "raf", "srw"
    ]

    public static let supportedVideoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "wmv", "flv", "3gp", "ts", "mts", "m2ts"
    ]

    public init() {}

    /// Checks if a file URL is recognized as a supported image or video format.
    public func isSupportedMediaFile(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if Self.supportedImageExtensions.contains(ext) || Self.supportedVideoExtensions.contains(ext) {
            return true
        }

        if let utType = UTType(filenameExtension: ext) {
            if utType.conforms(to: .image) || utType.conforms(to: .movie) || utType.conforms(to: .audiovisualContent) {
                return true
            }
        }

        return false
    }

    /// Scans a collection of dropped or selected URLs (directories or individual files) for media items.
    ///
    /// - Parameters:
    ///   - inputURLs: Array of source URLs.
    ///   - includeSubdirectories: Whether to recursively traverse child folders.
    ///   - onProgress: Optional callback invoked as files are discovered.
    /// - Returns: An array of discovered `MediaItem` instances.
    public func scan(
        inputURLs: [URL],
        includeSubdirectories: Bool = true,
        onProgress: (@Sendable (Int) -> Void)? = nil
    ) async -> [MediaItem] {
        var discovered: [MediaItem] = []
        var discoveredPaths: Set<String> = []
        let fileManager = FileManager.default

        for inputURL in inputURLs {
            if Task.isCancelled { break }

            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: inputURL.path(percentEncoded: false), isDirectory: &isDir) else {
                continue
            }

            if !isDir.boolValue {
                // Single file input
                let standardized = inputURL.standardizedFileURL
                if isSupportedMediaFile(url: standardized) && !discoveredPaths.contains(standardized.path(percentEncoded: false)) {
                    discoveredPaths.insert(standardized.path(percentEncoded: false))
                    let size = (try? standardized.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    discovered.append(MediaItem(sourceURL: standardized, fileSize: size))
                    onProgress?(discovered.count)
                }
            } else {
                // Directory input (e.g. SD Card, DCIM, or user folder)
                var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                if !includeSubdirectories {
                    options.insert(.skipsSubdirectoryDescendants)
                }

                guard let enumerator = fileManager.enumerator(
                    at: inputURL,
                    includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                    options: options,
                    errorHandler: { _, _ in true }
                ) else {
                    continue
                }

                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }

                    guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                          let isDirectory = values.isDirectory, !isDirectory else {
                        continue
                    }

                    let standardized = fileURL.standardizedFileURL
                    let path = standardized.path(percentEncoded: false)

                    if !discoveredPaths.contains(path) && isSupportedMediaFile(url: standardized) {
                        discoveredPaths.insert(path)
                        let size = Int64(values.fileSize ?? 0)
                        discovered.append(MediaItem(sourceURL: standardized, fileSize: size))

                        if discovered.count % 25 == 0 {
                            onProgress?(discovered.count)
                            // Yield cooperatively to keep main thread responsive
                            await Task.yield()
                        }
                    }
                }
            }
        }

        onProgress?(discovered.count)
        return discovered
    }
}
