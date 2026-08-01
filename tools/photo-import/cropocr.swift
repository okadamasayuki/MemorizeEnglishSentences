import Foundation
import Vision
import AppKit

// 使い方: cropocr <image> <y0> <y1>  — 正規化 y 範囲(上=0)を切り出して 2 倍に拡大し OCR する
let args = CommandLine.arguments
let path = args[1]
let y0 = Double(args[2])!, y1 = Double(args[3])!
guard let image = NSImage(contentsOfFile: path),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("load") }
let H = CGFloat(cg.height), W = CGFloat(cg.width)
let rect = CGRect(x: 0, y: H * CGFloat(y0), width: W, height: H * CGFloat(y1 - y0))
guard let cropped = cg.cropping(to: rect) else { fatalError("crop") }

// 2倍拡大
let scale = CGFloat(Double(ProcessInfo.processInfo.environment["OCR_SCALE"] ?? "2") ?? 2)
let ctx = CGContext(data: nil, width: Int(rect.width * scale), height: Int(rect.height * scale),
                    bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: rect.width * scale, height: rect.height * scale))
let scaled = ctx.makeImage()!

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ProcessInfo.processInfo.environment["OCR_JA"] == "1" ? ["ja-JP", "en-US"] : ["en-US", "ja-JP"]
request.usesLanguageCorrection = ProcessInfo.processInfo.environment["OCR_NOCORRECT"] != "1"
try VNImageRequestHandler(cgImage: scaled, options: [:]).perform([request])
struct L: Codable { let text: String; let x: Double; let y: Double }
let lines: [L] = (request.results ?? []).compactMap { obs in
    guard let top = obs.topCandidates(1).first else { return nil }
    let b = obs.boundingBox
    return L(text: top.string, x: b.origin.x, y: 1 - b.origin.y - b.height)
}.sorted { $0.y < $1.y }
print(String(data: try JSONEncoder().encode(lines), encoding: .utf8)!)
