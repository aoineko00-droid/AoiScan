# AoiScan

<p align="center">
  <b>A privacy-focused, offline-first document scanner for iOS.</b>
</p>

AoiScan is an open-source iOS document scanner built around **privacy, practical document workflows, and on-device processing**. Scanning, image processing, OCR, search indexing, and document storage are handled locally whenever possible; scanned documents are not automatically uploaded to a cloud service.

> AoiScan is under active development and is currently being tested through Apple TestFlight.

---

## 🎨 App Icon Preview

<p align="center">
  <img src="icon.png" width="180" alt="AoiScan app icon preview">
</p>

<p align="center">
  <sub>The current AoiScan application icon.</sub>
</p>

---

## ✨ Features

### Document Scanning

- 📷 Single-page and multi-page capture with the iPhone camera
- 📄 Automatic document detection with safety fallbacks
- 📐 Perspective correction and manual four-corner cropping
- 🔄 Rotation, zoom, and page positioning
- 🖼️ Original, smart, and black-and-white filters
- ➕ Continue scanning directly into an existing document
- 🧾 Smart light-paper enhancement with text and color-content protection

### OCR and Local Search

- 🔎 On-device text recognition using Apple Vision
- ✏️ Recognized-text editing, copying, and sharing
- 📚 Multi-page OCR navigation
- 🔍 Local full-text document search
- 🧱 Rule-based document blocks for lines, columns, paragraphs, and table candidates

### File and Page Management

- 📁 Create, rename, browse, and delete one-level folders
- 📥 Import one or more local PDF files
- 🖼️ First-page thumbnails on the home screen
- ✏️ Rename documents from the list or scan detail view
- ☑️ Batch select, delete, move, merge, and share documents
- 🔀 Reorder documents before merging and choose whether to keep the originals
- 📑 View every page in a thumbnail grid and long-press/drag to reorder pages
- 🗑️ Delete only the current page of a multi-page document
- ↔️ Consistent swipe actions for files and folders

### Export and Sharing

- 📄 Generate and share image-based PDF files
- 🖼️ Share single-page or multi-page documents as JPG files
- 📝 Export recognized document structure as a DOCX MVP
- 📤 Share recognized text through the iOS share sheet

### Privacy and Diagnostics

- 🔒 Offline-first architecture with local document and OCR processing
- 🛡️ No automatic cloud upload
- 📜 In-app privacy statement
- 🧰 View, export, and clear privacy-safe diagnostic logs
- 🚫 Diagnostics exclude scanned images, recognized document text, document contents, and user file names

### Interface

- 🌐 Simplified Chinese and English
- ✅ Language changes use an explicit Cancel/Confirm flow
- 🧭 Compact scan-detail layout with a larger document preview
- 📱 iPhone and adaptive SwiftUI layouts

---

## 🆕 Today’s Updates — August 15, 2026

### Multi-page Document Editing

The scan detail screen can now continue capturing pages into the current document. A translucent page-control group provides current-page deletion and access to an all-pages overview. The overview supports page selection and long-press drag reordering; changes are committed only after tapping **Done**.

Page mutations are staged in a temporary directory and use a backup-and-replace workflow. Page images, OCR JSON, recognized text, document JSON, crop/filter metadata, and search text are renumbered together.

### File Management

The home screen now supports folders, PDF import, document thumbnails, batch deletion, document merging, moving documents into folders, and PDF/JPG batch sharing. Merge operations can preserve or remove the source documents after a successful commit.

Files and folders use consistent swipe actions, and redundant long-press management actions have been removed.

### Scan Detail and Export

The document name and timestamp now share the navigation row, and tapping the name opens rename editing. The preview area is larger, while filter, crop, OCR, share, and add-page actions use a consistent monochrome toolbar. Detail sharing supports PDF, JPG, and DOCX.

### Scanning and Image Quality

Automatic cropping now applies stricter geometry and document-completeness checks before accepting small candidates. Unsafe results fall back to stable corners or the full image instead of risking content loss.

Smart enhancement for high-confidence light paper is being calibrated around a content-aware white canvas with protection for dark text, red/blue marks, and saturated graphics. User-confirmed page orientation is preserved during later enhancement. These quality improvements remain an active TestFlight validation area.

---

## 📱 Screenshots

Coming soon.

---

## 🛠 Technologies

AoiScan primarily uses Apple-native frameworks:

- Swift and SwiftUI
- AVFoundation
- Vision
- Core Image
- PDFKit
- Core Data
- UIKit where native camera, image, or sharing integration is required

