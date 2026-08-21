import UIKit

/// ロック画面の再生中カードに出す「カラオケ風」画像を描く。
/// 前後の文を薄く、いま読んでいる文(英+和)をハイライト枠で大きく表示する
/// (シス単アプリのロック画面表示と同じ方式: アートワーク画像として渡す)。
/// 文は省略せず折り返して全文を出し、長い時は全体の文字サイズを自動で縮めて収める。
enum NowPlayingArtwork {
    struct Line {
        let en: String
        let ja: String
    }

    private static let canvas = CGSize(width: 800, height: 800)
    private static let margin: CGFloat = 40

    static func render(previous: Line?, current: Line, next: Line?, jaActive: Bool) -> UIImage {
        // 収まるまで文字サイズを段階的に縮める
        for scale in [1.0, 0.85, 0.72, 0.6, 0.5, 0.42] {
            if let image = tryRender(previous: previous, current: current, next: next,
                                     jaActive: jaActive, scale: scale, force: false) {
                return image
            }
        }
        return tryRender(previous: previous, current: current, next: next,
                         jaActive: jaActive, scale: 0.42, force: true)!
    }

    private static func tryRender(previous: Line?, current: Line, next: Line?,
                                  jaActive: Bool, scale: CGFloat, force: Bool) -> UIImage? {
        let width = canvas.width - margin * 2

        func para() -> NSMutableParagraphStyle {
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.lineBreakMode = .byWordWrapping  // 省略せず折り返して全文を出す
            return p
        }
        func attr(_ text: String, size fontSize: CGFloat, weight: UIFont.Weight,
                  color: UIColor) -> NSAttributedString {
            NSAttributedString(string: text, attributes: [
                .font: UIFont.systemFont(ofSize: fontSize * scale, weight: weight),
                .foregroundColor: color,
                .paragraphStyle: para(),
            ])
        }
        func height(_ a: NSAttributedString) -> CGFloat {
            ceil(a.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin], context: nil).height)
        }

        let dimEn = UIColor(white: 0.62, alpha: 1)
        let dimJa = UIColor(white: 0.5, alpha: 1)

        struct Block {
            let text: NSAttributedString
            let height: CGFloat
            let inBox: Bool
        }
        var blocks: [Block] = []
        let gap: CGFloat = 14 * scale + 6
        let boxPadding: CGFloat = 22 * scale + 4

        if let previous {
            let en = attr(previous.en, size: 28, weight: .semibold, color: dimEn)
            blocks.append(Block(text: en, height: height(en), inBox: false))
            if !previous.ja.isEmpty {
                let ja = attr(previous.ja, size: 22, weight: .regular, color: dimJa)
                blocks.append(Block(text: ja, height: height(ja), inBox: false))
            }
        }
        let curEn = attr(current.en, size: 40, weight: .bold, color: .white)
        blocks.append(Block(text: curEn, height: height(curEn), inBox: true))
        if !current.ja.isEmpty {
            let curJa = attr(current.ja, size: 30, weight: .semibold,
                             color: jaActive ? UIColor(red: 0.55, green: 0.8, blue: 1, alpha: 1)
                                             : UIColor(white: 0.93, alpha: 1))
            blocks.append(Block(text: curJa, height: height(curJa), inBox: true))
        }
        if let next {
            let en = attr(next.en, size: 28, weight: .semibold, color: dimEn)
            blocks.append(Block(text: en, height: height(en), inBox: false))
            if !next.ja.isEmpty {
                let ja = attr(next.ja, size: 22, weight: .regular, color: dimJa)
                blocks.append(Block(text: ja, height: height(ja), inBox: false))
            }
        }

        // 全体の高さ(ハイライト枠のパディング込み)
        var total: CGFloat = 0
        var prevInBox = false
        for (i, b) in blocks.enumerated() {
            if i > 0 { total += (b.inBox != prevInBox) ? gap + boxPadding : gap * 0.55 }
            total += b.height
            prevInBox = b.inBox
        }
        total += boxPadding * 2  // 枠の上下(先頭/末尾が枠の場合の分も含め概算)
        if !force, total > canvas.height - margin * 2 { return nil }

        let renderer = UIGraphicsImageRenderer(size: canvas)
        return renderer.image { ctx in
            UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: canvas))

            // ハイライト枠の範囲を先に計算
            var y = max(margin, (canvas.height - total) / 2)
            var boxTop: CGFloat = 0
            var boxBottom: CGFloat = 0
            var positions: [CGFloat] = []
            prevInBox = false
            for (i, b) in blocks.enumerated() {
                if i > 0 { y += (b.inBox != prevInBox) ? gap + boxPadding : gap * 0.55 }
                if b.inBox && boxTop == 0 { boxTop = y - boxPadding }
                positions.append(y)
                y += b.height
                if b.inBox { boxBottom = y + boxPadding }
                prevInBox = b.inBox
            }

            let boxRect = CGRect(x: margin - 16, y: boxTop,
                                 width: width + 32, height: boxBottom - boxTop)
            UIColor(red: 0.13, green: 0.22, blue: 0.42, alpha: 1).setFill()
            UIBezierPath(roundedRect: boxRect, cornerRadius: 20).fill()

            for (i, b) in blocks.enumerated() {
                b.text.draw(with: CGRect(x: margin, y: positions[i], width: width, height: b.height),
                            options: [.usesLineFragmentOrigin], context: nil)
            }
        }
    }
}
