import Foundation
import Vision
import AppKit

// 引数の画像ファイルを Vision OCR にかけ、行ごとのテキストと位置(正規化座標)を JSON で出力する
struct Line: Codable {
    let text: String
    let x: Double
    let y: Double  // 上端 = 0 になるよう反転済み
    let w: Double
    let h: Double
}
struct PageResult: Codable {
    let file: String
    let lines: [Line]
}

var results: [PageResult] = []
for path in CommandLine.arguments.dropFirst() {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("cannot load \(path)\n".data(using: .utf8)!)
        continue
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ProcessInfo.processInfo.environment["OCR_LANGS"] == "ja" ? ["ja-JP", "en-US"] : ["en-US", "ja-JP"]
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    try handler.perform([request])
    let lines: [Line] = (request.results ?? []).compactMap { obs in
        guard let top = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox
        return Line(text: top.string, x: b.origin.x, y: 1 - b.origin.y - b.height, w: b.width, h: b.height)
    }
    results.append(PageResult(file: path, lines: lines))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted]
print(String(data: try encoder.encode(results), encoding: .utf8)!)
