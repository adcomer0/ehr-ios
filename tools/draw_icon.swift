// Historical standalone-lab artwork only. The branded game uses the tracked
// AppIcon.png master and --app-icon; do not overwrite that master with this.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Output directory required") }
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.035, green: 0.09, blue: 0.14, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedRed: 0.16, green: 0.85, blue: 0.75, alpha: 1).setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 162, y: 290, width: 700, height: 440), xRadius: 100, yRadius: 100)
frame.lineWidth = 25
frame.stroke()
let text = "EHR" as NSString
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 210, weight: .bold), .foregroundColor: NSColor.white]
let size = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: (1024-size.width)/2, y: 430), withAttributes: attrs)
let lab = "PORT LAB" as NSString
let labAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 52, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.16, green: 0.85, blue: 0.75, alpha: 1)]
let labSize = lab.size(withAttributes: labAttrs)
lab.draw(at: NSPoint(x: (1024-labSize.width)/2, y: 365), withAttributes: labAttrs)
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("AppIcon.png"))
let json = """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
"""
try json.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
