import UIKit
import Vision

enum TextRecognitionError: LocalizedError {
    case noText

    var errorDescription: String? {
        "写真から英文を読み取れませんでした。文字がはっきり写っているか確認してください。"
    }
}

/// Vision (VNRecognizeTextRequest) による英文 OCR。オンデバイスで動作しオフラインでも使える。
/// 行の縦方向の間隔から段落を検出し、段落間を空行で区切って返す(教科書の Content Block 対応)。
enum TextRecognitionService {
    static func recognizeEnglishText(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw TextRecognitionError.noText
        }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = Self.buildParagraphText(from: observations)
                if text.isEmpty {
                    continuation.resume(throwing: TextRecognitionError.noText)
                } else {
                    continuation.resume(returning: text)
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - 段落検出

    private struct Line {
        let text: String
        let box: CGRect
    }

    private static func buildParagraphText(from observations: [VNRecognizedTextObservation]) -> String {
        // 信頼度が低い行と、英文でない行(日本語見出しなど)を除外
        let candidates: [Line] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence >= 0.3 else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, isMostlyEnglish(text) else { return nil }
            return Line(text: text, box: observation.boundingBox)
        }
        guard !candidates.isEmpty else { return "" }

        let allHeights = candidates.map(\.box.height).sorted()
        let medianHeight = allHeights[allHeights.count / 2]

        // ノイズ行を除外:
        // - 行の高さが極端に大きい(他ページの写り込みやルビの誤認識)
        // - 小文字を含まない(「BEONE TE」のような誤認識や飾り文字)
        // - 2 語以下で文末記号がない(「Content Block」のようなラベル行)
        let lines = candidates.filter { line in
            guard line.box.height <= medianHeight * 1.8 else { return false }
            guard line.text.contains(where: { $0.isLowercase && $0.isASCII }) else { return false }
            let words = line.text.split(whereSeparator: { $0.isWhitespace })
            if words.count <= 2, !line.text.contains(where: { ".!?".contains($0) }) {
                return false
            }
            return true
        }
        guard !lines.isEmpty else { return "" }

        // 上から下へ並べる(Vision の座標系は左下原点)
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }

        var paragraphs: [[String]] = []
        var current: [String] = []
        var previous: Line?

        for line in sorted {
            if let previous {
                // 行間が通常より明らかに広いところを段落境界とみなす
                let gap = previous.box.minY - line.box.maxY
                if gap > medianHeight * 0.45 {
                    if !current.isEmpty {
                        paragraphs.append(current)
                    }
                    current = []
                }
            }
            current.append(line.text)
            previous = line
        }
        if !current.isEmpty {
            paragraphs.append(current)
        }

        // 段落内の行はスペースで連結し、段落間は空行で区切る
        return paragraphs
            .map { $0.joined(separator: " ") }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 英文の行かどうか(ASCII 英字が過半数を占めるか)
    private static func isMostlyEnglish(_ text: String) -> Bool {
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        let ascii = letters.filter { $0.isASCII }
        return Double(ascii.count) / Double(letters.count) >= 0.5
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
