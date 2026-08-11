# AoiScan

<p align="center">
  <img src="icon.png" width="120" alt="AoiScan Icon">
</p>

<p align="center">
  <b>A privacy-focused offline document scanner for iOS.</b>
</p>

AoiScan is an open-source iOS document scanning application designed around **privacy, simplicity, and local processing**.

Unlike cloud-dependent scanning solutions, AoiScan processes documents directly on the device whenever possible, helping users keep their documents private and secure.

The goal of AoiScan is to provide a lightweight but powerful document scanning experience using Apple’s native technologies and modern computer vision techniques.

---

## ✨ Features

### Document Scanning

- 📷 Capture documents using the iPhone camera
- 📑 Single-page and multi-page scanning
- 📄 Automatic document detection
- 📐 Perspective correction
- ✂️ Manual crop adjustment
- 🔄 Image rotation
- 🔍 Image zoom and position adjustment
- 🖼️ Original, smart, and black-and-white document filters
- 📤 Export and share scanned documents as PDF

### Text Recognition

- 🔎 On-device OCR text recognition
- ✏️ Basic recognized-text editing
- 📋 Copy recognized text
- 📤 Share recognized text with other applications
- 📚 Page navigation for multi-page OCR
- 🔍 Local document search using recognized text

### Privacy & Security

- 🔒 Offline-first architecture
- 🛡️ No automatic cloud upload
- 📱 Local document and OCR processing
- 🔐 Scanned documents stay on the device
- 📜 An in-app privacy statement explains how documents and diagnostic data are handled
- 🚫 Diagnostic logs do not contain scanned images or recognized document text

### Document Management

- Local document storage
- PDF document organization
- Document renaming
- Local full-text search
- Privacy-safe diagnostic logs
- Diagnostic log review and export

---

## 🆕 Latest Updates — August 10, 2026

### Privacy Statement

AoiScan now includes an in-app privacy statement explaining how scanned documents, recognized text, and diagnostic information are handled.

AoiScan is designed for offline use. Scanned documents are processed locally and are not automatically uploaded to a cloud service.

### Diagnostic Logs

Users can now review and export diagnostic logs to help investigate scanning, document detection, and recognition issues.

The diagnostic logs are designed not to include:

- Scanned document images
- Recognized document text
- Document contents
- User file names

### TestFlight Beta Testing

AoiScan is currently undergoing beta testing through Apple TestFlight.

If you would like to participate in the TestFlight beta and provide feedback, please contact the maintainer by opening a GitHub Issue.

TestFlight access may be limited while the application is under active development.

---

## 📱 Screenshots

Coming soon.

---

## 🛠 Technologies

AoiScan is built with Apple’s native frameworks and modern iOS technologies.

### Current Technologies

- Swift
- SwiftUI
- AVFoundation
- Vision Framework
- Core Image
- PDFKit
- Core Data

### Technologies Under Evaluation

- OpenCV for advanced document image processing
- Core ML for local AI enhancement
- Advanced shadow removal
- Intelligent document understanding

---

## 🚧 Development Status

AoiScan is currently under active development and TestFlight beta testing.

Current development priorities include:

- Improving document edge-detection stability
- Supporting documents with different colors and backgrounds
- Improving scanning performance and image quality
- Optimizing local OCR performance
- Improving multi-page document workflows
- Expanding privacy-safe diagnostic information
- Building a simple and intuitive scanning experience

---

## 🗺 Roadmap

### Version 1.0

- [x] Single-page document capture
- [x] Multi-page document capture
- [x] Automatic document detection
- [x] Perspective correction
- [x] Manual crop adjustment
- [x] Image filters
- [x] PDF generation
- [x] Local document storage
- [x] OCR text recognition
- [x] Local OCR search
- [x] Diagnostic logs
- [x] In-app privacy statement
- [x] TestFlight beta testing
- [ ] Improved detection for colored documents
- [ ] Additional scanning stability improvements
- [ ] Expanded diagnostic information

### Future Development

- [ ] Professional document filters
- [ ] Advanced shadow removal
- [ ] Advanced noise reduction
- [ ] PDF merge and split
- [ ] PDF page management
- [ ] Local AI document analysis
- [ ] Smart document organization
- [ ] Improved book-page detection
- [ ] Optional automatic separation of left and right book pages

---

## 🧠 Vision

Many document scanner applications rely on cloud services for advanced processing.

AoiScan explores a different approach:

> Powerful document scanning while keeping documents private and processed locally.

The project aims to combine Apple’s ecosystem, computer vision algorithms, and local AI technologies to create a secure and practical document scanning experience.

---

## 🤝 Contributing

Contributions, bug reports, testing feedback, and suggestions are welcome.

When reporting an issue, please include:

- iOS version
- Device model
- A description of the document and environment
- Steps to reproduce the problem
- Screenshots when appropriate
- Exported diagnostic logs when available

Please make sure screenshots do not contain private or sensitive document information.

---

## 🧪 TestFlight

AoiScan is currently available to a limited number of TestFlight beta testers.

If you are interested in testing AoiScan, please open a GitHub Issue to contact the maintainer.

Feedback about the following areas is especially helpful:

- Document detection accuracy
- Colored-paper detection
- Multi-page scanning
- Image filters
- OCR accuracy
- Performance and stability
- User interface and workflow

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

Open the project in Xcode, select an iOS device, and build the application.

---

## 🔐 Privacy

AoiScan is designed as an offline-first application.

Documents and recognized text are processed locally whenever possible. AoiScan does not automatically upload scanned documents to an external server.

Users
