import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum PreviewDisplayMode: String, CaseIterable, Identifiable {
    case folders = "Folder Summary"
    case files = "File Preview"

    var id: String { rawValue }
}

private enum LogFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case copied = "Copied"
    case renamed = "Renamed"
    case skipped = "Skipped"
    case failed = "Errors"

    var id: String { rawValue }
}

/// The primary user interface of Datwig featuring a drag-and-drop landing target,
/// native file picker invocation, pre-copy confirmation preview, live progress tracking,
/// and searchable post-processing reports.
public struct ContentView: View {
    @Bindable var organizer = DateOrganizer.shared
    @State private var isTargetedForDrop: Bool = false
    @State private var showingSettings: Bool = false
    @State private var previewMode: PreviewDisplayMode = .folders
    @State private var logFilter: LogFilter = .all
    @State private var logSearchText: String = ""
    @State private var didCopyLog: Bool = false

    public init() {}

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.3"
        return "v\(short)"
    }

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
        .frame(minWidth: 640, idealWidth: 720, minHeight: 520, idealHeight: 620)
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: organizer.settings.destinationURL) { _, _ in
            organizer.refreshPreview()
        }
        .onChange(of: organizer.settings.formatPreset) { _, _ in
            organizer.refreshPreview()
        }
        .onChange(of: organizer.settings.customFormatPattern) { _, _ in
            organizer.refreshPreview()
        }
        .onChange(of: organizer.state) { _, newState in
            switch newState {
            case .ready:
                previewMode = .folders
            case .completed, .cancelled:
                logFilter = .all
                logSearchText = ""
                didCopyLog = false
            default:
                break
            }
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
                    Text(appVersionLabel)
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

        case .ready(let preview):
            readyConfirmationView(preview: preview)

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
                        Text(isTargetedForDrop ? "Release to Preview Media" : "Drop Media Files or Folders Here")
                            .font(.title3.weight(.medium))

                        Text("Drag an SD card, camera DCIM folder, or video/image files")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Files will be scanned and previewed before any copy begins")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
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

            Text("Discovered \(count) media file\(count == 1 ? "" : "s") so far — no files modified yet")
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

    // MARK: - Ready Confirmation View (Dry-Run Preview)

    private func readyConfirmationView(preview: BatchPreview) -> some View {
        VStack(spacing: 14) {
            // Source & Target Plan Summary Card
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Ready to Organize: \(preview.sourceDisplayName)")
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text("\(preview.totalFiles) file\(preview.totalFiles == 1 ? "" : "s") • \(preview.formattedTotalBytes)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }

                        Text("Source: \(preview.sourceFullPathDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Divider()

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Structure: \(organizer.settings.formatPreset.displayName)")
                            .font(.caption.weight(.medium))
                        Text("Duplicates: \(organizer.settings.duplicatePolicy.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Adjust Settings...") {
                        showingSettings = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Preview Mode Switcher
            HStack {
                Picker("Preview Mode", selection: $previewMode) {
                    Text("Folder Plan (\(preview.folderBuckets.count))")
                        .tag(PreviewDisplayMode.folders)
                    Text("File Preview (\(preview.totalFiles))")
                        .tag(PreviewDisplayMode.files)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)

                Spacer()

                Text("Non-destructive copy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)

            // Scrollable Preview Table
            Group {
                if previewMode == .folders {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(preview.folderBuckets) { bucket in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 18)

                                    Text(bucket.relativePath)
                                        .font(.system(.caption, design: .monospaced).weight(.medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    Text("\(bucket.fileCount) file\(bucket.fileCount == 1 ? "" : "s")")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Text(bucket.formattedBytes)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 68, alignment: .trailing)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(10)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(preview.sampleItems) { item in
                                let targetSubdir = organizer.settings.relativeSubdirectory(for: item.captureDate ?? Date())
                                HStack(spacing: 10) {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.fileName)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text("\(item.formattedCaptureDate) • \(item.dateSource?.rawValue ?? "Unknown")")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text("→ \(targetSubdir)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(Color.accentColor)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            if preview.totalFiles > preview.sampleItems.count {
                                Text("Showing first \(preview.sampleItems.count) of \(preview.totalFiles) files. All files will be organized.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 6)
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            // Confirmation Action Buttons
            HStack(spacing: 12) {
                Button("Cancel / Choose Different Source") {
                    organizer.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Spacer()

                Button {
                    organizer.confirmAndStart()
                } label: {
                    Label("Start Organizing (\(preview.totalFiles) file\(preview.totalFiles == 1 ? "" : "s"))", systemImage: "play.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
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
        VStack(spacing: 14) {
            // Compact Header Summary
            HStack(spacing: 12) {
                Image(systemName: report.errorCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(report.errorCount > 0 ? .orange : .green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Organization Completed")
                        .font(.title3.bold())
                    Text("Processed \(report.totalFound) files into \(report.destinationDirectory.lastPathComponent) in \(report.formattedDuration) (\(report.formattedTotalBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Metric Cards Grid
            HStack(spacing: 10) {
                statBox(title: "Copied", value: "\(report.copiedCount)", icon: "arrow.down.doc.fill", color: .blue)
                statBox(title: "Renamed", value: "\(report.renamedCount)", icon: "doc.badge.plus", color: .orange)
                statBox(title: "Skipped", value: "\(report.skippedCount)", icon: "equal.circle.fill", color: .purple)
                if report.errorCount > 0 {
                    statBox(title: "Errors", value: "\(report.errorCount)", icon: "exclamationmark.triangle.fill", color: .red)
                }
            }
            .padding(.horizontal, 24)

            // Filterable & Exportable Post-Processing Log
            processingLogSection(destinationRoot: report.destinationDirectory)
                .padding(.horizontal, 24)

            // Bottom Primary Actions
            HStack(spacing: 12) {
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
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.bold())
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Post-Processing Detailed Log Section

    private var filteredLogItems: [MediaItem] {
        let query = logSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return organizer.processedItems.filter { item in
            let matchesFilter: Bool
            switch logFilter {
            case .all:
                matchesFilter = true
            case .copied:
                if case .copied = item.status { matchesFilter = true } else { matchesFilter = false }
            case .renamed:
                if case .renamed = item.status { matchesFilter = true } else { matchesFilter = false }
            case .skipped:
                if case .skipped = item.status { matchesFilter = true } else { matchesFilter = false }
            case .failed:
                if case .failed = item.status { matchesFilter = true } else { matchesFilter = false }
            }

            guard matchesFilter else { return false }
            guard !query.isEmpty else { return true }

            let haystack = [
                item.fileName,
                item.formattedCaptureDate,
                item.dateSource?.rawValue ?? "",
                item.targetURL?.path(percentEncoded: false) ?? "",
                item.sourceURL.path(percentEncoded: false)
            ].joined(separator: " ").lowercased()

            return haystack.contains(query)
        }
    }

    private func processingLogSection(destinationRoot: URL) -> some View {
        let items = filteredLogItems

        return VStack(spacing: 8) {
            // Log Toolbar: Filter + Search + Copy/Save
            HStack(spacing: 8) {
                Picker("Filter", selection: $logFilter) {
                    ForEach(LogFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)

                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search log...", text: $logSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )

                Button {
                    copyLogToPasteboard()
                } label: {
                    Label(didCopyLog ? "Copied" : "Copy", systemImage: didCopyLog ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    saveLogToFile()
                } label: {
                    Label("Save...", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Scrollable File Log List
            Group {
                if items.isEmpty {
                    VStack(spacing: 6) {
                        Text(organizer.processedItems.isEmpty ? "No files were processed." : "No log entries match the current filter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(items) { item in
                                logItemRow(item, destinationRoot: destinationRoot)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func logItemRow(_ item: MediaItem, destinationRoot: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForStatus(item.status))
                .foregroundStyle(colorForStatus(item.status))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.fileName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(badgeTextForStatus(item.status))
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(colorForStatus(item.status).opacity(0.15))
                        .foregroundStyle(colorForStatus(item.status))
                        .clipShape(Capsule())
                }

                Text(detailLineForLogItem(item, destinationRoot: destinationRoot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.formattedCaptureDate)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let source = item.dateSource {
                    Text(source.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func badgeTextForStatus(_ status: MediaProcessingStatus) -> String {
        switch status {
        case .copied: return "COPIED"
        case .renamed: return "RENAMED"
        case .skipped: return "SKIPPED"
        case .failed: return "ERROR"
        case .pending, .copying: return "PENDING"
        }
    }

    private func detailLineForLogItem(_ item: MediaItem, destinationRoot: URL) -> String {
        let rootPath = destinationRoot.path(percentEncoded: false)
        func relativeTarget(_ url: URL) -> String {
            let full = url.path(percentEncoded: false)
            if full.hasPrefix(rootPath) {
                let stripped = String(full.dropFirst(rootPath.count))
                return stripped.hasPrefix("/") ? String(stripped.dropFirst()) : stripped
            }
            return full
        }

        switch item.status {
        case .copied(let dest):
            return "→ \(relativeTarget(dest))"
        case .renamed(let dest):
            return "→ \(relativeTarget(dest)) (renamed to avoid conflict)"
        case .skipped(let reason):
            if let target = item.targetURL {
                return "\(reason) (\(relativeTarget(target)))"
            }
            return reason
        case .failed(let err):
            return "Error: \(err)"
        case .pending, .copying:
            return item.sourceURL.path(percentEncoded: false)
        }
    }

    private func copyLogToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(organizer.exportLogText(), forType: .string)
        didCopyLog = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopyLog = false
        }
    }

    private func saveLogToFile() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"

        let panel = NSSavePanel()
        panel.title = "Save Datwig Processing Log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "datwig-log-\(formatter.string(from: Date())).txt"

        if panel.runModal() == .OK, let url = panel.url {
            try? organizer.exportLogText().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Cancelled & Failed Views

    private var cancelledView: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Organization Cancelled")
                        .font(.title3.bold())
                    Text("The operation was stopped. Source files are untouched and completed copies remain intact.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            if !organizer.processedItems.isEmpty {
                processingLogSection(destinationRoot: organizer.settings.destinationURL)
                    .padding(.horizontal, 24)
            } else {
                Spacer()
            }

            Button("Start Over") {
                organizer.reset()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 18)
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
