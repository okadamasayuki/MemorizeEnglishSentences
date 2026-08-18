import SwiftUI
import UIKit

/// 近くの UIScrollView(List/ScrollView の中身)の scrollsToTop を無効にする。
/// これで「タブを再タップするとトップへスクロール」や「ステータスバータップでトップへ」を止める。
/// 使い方: 対象の List/ScrollView に `.background(DisableScrollToTop())` を付ける。
struct DisableScrollToTop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // レイアウト確定後にスクロールビューを探して無効化する
        DispatchQueue.main.async { disable(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { disable(from: uiView) }
    }

    private func disable(from view: UIView) {
        // まず先祖方向を探す
        var ancestor: UIView? = view.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scroll.scrollsToTop = false
                return
            }
            ancestor = current.superview
        }
        // 見つからなければ、共通の親配下の子孫からスクロールビューを探す
        if let root = view.superview {
            findScrollView(in: root)?.scrollsToTop = false
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let scroll = subview as? UIScrollView { return scroll }
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}
