import Foundation
import Observation

/// Preset choices for the chronological directory hierarchy.
public enum StructureFormatPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case yearThenDate = "yyyy/yyyy-MM-dd"
    case yearMonthDay = "yyyy/MM/dd"
    case flatDate = "yyyy-MM-dd"
    case yearMonthNameDay = "yyyy/MM - MMMM/yyyy-MM-dd"
    case custom = "Custom"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .yearThenDate:
            return "YYYY / YYYY-MM-DD (Recommended)"
        case .yearMonthDay:
            return "YYYY / MM / DD"
        case .flatDate:
            return "YYYY-MM-DD (Flat)"
        case .yearMonthNameDay:
            return "YYYY / MM - Month / YYYY-MM-DD"
        case .custom:
            return "Custom Pattern"
        }
    }

    public var examplePath: String {
        switch self {
        case .yearThenDate:
            return "2024/2024-08-15/IMG_0001.JPG"
        case .yearMonthDay:
            return "2024/08/15/IMG_0001.JPG"
        case .flatDate:
            return "2024-08-15/IMG_0001.JPG"
        case .yearMonthNameDay:
            return "2024/08 - August/2024-08-15/IMG_0001.JPG"
        case .custom:
            return "User Defined"
        }
    }
}

/// Strategy for resolving filename collisions at the destination.
public enum DuplicatePolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case skipIdentical = "Skip Identical"
    case renameWithSuffix = "Always Rename with Suffix"
    case overwrite = "Overwrite Destination"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .skipIdentical:
            return "Skips copying if an identical file (size + content) already exists. If different, renames with a numeric suffix (e.g. _1)."
        case .renameWithSuffix:
            return "Appends an incremental number suffix (e.g. photo_1.jpg) whenever any file with that name exists."
        case .overwrite:
            return "Overwrites any existing file at the destination with the new copy."
        }
    }
}

/// User settings for Datwig file organization.
@Observable
public final class OrganizationSettings: @unchecked Sendable {
    public static let shared = OrganizationSettings()

    // Keys for UserDefaults
    private enum Keys {
        static let destinationPath = "datwig.destinationPath"
        static let formatPreset = "datwig.formatPreset"
        static let customFormatPattern = "datwig.customFormatPattern"
        static let duplicatePolicy = "datwig.duplicatePolicy"
        static let includeSubdirectories = "datwig.includeSubdirectories"
    }

    /// Root folder where organized media files will be placed.
    public var destinationURL: URL {
        didSet {
            UserDefaults.standard.set(destinationURL.path(percentEncoded: false), forKey: Keys.destinationPath)
        }
    }

    /// Chronological directory hierarchy structure preset.
    public var formatPreset: StructureFormatPreset {
        didSet {
            UserDefaults.standard.set(formatPreset.rawValue, forKey: Keys.formatPreset)
        }
    }

    /// Custom date format pattern when preset is `.custom`.
    public var customFormatPattern: String {
        didSet {
            UserDefaults.standard.set(customFormatPattern, forKey: Keys.customFormatPattern)
        }
    }

    /// Policy for duplicate resolution.
    public var duplicatePolicy: DuplicatePolicy {
        didSet {
            UserDefaults.standard.set(duplicatePolicy.rawValue, forKey: Keys.duplicatePolicy)
        }
    }

    /// Whether to scan subdirectories recursively.
    public var includeSubdirectories: Bool {
        didSet {
            UserDefaults.standard.set(includeSubdirectories, forKey: Keys.includeSubdirectories)
        }
    }

    public init() {
        // Default destination: ~/Pictures/Datwig
        let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        let defaultDestination = picturesDirectory.appendingPathComponent("Datwig", isDirectory: true)

        if let savedPath = UserDefaults.standard.string(forKey: Keys.destinationPath), !savedPath.isEmpty {
            self.destinationURL = URL(fileURLWithPath: savedPath, isDirectory: true)
        } else {
            self.destinationURL = defaultDestination
        }

        if let savedPresetRaw = UserDefaults.standard.string(forKey: Keys.formatPreset),
           let savedPreset = StructureFormatPreset(rawValue: savedPresetRaw) {
            self.formatPreset = savedPreset
        } else {
            self.formatPreset = .yearThenDate
        }

        self.customFormatPattern = UserDefaults.standard.string(forKey: Keys.customFormatPattern) ?? "yyyy/yyyy-MM-dd"

        if let savedPolicyRaw = UserDefaults.standard.string(forKey: Keys.duplicatePolicy),
           let savedPolicy = DuplicatePolicy(rawValue: savedPolicyRaw) {
            self.duplicatePolicy = savedPolicy
        } else {
            self.duplicatePolicy = .skipIdentical
        }

        if UserDefaults.standard.object(forKey: Keys.includeSubdirectories) != nil {
            self.includeSubdirectories = UserDefaults.standard.bool(forKey: Keys.includeSubdirectories)
        } else {
            self.includeSubdirectories = true
        }
    }

    /// Calculates the destination relative subfolder path for a given capture date.
    public func relativeSubdirectory(for date: Date) -> String {
        let pattern: String
        switch formatPreset {
        case .custom:
            pattern = customFormatPattern.isEmpty ? "yyyy/yyyy-MM-dd" : customFormatPattern
        default:
            pattern = formatPreset.rawValue
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Formatted preview path demonstrating how a sample file would be structured.
    public func previewPath(sampleFileName: String = "IMG_0042.JPG") -> String {
        let sampleDate = Calendar.current.date(from: DateComponents(year: 2024, month: 8, day: 15, hour: 14, minute: 30)) ?? Date()
        let sub = relativeSubdirectory(for: sampleDate)
        return "\(destinationURL.lastPathComponent)/\(sub)/\(sampleFileName)"
    }

    /// Resets all settings to their recommended default values.
    public func resetToDefaults() {
        let picturesDirectory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
        self.destinationURL = picturesDirectory.appendingPathComponent("Datwig", isDirectory: true)
        self.formatPreset = .yearThenDate
        self.customFormatPattern = "yyyy/yyyy-MM-dd"
        self.duplicatePolicy = .skipIdentical
        self.includeSubdirectories = true
    }
}
