#!/usr/bin/env swift
import Foundation
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let red = NSColor(red: 0.698, green: 0.133, blue: 0.133, alpha: 1)
let white = NSColor.white
let blue = NSColor(red: 0.235, green: 0.235, blue: 0.478, alpha: 1)

let stripeHeight = size / 13
for i in 0..<7 {
    red.setFill()
    NSBezierPath(rect: CGRect(x: 0, y: CGFloat(i * 2) * stripeHeight, width: size, height: stripeHeight)).fill()
}

let cantonWidth = size * 0.4
let cantonHeight = stripeHeight * 7
blue.setFill()
NSBezierPath(rect: CGRect(x: 0, y: size - cantonHeight, width: cantonWidth, height: cantonHeight)).fill()

let starRows = [6, 5, 6, 5, 6, 5, 6, 5, 6]
let starSize: CGFloat = cantonWidth / 12
for (row, count) in starRows.enumerated() {
    let rowY = size - cantonHeight + cantonHeight * CGFloat(row + 1) / CGFloat(starRows.count + 1) - starSize/2
    for col in 0..<count {
        let colX = cantonWidth * CGFloat(col + 1) / CGFloat(count + 1) - starSize/2
        white.setFill()
        NSBezierPath(ovalIn: CGRect(x: colX, y: rowY, width: starSize, height: starSize)).fill()
    }
}

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiff),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    let cwd = FileManager.default.currentDirectoryPath
    let root = cwd.hasSuffix("uscis-case-status-ios") ? cwd : (cwd as NSString).deletingLastPathComponent
    let url = URL(fileURLWithPath: root)
        .appendingPathComponent("USCISCaseTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    try? pngData.write(to: url)
    print("Saved to \(url.path)")
} else {
    print("Failed")
    exit(1)
}