OpenCV, PaddleOCR, and production Core ML document analysis are **not currently integrated**.

---

## 🚧 Development Status

| Area | Status |
|---|---|
| Single-page and multi-page scanning | Available |
| Automatic detection and perspective correction | Available; continuing stability testing |
| Manual crop and image filters | Available |
| On-device OCR and local search | Available |
| PDF and JPG export | Available |
| DOCX export | MVP available |
| Folders, PDF import, batch actions, and merging | Available; awaiting broader device testing |
| Add, delete, preview, and reorder document pages | Available; awaiting large-document testing |
| Smart enhancement and light-paper normalization | First production phase; active calibration |
| High-resolution capture buffer | Diagnostics only |
| Best-frame replacement | Not enabled |
| Multi-frame fusion | Experimental offline kernel only |
| Searchable PDF text layer | Not implemented |
| Full table-cell reconstruction | Not implemented |

Current priorities are:

- Real-device validation of large multi-page document operations
- Further automatic crop stability for colored paper, books, and small documents
- Smart enhancement quality and color-content preservation
- OCR performance on dense, small-text pages
- PDF/JPG/DOCX page-order and export regression testing
- Continued UI simplification and accessibility review

---

## 🎯 Future Goals and Roadmap

The near-term goal is to turn the newly completed file and page-management workflows into a stable Version 1.0 experience while continuing to improve scan completeness, image quality, and on-device performance.

### Version 1.0

- [x] Single-page and multi-page capture
- [x] Automatic document detection and perspective correction
- [x] Manual crop, rotation, and image filters
- [x] Local document storage and folders
- [x] On-device OCR and local full-text search
- [x] PDF import
- [x] PDF/JPG sharing and DOCX MVP export
- [x] Batch delete, merge, move, and share
- [x] Add, delete, preview, and reorder pages in an existing document
- [x] Diagnostic logs and in-app privacy statement
- [x] Simplified Chinese and English interface
- [x] TestFlight beta testing
- [ ] Complete large-document and migration regression testing
- [ ] Continue colored-document and crop-stability improvements
- [ ] Continue smart-enhancement calibration
- [ ] Expand automated regression coverage

### Longer-term Goals

- [ ] Searchable PDF text layer
- [ ] Full table-cell and complex-layout reconstruction
- [ ] Advanced book-page detection and optional left/right page separation
- [ ] Production-ready best-frame selection and safe multi-frame fusion
- [ ] Optional local document analysis using an evaluated on-device model

---

## 🧠 Vision

Many document scanner applications depend on cloud services for advanced processing. AoiScan explores a different approach:

> Powerful document scanning while keeping documents private and processed locally.

The project combines Apple’s native frameworks, computer-vision techniques, and careful failure fallbacks to create a secure and practical scanning experience.

---

## 🧪 TestFlight

AoiScan is currently available to a limited number of TestFlight beta testers. To express interest, open a GitHub Issue and contact the maintainer.

Feedback is especially useful for:

- Document detection and crop completeness
- Colored paper, shadows, folds, stamps, and handwritten marks
- Large multi-page add/delete/reorder workflows
- PDF import, merge, folder migration, and export page order
- OCR accuracy and performance on dense text
- Interface clarity, accessibility, and stability

Please remove or obscure private information before attaching screenshots or sample documents.

---

## 🤝 Contributing

Contributions, bug reports, testing feedback, and suggestions are welcome. When reporting an issue, please include:

- iOS version and device model
- A short description of the document and lighting environment
- Steps to reproduce the issue
- Screenshots when appropriate and privacy-safe
- Exported diagnostic logs when available

Diagnostic logs are preferred over private document samples whenever they are sufficient to reproduce the problem.

---

## 🔧 Development

### Requirements

- macOS
- Xcode
- iOS 17 or later

### Clone the Repository

```bash
git clone https://github.com/aoineko00-droid/AoiScan.git
```

Open `AoiScan.xcodeproj` in Xcode, select an iOS device or supported simulator, and build the `AoiScan` scheme.

---

## 🔐 Privacy

AoiScan is designed as an offline-first application. Documents and recognized text are processed locally whenever possible, and the app does not automatically upload scanned documents to an external service.

Before contributing changes that affect telemetry or diagnostics, preserve the existing rule that logs must not contain scanned images, recognized document text, document contents, user file names, or raw data that can reconstruct sensitive material.
