import SwiftUI
import UIKit

/// sheet(item:) で UIImage を渡すためのラッパー
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 元スクショ(教材ページ)を全画面で表示する。ピンチと ダブルタップで拡大できる。
struct SourceImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    /// 下スワイプで閉じるための一時的な下方向オフセット
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: UIScreen.main.bounds.width)
                    .scaleEffect(scale * pinch)
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in state = value }
                            .onEnded { value in
                                scale = min(max(scale * value, 1), 5)
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scale = scale > 1 ? 1 : 2.5
                        }
                    }
            }
            .offset(y: dragOffset)
            // 拡大していない時、下方向へスワイプすると閉じる
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if scale <= 1.01, value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if scale <= 1.01, value.translation.height > 120 {
                            dismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        }
                    }
            )
            .background(Color(.systemBackground))
            .navigationTitle("元のスクショ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
