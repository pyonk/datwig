import SwiftUI
import AppKit

/// The primary user interface of Datwig featuring a drag-and-drop landing target,
/// native file picker invocation, live progress tracking, and batch reports.
public struct ContentView: View {
    @Bindable var organizer = DateOrganizer.shared
    @State private var isTargetedForDrop: Bool = false
    @State private var showingSettings: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Dynamic Content Area based on state
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom Status / Destination Bar
            bottomBar
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 460, idealHeight: 520)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            DatwigIconView(size: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Datwig")
                        .font(.headline)
                    Text("v1.0")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("Native Chronological Media Organizer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if organizer.state.isBusy {
                Button(role: .destructive) {
                    organizer.cancel()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Preferences (⌘,)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Main Dynamic Content Area

    @ViewBuilder
    private var mainContent: some View {
        switch organizer.state {
        case .idle:
            idleDropZoneView

        case .scanning(let count):
            scanningView(count: count)

        case .processing(let current, let total, let currentFileName):
            processingView(current: current, total: total, fileName: currentFileName)

        case .completed(let report):
            completedView(report: report)

        case .cancelled:
            cancelledView

        case .failed(let message):
            failedView(message: message)
        }
    }

    // MARK: - Idle Drop Zone View

    private var idleDropZoneView: some View {
        VStack(spacing: 24) {
            // Drop Box Target
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isTargetedForDrop ? 3 : 2, dash: isTargetedForDrop ? [] : [8, 6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargetedForDrop ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    )

                VStack(spacing: 16) {
                    Image(systemName: isTargetedForDrop ? "arrow.down.doc.fill" : "photo.stack")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(isTargetedForDrop ? Color.accentColor : Color.secondary)
                        .scaleEffect(isTargetedForDrop ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTargetedForDrop)

                    VStack(spacing: 6) {
                        Text(isTargetedForDrop ? "Release to Ingest Media" : "Drop Media Files or Folders Here")
                            .font(.title3.weight(.medium))

                        Text("Drag an SD card, camera DCIM folder, or video/image files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                        Text("OR")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                    .frame(width: 240)
                    .padding(.vertical, 2)

                    // Prominent [Select Directory...] Button triggering NSOpenPanel
                    Button {
                        organizer.selectSourceViaPicker()
                    } label: {
                        Label("Select Directory...", systemImage: "folder.badge.plus")
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Open File Dialog (⌘O)")
                }
                .padding(32)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .dropDestination(for: URL.self) { items, _ in
                organizer.handleDrop(urls: items)
                return true
            } isTargeted: { targeted in
                self.isTargetedForDrop = targeted
            }
        }
    }

    // MARK: - Scanning View

    private func scanningView(count: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text("Scanning Source...")
                .font(.title3.weight(.medium))

            Text("Discovered \(count) media file\(count == 1 ? "" : "s") so far")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel Scanning") {
                organizer.cancel()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Processing View

    private func processingView(current: Int, total: Int, fileName: String) -> some View {
        VStack(spacing: 20) {
            // Top Status Block
            VStack(spacing: 8) {
                HStack {
                    Text("Organizing Media")
                        .font(.headline)
                    Spacer()
                    Text("\(current) of \(total)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: organizer.progress)
                    .progressViewStyle(.linear)

                HStack {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.0f%%", organizer.progress * 100))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 28)

            // Live Activity Stream
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Activity")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(organizer.recentItems) { item in
                            recentItemRow(item)
                        }
                    }
                    .padding(.horizontal, 28)
                }
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private func recentItemRow(_ item: MediaItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForStatus(item.status))
                .foregroundStyle(colorForStatus(item.status))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let target = item.targetURL {
                    Text(target.deletingLastPathComponent().lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let source = item.dateSource {
                Text(source.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Completed View

    private func completedView(report: OrganizationReport) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Organization Completed")
                    .font(.title2.bold())
                Text("Organized \(report.copiedCount + report.renamedCount) files into chronological tree in \(report.formattedDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Metric Cards Grid
            HStack(spacing: 12) {
                statBox(title: "Copied", value: "\(report.copiedCount)", icon: "arrow.down.doc.fill", color: .blue)
                statBox(title: "Renamed", value: "\(report.renamedCount)", icon: "doc.badge.plus", color: .orange)
                statBox(title: "Skipped", value: "\(report.skippedCount)", icon: "equal.circle.fill", color: .purple)
                if report.errorCount > 0 {
                    statBox(title: "Errors", value: "\(report.errorCount)", icon: "exclamationmark.triangle.fill", color: .red)
                }
            }
            .padding(.horizontal, 28)

            HStack(spacing: 14) {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: report.destinationDirectory.path(percentEncoded: false))
                } label: {
                    Label("Show in Finder", systemImage: "folder.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Organize More Media") {
                    organizer.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Cancelled & Failed Views

    private var cancelledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Organization Cancelled")
                .font(.title3.bold())

            Text("The operation was stopped by user. Partial copies remain safely intact.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Start Over") {
                organizer.reset()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            Text("Organization Encountered an Issue")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Dismiss & Try Again") {
                organizer.reset()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Destination:")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(organizer.settings.destinationURL.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button("Change...") {
                if let newDestination = DirectoryPicker.pickDestination(currentDestination: organizer.settings.destinationURL) {
                    organizer.settings.destinationURL = newDestination
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(organizer.state.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private func iconForStatus(_ status: MediaProcessingStatus) -> String {
        switch status {
        case .pending, .copying:
            return "clock"
        case .copied:
            return "checkmark.circle.fill"
        case .renamed:
            return "doc.badge.plus"
        case .skipped:
            return "equal.circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func colorForStatus(_ status: MediaProcessingStatus) -> Color {
        switch status {
        case .pending, .copying:
            return .secondary
        case .copied:
            return .green
        case .renamed:
            return .orange
        case .skipped:
            return .purple
        case .failed:
            return .red
        }
    }
}

/// Renders the official Datwig app icon, with graceful fallback to system symbols.
public struct DatwigIconView: View {
    public var size: CGFloat

    public init(size: CGFloat = 36) {
        self.size = size
    }

    public var body: some View {
        if let icon = loadAppIcon() {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.tint)
            }
            .frame(width: size, height: size)
        }
    }

    private func loadAppIcon() -> NSImage? {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return nil
    }
}
