//
//  DocumentDebugOverlay.swift
//  AoiScan
//

import SwiftUI


#if DEBUG
struct DocumentDebugOverlay:View {
    let image:UIImage
    let blocks:[DocumentBlock]

    var body:some View {
        GeometryReader { proxy in
            let imageRect = aspectFitRect(
                imageSize:image.size,
                containerSize:proxy.size
            )
            let ocrBlocks = uniqueOCRBlocks
            let textLines = LineAnalyzer().analyze(
                ocrBlocks:ocrBlocks
            )
            let columnLayout = ColumnAnalyzer().analyze(
                textLines:textLines
            )

            ZStack(alignment:.topLeading) {
                Color(.systemBackground)

                Image(uiImage:image)
                    .resizable()
                    .aspectRatio(contentMode:.fit)
                    .frame(
                        width:imageRect.width,
                        height:imageRect.height
                    )
                    .position(
                        x:imageRect.midX,
                        y:imageRect.midY
                    )

                ForEach(columnLayout.columns) { column in
                    let rect = displayRect(
                        for:column.boundingBox,
                        in:imageRect
                    )

                    Rectangle()
                        .stroke(
                            Color.cyan,
                            style:StrokeStyle(
                                lineWidth:1.5,
                                dash:[8,4]
                            )
                        )
                        .frame(
                            width:max(rect.width, 1),
                            height:max(rect.height, 1)
                        )
                        .position(
                            x:rect.midX,
                            y:rect.midY
                        )

                    Text("C\(column.index + 1)")
                        .font(.system(size:9, weight:.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal,4)
                        .padding(.vertical,2)
                        .background(Color.cyan)
                        .clipShape(RoundedRectangle(cornerRadius:3))
                        .position(
                            x:min(
                                max(rect.minX + 12, imageRect.minX + 12),
                                imageRect.maxX - 12
                            ),
                            y:max(rect.minY + 8, imageRect.minY + 8)
                        )
                }

                ForEach(textLines) { line in
                    let rect = displayRect(
                        for:line.boundingBox,
                        in:imageRect
                    )

                    Rectangle()
                        .stroke(
                            Color.purple.opacity(0.85),
                            style:StrokeStyle(
                                lineWidth:0.8,
                                dash:[3,2]
                            )
                        )
                        .frame(
                            width:max(rect.width, 1),
                            height:max(rect.height, 1)
                        )
                        .position(
                            x:rect.midX,
                            y:rect.midY
                        )
                }

                ForEach(blocks) { block in
                    let rect = displayRect(
                        for:block.boundingBox,
                        in:imageRect
                    )
                    let color = color(for:block.type)

                    Rectangle()
                        .stroke(color, lineWidth:2)
                        .background(color.opacity(0.06))
                        .frame(
                            width:max(rect.width, 1),
                            height:max(rect.height, 1)
                        )
                        .position(
                            x:rect.midX,
                            y:rect.midY
                        )

                    Text(debugLabel(for:block))
                        .font(.system(size:9, weight:.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal,4)
                        .padding(.vertical,2)
                        .background(color)
                        .clipShape(RoundedRectangle(cornerRadius:3))
                        .position(
                            x:min(
                                max(rect.minX + 28, imageRect.minX + 28),
                                imageRect.maxX - 28
                            ),
                            y:max(rect.minY - 8, imageRect.minY + 8)
                        )
                }
            }
            .clipped()
        }
        .allowsHitTesting(false)
    }

    private var uniqueOCRBlocks:[OCRBlock] {
        Array(
            Dictionary(
                blocks
                    .flatMap(\.ocrBlocks)
                    .map { ($0.id, $0) },
                uniquingKeysWith:{ first, _ in first }
            ).values
        )
    }

    private func aspectFitRect(
        imageSize:CGSize,
        containerSize:CGSize
    )->CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return .zero
        }

        let scale = min(
            containerSize.width / imageSize.width,
            containerSize.height / imageSize.height
        )
        let fittedSize = CGSize(
            width:imageSize.width * scale,
            height:imageSize.height * scale
        )

        return CGRect(
            x:(containerSize.width - fittedSize.width) / 2,
            y:(containerSize.height - fittedSize.height) / 2,
            width:fittedSize.width,
            height:fittedSize.height
        )
    }

    private func displayRect(
        for normalizedRect:CGRect,
        in imageRect:CGRect
    )->CGRect {
        CGRect(
            x:imageRect.minX
                + normalizedRect.minX * imageRect.width,
            y:imageRect.minY
                + (1 - normalizedRect.maxY) * imageRect.height,
            width:normalizedRect.width * imageRect.width,
            height:normalizedRect.height * imageRect.height
        )
    }

    private func color(
        for type:DocumentBlockType
    )->Color {
        switch type {
        case .title:
            return .red
        case .paragraph:
            return .blue
        case .table:
            return .green
        case .image:
            return .orange
        case .unknown:
            return .gray
        }
    }

    private func debugLabel(
        for block:DocumentBlock
    )->String {
        let column = block.columnIndex.map {
            " C\($0 + 1)"
        } ?? ""
        return "\(block.type.rawValue.uppercased()) #\(block.readingOrder + 1)\(column)"
    }
}
#endif
