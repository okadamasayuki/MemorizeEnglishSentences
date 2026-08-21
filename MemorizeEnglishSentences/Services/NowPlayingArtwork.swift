import UIKit

/// ロック画面の再生中カードに出す「カラオケ風」画像を描く。
/// 前後の文を薄く、いま読んでいる文(英+和)をハイライト枠で大きく表示する
/// (シス単アプリのロック画面表示と同じ方式: アートワーク画像として渡す)。
enum NowPlayingArtwork {
    struct Line {
        let en: String
        let ja: String
    }

    static func render(previous: Line?, current: Line, next: Line?, jaActive: Bool) -> UIImage {
        let size = CGSize(width: 800, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            // 背景(ロック画面になじむ濃紺)
            UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let margin: CGFloat = 44
            let width = size.width - margin * 2

            func paragraph() -> NSMutableParagraphStyle {
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                p.lineBreakMode = .byTruncatingTail
                return p
            }

            func attr(_ text: String, size fontSize: CGFloat, weight: UIFont.Weight,
                      color: UIColor) -> NSAttributedString {
                NSAttributedString(string: text, attributes: [
                    .font: UIFont.systemFont(ofSize: fontSize, weight: weight),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph(),
                ])
            }

            func height(_ a: NSAttributedString, maxHeight: CGFloat) -> CGFloat {
                min(maxHeight, ceil(a.boundingRect(with: CGSize(width: width, height: maxHeight),
                                                   options: [.usesLineFragmentOrigin], context: nil).height))
            }

            // 現在の文(中央・ハイライト)
            let dimEn = UIColor(white: 0.62, alpha: 1)
            let dimJa = UIColor(white: 0.52, alpha: 1)
            let curEn = attr(current.en, size: 44, weight: .bold, color: .white)
            let curJa = attr(current.ja, size: 32, weight: .semibold,
                             color: jaActive ? UIColor(red: 0.55, green: 0.78, blue: 1, alpha: 1) : UIColor(white: 0.92, alpha: 1))
            let curEnH = height(curEn, maxHeight: 220)
            let curJaH = current.ja.isEmpty ? 0 : height(curJa, maxHeight: 150)
            let boxPadding: CGFloat = 26
            let boxH = curEnH + (curJaH > 0 ? curJaH + 12 : 0) + boxPadding * 2
            let boxRect = CGRect(x: margin - 18, y: (size.height - boxH) / 2,
                                 width: width + 36, height: boxH)
            let box = UIBezierPath(roundedRect: boxRect, cornerRadius: 22)
            UIColor(red: 0.13, green: 0.22, blue: 0.42, alpha: 1).setFill()
            box.fill()
            var y = boxRect.minY + boxPadding
            curEn.draw(with: CGRect(x: margin, y: y, width: width, height: curEnH),
                       options: [.usesLineFragmentOrigin], context: nil)
            y += curEnH + 12
            if curJaH > 0 {
                curJa.draw(with: CGRect(x: margin, y: y, width: width, height: curJaH),
                           options: [.usesLineFragmentOrigin], context: nil)
            }

            // 前の文(上・薄く)
            if let previous {
                let en = attr(previous.en, size: 30, weight: .semibold, color: dimEn)
                let ja = attr(previous.ja, size: 24, weight: .regular, color: dimJa)
                let enH = height(en, maxHeight: 84)
                let jaH = previous.ja.isEmpty ? 0 : height(ja, maxHeight: 64)
                var py = boxRect.minY - 30 - enH - (jaH > 0 ? jaH + 6 : 0)
                py = max(20, py)
                en.draw(with: CGRect(x: margin, y: py, width: width, height: enH),
                        options: [.usesLineFragmentOrigin], context: nil)
                if jaH > 0 {
                    ja.draw(with: CGRect(x: margin, y: py + enH + 6, width: width, height: jaH),
                            options: [.usesLineFragmentOrigin], context: nil)
                }
            }

            // 次の文(下・薄く)
            if let next {
                let en = attr(next.en, size: 30, weight: .semibold, color: dimEn)
                let ja = attr(next.ja, size: 24, weight: .regular, color: dimJa)
                let enH = height(en, maxHeight: 84)
                let jaH = next.ja.isEmpty ? 0 : height(ja, maxHeight: 64)
                let ny = boxRect.maxY + 30
                if ny + enH < size.height - 20 {
                    en.draw(with: CGRect(x: margin, y: ny, width: width, height: enH),
                            options: [.usesLineFragmentOrigin], context: nil)
                    if jaH > 0, ny + enH + 6 + jaH < size.height - 12 {
                        ja.draw(with: CGRect(x: margin, y: ny + enH + 6, width: width, height: jaH),
                                options: [.usesLineFragmentOrigin], context: nil)
                    }
                }
            }
        }
    }
}
