# Datwig

<p align="center">
  <strong>Native, ultra-lightweight chronological media organizer for macOS.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20(Sonoma%20%2F%20Sequoia)-000000?style=flat-square&logo=apple&logoColor=white" alt="Platform macOS 14+" />
  <img src="https://img.shields.io/badge/Language-Swift%205.9%2B-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift 5.9+" />
  <img src="https://img.shields.io/badge/UI-100%25%20SwiftUI-0071e3?style=flat-square" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Architecture-Apple%20Silicon%20Native-333333?style=flat-square" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/Dependencies-Zero-success?style=flat-square" alt="Zero Dependencies" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License MIT" />
</p>

---

## Origin & Naming

**Datwig** (pronounced **/deɪt wɪɡ/**) is a portmanteau of **Date** and **Twig**.

Conceived as a modern rewrite and spiritual successor to the legacy utility **DateTree**, Datwig strips away technical debt, binary bloat, and legacy runtimes in favor of a nimble, twig-weight native Swift utility designed specifically for modern macOS.

---

## Key Features

- **Dual Ingestion Methods**:
  - **Drag & Drop**: Drop source folders, camera cards, or batches of photos/videos directly onto the responsive drop area.
  - **Native File Picker (`NSOpenPanel`)**: Click **`[Select Directory...]`** (or press `⌘O`) to select an entire SD card (e.g. `DCIM`), camera volume, or individual media file via the system dialog.
  - Both pathways converge into the identical asynchronous processing pipeline.

- **Zero-Bitmap Fast Metadata Extraction**:
  - Utilizes Apple's native `ImageIO` framework with `kCGImageSourceShouldCache: false`.
  - Reads `kCGImagePropertyExifDateTimeOriginal` directly from image headers without decoding multi-megabyte uncompressed pixel buffers into RAM.
  - Supports comprehensive fallbacks:
    1. `kCGImagePropertyExifDateTimeOriginal` (EXIF)
    2. `kCGImagePropertyExifDateTimeDigitized` (EXIF)
    3. `kCGImagePropertyTIFFDateTime` (TIFF)
    4. IPTC Date & Time Created
    5. Video creation timestamp metadata (`AVFoundation` / QuickTime container metadata)
    6. File system creation timestamp (`attributes[.creationDate]`)
    7. File system modification timestamp (`attributes[.modificationDate]`)

- **Non-Destructive & Safe Copying**:
  - Copies media files to the destination tree without altering or removing source camera files.
  - Built-in cancellation support: safely stop operations at any point with cooperative `async/await` tasks.

- **Intelligent Collision Resolution**:
  - **Skip Identical (Default)**: Compares file size and sample byte chunks. If an identical copy exists at the target, copying is skipped to prevent duplicate storage. If contents differ, it appends an incremental suffix (e.g. `IMG_0001_1.JPG`).
  - **Always Rename**: Appends `_1`, `_2` to resolve any naming conflict.
  - **Overwrite**: Replaces destination files when explicitly requested.

- **Live Progress & Reporting**:
  - Real-time progress bar, item counters (`Processing 142 of 500`), and live recent activity feed.
  - Post-organization summary cards with metrics (Copied, Renamed, Skipped, Errors) and direct **Show in Finder** shortcut.

- **Flexible Hierarchy Presets**:
  - `YYYY / YYYY-MM-DD` (e.g. `2024/2024-08-15/IMG_0001.JPG`) *(Recommended)*
  - `YYYY / MM / DD` (e.g. `2024/08/15/IMG_0001.JPG`)
  - `YYYY-MM-DD` (e.g. `2024-08-15/IMG_0001.JPG`)
  - `YYYY / MM - Month / YYYY-MM-DD` (e.g. `2024/08 - August/2024-08-15/IMG_0001.JPG`)
  - Fully customizable date formatting tokens.

---

## System Requirements

- **macOS 14.0 (Sonoma)** or **macOS 15.0+ (Sequoia)**
- Native support for Apple Silicon (M1/M2/M3/M4) and Intel x86_64
- Zero third-party package dependencies (100% native Apple frameworks: `SwiftUI`, `ImageIO`, `UniformTypeIdentifiers`, `FileManager`, `AppKit`, `AVFoundation`)

---

## Project Structure

```
datwig/
├── Package.swift                    # Swift 5.9+ Package definition (CLI & Tests)
├── Datwig.xcodeproj/                # Native Xcode project file
│   └── project.pbxproj
├── Sources/
│   └── Datwig/
│       ├── DatwigApp.swift          # Main application entry point & lifecycle
│       ├── ContentView.swift        # Primary UI: drop target, progress & reports
│       ├── DirectoryPicker.swift    # NSOpenPanel source & destination wrappers
│       ├── DateOrganizer.swift      # Async/await pipeline, cancellation & state
│       ├── ExifParser.swift         # Fast ImageIO metadata reader & date parser
│       ├── OrganizationSettings.swift# User preferences, directory presets & preview
│       ├── DuplicateResolver.swift  # Collision resolution & chunk comparison
│       ├── FileScanner.swift        # Recursive media scanner & UTType filters
│       ├── MediaItem.swift          # Media model, states & batch report structs
│       ├── SettingsView.swift       # Preferences sheet & tabs
│       ├── Info.plist               # App metadata configuration
│       └── Datwig.entitlements      # Sandboxed file access permissions
├── Tests/
│   └── DatwigTests/
│       ├── ExifParserTests.swift    # EXIF, ISO8601 & IPTC parser tests
│       ├── DateOrganizerTests.swift # Path preset formatting & scanner tests
│       └── DuplicateResolverTests.swift # Collision logic & unique naming tests
├── LICENSE                          # MIT License
├── .gitignore                       # Standard Swift / Xcode ignores
└── README.md
```

---

## Building and Running

### Option 1: Xcode (Recommended for GUI App)

1. Double-click `Datwig.xcodeproj` or run:
   ```bash
   open Datwig.xcodeproj
   ```
2. Select the **Datwig** target and your Mac as the destination.
3. Press `⌘R` to build and run.
4. Press `⌘U` to execute unit tests.

### Option 2: Swift Package Manager

You can also build and run Datwig via the terminal:

```bash
# Build the project
swift build

# Run unit tests
swift test

# Run executable
swift run Datwig
```

---

## How to Use

1. **Launch Datwig**.
2. **Choose Source**:
   - **Drag & Drop**: Drag a folder, SD card volume, or camera files directly onto the drop box.
   - **Click Button**: Click **`[Select Directory...]`** (or press `⌘O`) and choose your folder or card root.
3. **Monitor Progress**:
   - Observe real-time scanning and file organization progress.
   - View newly organized files appearing in the live activity stream.
4. **Complete & Inspect**:
   - Review the batch metrics summary card.
   - Click **`[Show in Finder]`** to navigate straight to your newly sorted photo library.

---

## Keyboard Shortcuts

| Shortcut | Action |
|:---|:---|
| `⌘O` | Open native file dialog to choose source |
| `⌘,` | Open Preferences / Settings |
| `⌘.` | Cancel active organization job |
| `⌘R` | Reset view to organize another batch |

---

## Supported Media Formats

Datwig recognizes all standard camera and video formats, including:

- **Images**: JPEG, PNG, HEIC, HEIF, TIFF, GIF, WebP, BMP
- **Camera RAW**: Canon (`.CR2`, `.CR3`), Nikon (`.NEF`), Sony (`.ARW`), Adobe (`.DNG`), Fujifilm (`.RAF`), Olympus (`.ORF`), Panasonic (`.RW2`), Pentax (`.PEF`)
- **Videos**: QuickTime (`.MOV`), MP4 (`.MP4`, `.M4V`), AVCHD (`.MTS`, `.M2TS`), AVI, MKV

---

## License

Datwig is released under the open-source [MIT License](LICENSE).
Feel free to use, modify, and distribute it in accordance with the license conditions.
