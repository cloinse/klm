#!/usr/bin/env swift

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
  FileHandle.standardError.write(Data("Usage: create_dmg_background.swift <output.png>\n".utf8))
  exit(64)
}

let width = 660
let height = 400

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: width,
  pixelsHigh: height,
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  exit(1)
}
NSGraphicsContext.current = context

let canvas = NSRect(x: 0, y: 0, width: width, height: height)
let background = NSGradient(
  starting: NSColor(calibratedRed: 0.98, green: 0.99, blue: 1.0, alpha: 1),
  ending: NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.97, alpha: 1)
)
background?.draw(in: canvas, angle: 90)

let panel = NSBezierPath(
  roundedRect: NSRect(x: 34, y: 42, width: 592, height: 322),
  xRadius: 28,
  yRadius: 28
)
NSColor.white.withAlphaComponent(0.62).setFill()
panel.fill()
NSColor(calibratedWhite: 0.73, alpha: 0.42).setStroke()
panel.lineWidth = 1
panel.stroke()

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowBlurRadius = 12
shadow.shadowOffset = NSSize(width: 0, height: -3)
shadow.set()

let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 264, y: 174))
arrow.line(to: NSPoint(x: 346, y: 174))
arrow.line(to: NSPoint(x: 346, y: 150))
arrow.line(to: NSPoint(x: 407, y: 190))
arrow.line(to: NSPoint(x: 346, y: 230))
arrow.line(to: NSPoint(x: 346, y: 206))
arrow.line(to: NSPoint(x: 264, y: 206))
arrow.close()
NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.18, alpha: 1).setFill()
arrow.fill()

let instruction = "To use, please install KLM in the Applications folder"
let instructionStyle = NSMutableParagraphStyle()
instructionStyle.alignment = .center
let instructionAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 16, weight: .medium),
  .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 0.88),
  .paragraphStyle: instructionStyle,
]
instruction.draw(
  in: NSRect(x: 52, y: 292, width: 556, height: 28),
  withAttributes: instructionAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  exit(1)
}
try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
