import SwiftUI
import UIKit

/// 行末まで詰めて折り返すテキスト表示。
/// SwiftUI の Text は日本語で「単語のまとまり優先」の改行をして
/// 行が早めに折り返されることがあるため、UILabel で改行戦略を無効にする。
struct NaturalWrapText: UIViewRepresentable {
    let text: String
    var textStyle: UIFont.TextStyle = .title3
    var lineSpacing: CGFloat = 6

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakStrategy = []
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakStrategy = []
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: textStyle),
                .paragraphStyle: style,
            ]
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }
}
