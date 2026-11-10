import Foundation
import CommonCrypto

/// Result of evaluating a potential file collision at the destination.
public enum CollisionResolution: Sendable, Equatable {
    case copy(destination: URL)
    case skip(existing: URL)
    case rename(destination: URL)
    case overwrite(destination: URL)
}

/// Resolves file collisions safely and non-destructively based on user policy.
public final class DuplicateResolver: Sendable {
    public static let shared = DuplicateResolver()

    public init() {}

    /// Determines the action to take when copying `sourceURL` to `targetURL`.
    public func resolve(
        sourceURL: URL,
        targetURL: URL,
        policy: DuplicatePolicy,
        fileManager: FileManager = .default
    ) -> CollisionResolution {
        let targetPath = targetURL.path(percentEncoded: false)

        // If no file exists at the target, simply copy
        guard fileManager.fileExists(atPath: targetPath) else {
            return .copy(destination: targetURL)
        }

        switch policy {
        case .overwrite:
            return .overwrite(destination: targetURL)

        case .renameWithSuffix:
            let uniqueURL = generateUniqueURL(for: targetURL, fileManager: fileManager)
            return .rename(destination: uniqueURL)

        case .skipIdentical:
            // Compare file sizes first
            guard let sourceSize = fileSize(of: sourceURL, fileManager: fileManager),
                  let targetSize = fileSize(of: targetURL, fileManager: fileManager) else {
                let uniqueURL = generateUniqueURL(for: targetURL, fileManager: fileManager)
                return .rename(destination: uniqueURL)
            }

            if sourceSize != targetSize {
                // Different size: definitely distinct files with the same name, rename to preserve
                let uniqueURL = generateUniqueURL(for: targetURL, fileManager: fileManager)
                return .rename(destination: uniqueURL)
            }

            // Sizes match: perform fast sample comparison to verify identity
            if areFilesIdentical(sourceURL: sourceURL, targetURL: targetURL, fileSize: sourceSize) {
                return .skip(existing: targetURL)
            } else {
                let uniqueURL = generateUniqueURL(for: targetURL, fileManager: fileManager)
                return .rename(destination: uniqueURL)
            }
        }
    }

    /// Generates a non-colliding destination URL by appending `_1`, `_2`, etc.
    public func generateUniqueURL(for targetURL: URL, fileManager: FileManager = .default) -> URL {
        let directory = targetURL.deletingLastPathComponent()
        let ext = targetURL.pathExtension
        let baseName = targetURL.deletingPathExtension().lastPathComponent

        var counter = 1
        while counter < 10_000 {
            let candidateFileName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let candidateURL = directory.appendingPathComponent(candidateFileName)

            if !fileManager.fileExists(atPath: candidateURL.path(percentEncoded: false)) {
                return candidateURL
            }
            counter += 1
        }

        // Fallback with UUID in the extreme case of 10,000 collisions
        let uuidSuffix = UUID().uuidString.prefix(8)
        let fallbackName = ext.isEmpty ? "\(baseName)_\(uuidSuffix)" : "\(baseName)_\(uuidSuffix).\(ext)"
        return directory.appendingPathComponent(fallbackName)
    }

    /// Fast, non-blocking check to determine if two files share identical content.
    /// Employs size checking and sampled chunk hashing (head + tail) to avoid reading gigabytes of video into RAM.
    public func areFilesIdentical(sourceURL: URL, targetURL: URL, fileSize: Int64) -> Bool {
        if fileSize == 0 {
            return true
        }

        guard let sourceHandle = try? FileHandle(forReadingFrom: sourceURL),
              let targetHandle = try? FileHandle(forReadingFrom: targetURL) else {
            return false
        }

        defer {
            try? sourceHandle.close()
            try? targetHandle.close()
        }

        let chunkSize = 64 * 1024 // 64 KB

        // 1. Compare head chunk
        do {
            let sourceHead = try sourceHandle.read(upToCount: chunkSize) ?? Data()
            let targetHead = try targetHandle.read(upToCount: chunkSize) ?? Data()
            if sourceHead != targetHead {
                return false
            }

            // If file is smaller than head chunk, they are identical
            if fileSize <= Int64(chunkSize) {
                return true
            }

            // 2. Compare tail chunk
            let tailOffset = max(0, UInt64(fileSize - Int64(chunkSize)))
            try sourceHandle.seek(toOffset: tailOffset)
            try targetHandle.seek(toOffset: tailOffset)

            let sourceTail = try sourceHandle.read(upToCount: chunkSize) ?? Data()
            let targetTail = try targetHandle.read(upToCount: chunkSize) ?? Data()
            if sourceTail != targetTail {
                return false
            }

            // 3. For medium-sized files under 10MB, compare middle chunk as well
            if fileSize > Int64(chunkSize * 2) {
                let midOffset = UInt64(fileSize / 2)
                try sourceHandle.seek(toOffset: midOffset)
                try targetHandle.seek(toOffset: midOffset)

                let sourceMid = try sourceHandle.read(upToCount: chunkSize) ?? Data()
                let targetMid = try targetHandle.read(upToCount: chunkSize) ?? Data()
                if sourceMid != targetMid {
                    return false
                }
            }

            return true
        } catch {
            return false
        }
    }

    private func fileSize(of url: URL, fileManager: FileManager) -> Int64? {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize {
            return Int64(size)
        }
        let path = url.path(percentEncoded: false)
        if let attrs = try? fileManager.attributesOfItem(atPath: path), let size = attrs[.size] as? Int64 {
            return size
        }
        return nil
    }
}
