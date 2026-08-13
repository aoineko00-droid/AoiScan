//
//  DOCXPackageWriter.swift
//  AoiScan
//

import Foundation


enum DOCXPackageWriterError:LocalizedError {
    case invalidTextEncoding

    var errorDescription:String? {
        L10n.text("无法生成 Word 文档内容。")
    }
}


/// Converts the stable ScanDocument model into a valid OOXML Word package.
struct DOCXPackageWriter {
    func write(
        document:ScanDocument,
        to url:URL
    ) throws {
        let parts:[(String,String)] = [
            ("[Content_Types].xml", contentTypesXML),
            ("_rels/.rels", packageRelationshipsXML),
            ("docProps/core.xml", corePropertiesXML(document)),
            ("docProps/app.xml", appPropertiesXML),
            ("word/document.xml", documentXML(document)),
            ("word/styles.xml", stylesXML),
            ("word/settings.xml", settingsXML),
            ("word/_rels/document.xml.rels", documentRelationshipsXML)
        ]

        let entries = try parts.map { path, xml in
            guard let data = xml.data(using:.utf8) else {
                throw DOCXPackageWriterError.invalidTextEncoding
            }
            return ZIPArchiveWriter.Entry(
                path:path,
                data:data
            )
        }

        try ZIPArchiveWriter.write(
            entries:entries,
            to:url
        )
    }

    private func documentXML(
        _ document:ScanDocument
    )->String {
        var elements:[String] = []

        for (pageIndex, page) in document.pages.enumerated() {
            if pageIndex > 0 {
                elements.append(pageBreakXML)
            }

            for block in page.blocks.sorted(
                by:{ $0.readingOrder < $1.readingOrder }
            ) {
                switch block.type {
                case .title:
                    guard !block.text.isEmpty else { continue }
                    elements.append(
                        paragraphXML(
                            text:block.text,
                            style:"AoiTitle"
                        )
                    )
                case .paragraph:
                    guard !block.text.isEmpty else { continue }
                    elements.append(
                        paragraphXML(text:block.text)
                    )
                case .table:
                    elements.append(
                        placeholderTableXML(
                            text:L10n.text("[表格区域]")
                        )
                    )
                case .image:
                    elements.append(
                        placeholderTableXML(
                            text:L10n.text("[图片区域]")
                        )
                    )
                case .unknown:
                    guard !block.text.isEmpty else { continue }
                    elements.append(
                        paragraphXML(text:block.text)
                    )
                }
            }
        }

        let body = elements.joined(separator:"\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
        \(body)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/>
              <w:cols w:space="708"/>
              <w:docGrid w:linePitch="360"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private func paragraphXML(
        text:String,
        style:String? = nil
    )->String {
        let styleXML = style.map {
            "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>"
        } ?? ""
        let lines = text
            .replacingOccurrences(of:"\r\n", with:"\n")
            .replacingOccurrences(of:"\r", with:"\n")
            .split(separator:"\n", omittingEmptySubsequences:false)
        let runs = lines.enumerated().map { index, line in
            let breakXML = index == 0 ? "" : "<w:r><w:br/></w:r>"
            return breakXML
                + "<w:r><w:t xml:space=\"preserve\">"
                + xmlEscaped(String(line))
                + "</w:t></w:r>"
        }
        .joined()

        return "<w:p>\(styleXML)\(runs)</w:p>"
    }

    private func placeholderTableXML(text:String)->String {
        """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="9360" w:type="dxa"/>
            <w:tblInd w:w="120" w:type="dxa"/>
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:color="A8B0BA"/>
              <w:left w:val="single" w:sz="6" w:color="A8B0BA"/>
              <w:bottom w:val="single" w:sz="6" w:color="A8B0BA"/>
              <w:right w:val="single" w:sz="6" w:color="A8B0BA"/>
              <w:insideH w:val="nil"/>
              <w:insideV w:val="nil"/>
            </w:tblBorders>
            <w:tblCellMar>
              <w:top w:w="80" w:type="dxa"/>
              <w:left w:w="120" w:type="dxa"/>
              <w:bottom w:w="80" w:type="dxa"/>
              <w:right w:w="120" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid><w:gridCol w:w="9360"/></w:tblGrid>
          <w:tr>
            <w:tc>
              <w:tcPr>
                <w:tcW w:w="9360" w:type="dxa"/>
                <w:shd w:val="clear" w:color="auto" w:fill="F2F4F7"/>
              </w:tcPr>
              <w:p><w:r><w:rPr><w:i/><w:color w:val="5B6470"/></w:rPr><w:t>\(xmlEscaped(text))</w:t></w:r></w:p>
            </w:tc>
          </w:tr>
        </w:tbl>
        """
    }

    private var pageBreakXML:String {
        "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
    }

    private func corePropertiesXML(
        _ document:ScanDocument
    )->String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let created = formatter.string(from:document.createdAt)
        let modified = formatter.string(from:Date())

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscaped(document.title))</dc:title>
          <dc:creator>AoiScan</dc:creator>
          <cp:lastModifiedBy>AoiScan</cp:lastModifiedBy>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(created)</dcterms:created>
          <dcterms:modified xsi:type="dcterms:W3CDTF">\(modified)</dcterms:modified>
        </cp:coreProperties>
        """
    }

    private func xmlEscaped(_ value:String)->String {
        value
            .replacingOccurrences(of:"&", with:"&amp;")
            .replacingOccurrences(of:"<", with:"&lt;")
            .replacingOccurrences(of:">", with:"&gt;")
            .replacingOccurrences(of:"\"", with:"&quot;")
            .replacingOccurrences(of:"'", with:"&apos;")
    }

    private var contentTypesXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
          <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        </Types>
        """
    }

    private var packageRelationshipsXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
          <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
        </Relationships>
        """
    }

    private var documentRelationshipsXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
        </Relationships>
        """
    }

    private var stylesXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="PingFang SC"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US" w:eastAsia="zh-CN"/></w:rPr></w:rPrDefault>
            <w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/><w:qFormat/>
            <w:pPr><w:spacing w:after="120" w:line="264" w:lineRule="auto"/></w:pPr>
            <w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="PingFang SC"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="AoiTitle">
            <w:name w:val="AoiScan Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>
            <w:pPr><w:jc w:val="center"/><w:spacing w:before="0" w:after="240"/></w:pPr>
            <w:rPr><w:b/><w:bCs/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr>
          </w:style>
        </w:styles>
        """
    }

    private var settingsXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:zoom w:percent="100"/>
          <w:defaultTabStop w:val="720"/>
          <w:compat/>
        </w:settings>
        """
    }

    private var appPropertiesXML:String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
          <Application>AoiScan</Application>
          <AppVersion>1.0</AppVersion>
        </Properties>
        """
    }
}
