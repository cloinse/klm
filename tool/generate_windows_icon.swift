#!/usr/bin/env swift

import AppKit

guard CommandLine.arguments.count == 3 else {
  FileHandle.standardError.write(
    Data("Usage: generate_windows_icon.swift SOURCE.png OUTPUT.ico\n".utf8)
  )
  exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = NSImage(contentsOf: sourceURL),
      source.size.width > 0,
      source.size.height > 0
else {
  FileHandle.standardError.write(Data("Unable to read source image.\n".utf8))
  exit(66)
}

let sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
var frames = [Data]()

for size in sizes {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    exit(70)
  }

  bitmap.size = NSSize(width: size, height: size)
  NSGraphicsContext.saveGraphicsState()
  guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    NSGraphicsContext.restoreGraphicsState()
    exit(70)
  }
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()

  let maximumDimension = CGFloat(size) * 0.88
  let scale = min(
    maximumDimension / source.size.width,
    maximumDimension / source.size.height
  )
  let width = source.size.width * scale
  let height = source.size.height * scale
  let destinationRect = NSRect(
    x: (CGFloat(size) - width) / 2,
    y: (CGFloat(size) - height) / 2,
    width: width,
    height: height
  )
  source.draw(
    in: destinationRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
  )
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    exit(70)
  }
  frames.append(png)
}

func appendUInt16(_ value: UInt16, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
  data.append(UInt8(value & 0xff))
  data.append(UInt8((value >> 8) & 0xff))
  data.append(UInt8((value >> 16) & 0xff))
  data.append(UInt8((value >> 24) & 0xff))
}

var icon = Data()
appendUInt16(0, to: &icon)
appendUInt16(1, to: &icon)
appendUInt16(UInt16(frames.count), to: &icon)

var offset = UInt32(6 + (16 * frames.count))
for (index, frame) in frames.enumerated() {
  let size = sizes[index]
  icon.append(size == 256 ? 0 : UInt8(size))
  icon.append(size == 256 ? 0 : UInt8(size))
  icon.append(0)
  icon.append(0)
  appendUInt16(1, to: &icon)
  appendUInt16(32, to: &icon)
  appendUInt32(UInt32(frame.count), to: &icon)
  appendUInt32(offset, to: &icon)
  offset += UInt32(frame.count)
}
for frame in frames { icon.append(frame) }

do {
  try icon.write(to: outputURL, options: .atomic)
} catch {
  FileHandle.standardError.write(Data("Unable to write ICO file: \(error)\n".utf8))
  exit(74)
}
