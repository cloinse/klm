#!/usr/bin/env swift
import AppKit
import Foundation

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("klm.png")
let macOSDirectory = root.appendingPathComponent(
  "macos/Runner/Assets.xcassets/AppIcon.appiconset",
  isDirectory: true
)
let windowsIconURL = root.appendingPathComponent(
  "windows/runner/resources/app_icon.ico"
)

guard let source = NSImage(contentsOf: sourceURL) else {
  fatalError("Unable to load \(sourceURL.path)")
}

func resizedPNG(size: Int) -> Data {
  guard
    let bitmap = NSBitmapImageRep(
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
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    fatalError("Unable to create \(size)x\(size) icon bitmap")
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  source.draw(
    in: NSRect(x: 0, y: 0, width: size, height: size),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1
  )
  context.flushGraphics()
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode \(size)x\(size) icon")
  }
  return png
}

let macOSSizes = [16, 32, 64, 128, 256, 512, 1024]
for size in macOSSizes {
  let destination = macOSDirectory.appendingPathComponent(
    "app_icon_\(size).png"
  )
  try resizedPNG(size: size).write(to: destination, options: .atomic)
}

func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
  var encoded = value.littleEndian
  withUnsafeBytes(of: &encoded) { bytes in
    data.append(contentsOf: bytes)
  }
}

let windowsSizes = [256, 128, 64, 48, 40, 32, 24, 20, 16]
let windowsImages = windowsSizes.map { resizedPNG(size: $0) }
var icon = Data()
appendLittleEndian(UInt16(0), to: &icon)
appendLittleEndian(UInt16(1), to: &icon)
appendLittleEndian(UInt16(windowsImages.count), to: &icon)

var offset = UInt32(6 + windowsImages.count * 16)
for (index, size) in windowsSizes.enumerated() {
  icon.append(UInt8(size == 256 ? 0 : size))
  icon.append(UInt8(size == 256 ? 0 : size))
  icon.append(0)
  icon.append(0)
  appendLittleEndian(UInt16(1), to: &icon)
  appendLittleEndian(UInt16(32), to: &icon)
  appendLittleEndian(UInt32(windowsImages[index].count), to: &icon)
  appendLittleEndian(offset, to: &icon)
  offset += UInt32(windowsImages[index].count)
}
for image in windowsImages {
  icon.append(image)
}

try icon.write(to: windowsIconURL, options: .atomic)
print("Generated macOS and Windows icons from \(sourceURL.lastPathComponent)")
