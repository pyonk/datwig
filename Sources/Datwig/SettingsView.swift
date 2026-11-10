import SwiftUI

/// Settings sheet allowing users to customize destination directory, directory tree format, and duplicate handling.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings = OrganizationSettings.shared

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            formatTab
                .tabItem {
                    Label("Organization", systemImage: "folder.badge.gearshape")
                }

            duplicateTab
                .tabItem {
                    Label("Duplicates", systemImage: "doc.on.doc")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 520, height: 380)
        .padding()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Destination Root Folder")
                        .font(.headline)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.destinationURL.lastPathComponent)
                                .font(.body.weight(.medium))
                            Text(settings.destinationURL.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Change...") {
                            if let newURL = DirectoryPicker.pickDestination(currentDestination: settings.destinationURL) {
                                settings.destinationURL = newURL
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button("Reset to Default (~/Pictures/Datwig)") {
                        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
                            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures")
                        settings.destinationURL = pictures.appendingPathComponent("Datwig", isDirectory: true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Toggle("Include subdirectories when scanning folders", isOn: $settings.includeSubdirectories)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Format Tab

    private var formatTab: some View {
        Form {
            Section {
                Picker("Folder Hierarchy:", selection: $settings.formatPreset) {
                    ForEach(StructureFormatPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                if settings.formatPreset == .custom {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Custom Date Format:", text: $settings.customFormatPattern)
                            .textFieldStyle(.roundedBorder)
                        Text("Tokens: yyyy (Year), MM (Month number), MMMM (Month name), dd (Day)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Directory Structure")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live Preview:")
                        .font(.caption.bold())
                    Text(settings.previewPath())
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Duplicates Tab

    private var duplicateTab: some View {
        Form {
            Section {
                Picker("Collision Action:", selection: $settings.duplicatePolicy) {
                    ForEach(DuplicatePolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.duplicatePolicy.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } header: {
                Text("File Name Conflicts")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 14) {
            DatwigIconView(size: 64)

            VStack(spacing: 4) {
                Text("Datwig")
                    .font(.title2.bold())
                Text("pronounced /ˈdeɪt wɪɡ/")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("A modern, ultra-lightweight, native macOS rewrite and spiritual successor to DateTree. Built with 100% native Swift & SwiftUI, optimized for Apple Silicon with zero third-party dependencies.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target:")
                        .font(.caption.bold())
                    Text("macOS 14.0+ (Sonoma, Sequoia)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("License:")
                        .font(.caption.bold())
                    Text("MIT Open Source")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
