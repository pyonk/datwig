import SwiftUI
import AppKit

/// The application entry point for Datwig.
@main
struct DatwigApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private var isReadyToStart: Bool {
        if case .ready = DateOrganizer.shared.state {
            return true
        }
        return false
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 720, height: 620)
        .commands {
            // Standard File Commands
            CommandGroup(replacing: .newItem) {
                Button("Select Source Directory or File...") {
                    DateOrganizer.shared.selectSourceViaPicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Organization Control Commands
            CommandMenu("Organize") {
                Button("Start Organizing") {
                    DateOrganizer.shared.confirmAndStart()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isReadyToStart)

                Divider()

                Button("Cancel Current Operation") {
                    DateOrganizer.shared.cancel()
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!DateOrganizer.shared.state.isBusy)

                Button("Reset / New Batch") {
                    DateOrganizer.shared.reset()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

/// App delegate handling application lifecycle and dock events.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure standard modern appearance and clean window management
        NSApp.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        // Support dropping files/folders onto the Dock icon
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        Task { @MainActor in
            DateOrganizer.shared.startProcessing(urls: urls)
        }
    }
}
