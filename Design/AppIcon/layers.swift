#!/usr/bin/env swift

// Generates the AppIcon foreground layers from stock icon-set glyphs.
//
// - brackets.svg: Tabler `chevron-compact-right` and `chevron-compact-left`
//   (MIT), scaled and stroked into filled outlines. Icon Composer repaints layer
//   geometry for Dark, Tinted, and Clear renditions, so the SVG must not rely on
//   strokes.
// - hourglass.svg: Phosphor `hourglass-fill` (MIT), path copied verbatim and
//   placed with one transform.
//
// Usage: swift Design/AppIcon/layers.swift Resources/AppIcon.icon/Assets

import CoreGraphics
import Foundation

let canvas: CGFloat = 1024
let center = canvas / 2

let bracketColor = "#EAFBFF"
let hourglassColor = "#F7A93E"

/// Tabler glyphs use a 24-unit grid; the chevrons span y 4...20.
let tablerScale: CGFloat = 26
/// Tabler "Regular" (stroke-width 2) would be 52 units here; 38 matches the lighter look chosen in review.
let bracketStroke: CGFloat = 38

// Phosphor glyphs use a 256-unit grid; hourglass-fill spans x 56...200.
let hourglassScale: CGFloat = 1.29
let hourglassSize = 256 * hourglassScale
let hourglassHalfWidth = 72 * hourglassScale
let hourglassPath = """
M200,75.64V40a16,16,0,0,0-16-16H72A16,16,0,0,0,56,40V76a16.08,16.08,0,0,0,6.41,12.8L114.67,128,62.4,167.2\
A16.07,16.07,0,0,0,56,180v36a16,16,0,0,0,16,16H184a16,16,0,0,0,16-16V180.36a16,16,0,0,0-6.36-12.77L141.26,128\
l52.38-39.59A16.05,16.05,0,0,0,200,75.64Z
"""

// Clear space between the hourglass and each bracket tip.
let gap: CGFloat = 42
let tipOffset = hourglassHalfWidth + gap + bracketStroke / 2

/// Places a Tabler polyline so its tip (at `tipX` in glyph units) lands on `targetX`.
func chevron(_ points: [CGPoint], tipX: CGFloat, targetX: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { point in
        CGPoint(x: targetX + (point.x - tipX) * tablerScale, y: center + (point.y - 12) * tablerScale)
    })
    return path.copy(strokingWithWidth: bracketStroke, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// chevron-compact-right: M11 4l3 8l-3 8
let left = chevron(
    [CGPoint(x: 11, y: 4), CGPoint(x: 14, y: 12), CGPoint(x: 11, y: 20)],
    tipX: 14,
    targetX: center - tipOffset
)
// chevron-compact-left: M13 20l-3 -8l3 -8
let right = chevron(
    [CGPoint(x: 13, y: 20), CGPoint(x: 10, y: 12), CGPoint(x: 13, y: 4)],
    tipX: 10,
    targetX: center + tipOffset
)

func format(_ value: CGFloat) -> String {
    let rounded = (value * 100).rounded() / 100
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.2f", rounded)
        .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
}

func format(_ point: CGPoint) -> String {
    "\(format(point.x)) \(format(point.y))"
}

func svgPathData(_ path: CGPath) -> String {
    var commands: [String] = []
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            commands.append("M\(format(points[0]))")
        case .addLineToPoint:
            commands.append("L\(format(points[0]))")
        case .addQuadCurveToPoint:
            commands.append("Q\(format(points[0])) \(format(points[1]))")
        case .addCurveToPoint:
            commands.append("C\(format(points[0])) \(format(points[1])) \(format(points[2]))")
        case .closeSubpath:
            commands.append("Z")
        @unknown default:
            fatalError("Unsupported path element")
        }
    }
    return commands.joined()
}

func svg(_ body: String) -> String {
    let size = format(canvas)
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)">
      \(body)
    </svg>

    """
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift Design/AppIcon/layers.swift <Assets directory>\n".utf8))
    exit(64)
}

let assets = URL(fileURLWithPath: arguments[1], isDirectory: true)

let brackets = svg(#"<path fill="\#(bracketColor)" d="\#(svgPathData(left.union(right)))"/>"#)

let origin = format(center - hourglassSize / 2)
let hourglass = svg("""
<g transform="translate(\(origin) \(origin)) scale(\(format(hourglassScale)))">\
<path fill="\(hourglassColor)" d="\(hourglassPath)"/></g>
""")

try brackets.write(to: assets.appendingPathComponent("brackets.svg"), atomically: true, encoding: .utf8)
try hourglass.write(to: assets.appendingPathComponent("hourglass.svg"), atomically: true, encoding: .utf8)
