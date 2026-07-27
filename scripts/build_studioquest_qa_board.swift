#!/usr/bin/env swift

import AppKit
import Foundation

private struct BoardInput {
    let reference: URL
    let output: URL
    let screenshots: [URL]
    let deviceLabel: String

    init(arguments: [String]) throws {
        guard arguments.count == 11 else {
            throw NSError(
                domain: "StudioQuestQABoard",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Usage: build_studioquest_qa_board.swift reference.png output.png "
                        + "today-light quest-light community-light you-light "
                        + "today-dark quest-dark community-dark you-dark"
                ]
            )
        }
        reference = URL(fileURLWithPath: arguments[1])
        output = URL(fileURLWithPath: arguments[2])
        screenshots = arguments.dropFirst(3).map(URL.init(fileURLWithPath:))
        let outputName = output.lastPathComponent.lowercased()
        if outputName.contains("compact") {
            deviceLabel = "compact iPhone"
        } else if outputName.contains("promax") {
            deviceLabel = "iPhone 17 Pro Max"
        } else {
            deviceLabel = "iPhone 17 Pro"
        }
    }
}

private enum BoardStyle {
    static let canvas = NSColor(
        calibratedRed: 0.925,
        green: 0.945,
        blue: 0.975,
        alpha: 1
    )
    static let ink = NSColor(
        calibratedRed: 0.055,
        green: 0.075,
        blue: 0.12,
        alpha: 1
    )
    static let secondaryInk = ink.withAlphaComponent(0.62)
    static let margin: CGFloat = 36
    static let gap: CGFloat = 18
    static let panelWidth: CGFloat = 330
    static let titleHeight: CGFloat = 70
    static let rowLabelHeight: CGFloat = 46
}

private func loadImage(_ url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw NSError(
            domain: "StudioQuestQABoard",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to load \(url.path)"]
        )
    }
    return image
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight,
    color: NSColor = BoardStyle.ink,
    alignment: NSTextAlignment = .left
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byTruncatingTail
    (text as NSString).draw(
        in: rect,
        withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    )
}

private func aspectFit(_ image: NSImage, in destination: NSRect) {
    let source = image.size
    guard source.width > 0, source.height > 0 else { return }
    let scale = min(destination.width / source.width, destination.height / source.height)
    let size = NSSize(width: source.width * scale, height: source.height * scale)
    let rect = NSRect(
        x: destination.midX - (size.width / 2),
        y: destination.midY - (size.height / 2),
        width: size.width,
        height: size.height
    )
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
}

private func makeBoard(input: BoardInput) throws {
    let reference = try loadImage(input.reference)
    let screenshots = try input.screenshots.map(loadImage)
    let screenshotAspect = screenshots[0].size.height / max(screenshots[0].size.width, 1)
    let panelHeight = BoardStyle.panelWidth * screenshotAspect
    let columns = 4
    let contentWidth =
        (CGFloat(columns) * BoardStyle.panelWidth)
        + (CGFloat(columns - 1) * BoardStyle.gap)
    let width = contentWidth + (BoardStyle.margin * 2)
    let referenceHeight = width * reference.size.height / reference.size.width
    let currentSectionHeight =
        BoardStyle.titleHeight
        + (BoardStyle.rowLabelHeight * 2)
        + (panelHeight * 2)
        + BoardStyle.gap
    let height =
        BoardStyle.margin
        + BoardStyle.titleHeight
        + referenceHeight
        + BoardStyle.margin
        + currentSectionHeight
        + BoardStyle.margin

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "StudioQuestQABoard",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Unable to allocate QA board bitmap"]
        )
    }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(
            domain: "StudioQuestQABoard",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Unable to create QA board context"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    BoardStyle.canvas.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    var cursorY = height - BoardStyle.margin - BoardStyle.titleHeight
    drawText(
        "PractiQuest 2.0 · Approved direction versus current \(input.deviceLabel) build",
        in: NSRect(
            x: BoardStyle.margin,
            y: cursorY + 15,
            width: contentWidth,
            height: 46
        ),
        size: 28,
        weight: .bold
    )

    cursorY -= referenceHeight
    reference.draw(
        in: NSRect(
            x: BoardStyle.margin,
            y: cursorY,
            width: contentWidth,
            height: referenceHeight
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    cursorY -= BoardStyle.margin + BoardStyle.titleHeight
    drawText(
        "Current deterministic root states · Same device, data, and navigation authority",
        in: NSRect(
            x: BoardStyle.margin,
            y: cursorY + 16,
            width: contentWidth,
            height: 40
        ),
        size: 23,
        weight: .semibold
    )

    let labels = ["Today", "Quest", "Community", "You"]
    for row in 0..<2 {
        let appearance = row == 0 ? "Light" : "Dark"
        cursorY -= BoardStyle.rowLabelHeight
        for column in 0..<columns {
            let x =
                BoardStyle.margin
                + (CGFloat(column) * (BoardStyle.panelWidth + BoardStyle.gap))
            drawText(
                "\(labels[column]) · \(appearance)",
                in: NSRect(
                    x: x,
                    y: cursorY + 9,
                    width: BoardStyle.panelWidth,
                    height: 30
                ),
                size: 18,
                weight: .semibold,
                alignment: .center
            )
        }

        cursorY -= panelHeight
        for column in 0..<columns {
            let x =
                BoardStyle.margin
                + (CGFloat(column) * (BoardStyle.panelWidth + BoardStyle.gap))
            let panelRect = NSRect(
                x: x,
                y: cursorY,
                width: BoardStyle.panelWidth,
                height: panelHeight
            )
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: panelRect,
                xRadius: 20,
                yRadius: 20
            ).fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(
                roundedRect: panelRect,
                xRadius: 20,
                yRadius: 20
            ).addClip()
            aspectFit(screenshots[(row * columns) + column], in: panelRect)
            NSGraphicsContext.restoreGraphicsState()
        }
        if row == 0 {
            cursorY -= BoardStyle.gap
        }
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "StudioQuestQABoard",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Unable to encode QA board"]
        )
    }
    try data.write(to: input.output, options: .atomic)
}

do {
    try makeBoard(input: BoardInput(arguments: CommandLine.arguments))
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
