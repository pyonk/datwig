import AppKit

/// Encapsulates native macOS `NSOpenPanel` dialogues for source selection and destination picking.
@MainActor
public enum DirectoryPicker {

    /// Displays a native macOS open panel allowing users to choose an SD card, camera root,
    /// media directory (e.g. DCIM), or an individual media file.
    ///
    /// Specifications:
    /// - `canChooseDirectories`: `true`
    /// - `canChooseFiles`: `true`
    /// - `allowsMultipleSelection`: `false`
    ///
    /// - Returns: The chosen `URL` if the user confirmed, or `nil` if cancelled.
    public static func pickSource() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select Source Directory or Media File"
        panel.message = "Select an SD card (e.g. DCIM folder), camera volume, or media file to organize."
        panel.prompt = "Select"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    /// Displays a directory chooser panel allowing users to set their preferred destination root folder.
    ///
    /// - Parameter currentDestination: The current destination directory to pre-select in the panel.
    /// - Returns: The chosen directory `URL` if confirmed, or `nil` if cancelled.
    public static func pickDestination(currentDestination: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Destination Directory"
        panel.message = "Select the folder where Datwig will build the chronological directory tree."
        panel.prompt = "Set Destination"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        if let current = currentDestination {
            panel.directoryURL = current
        }

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}
