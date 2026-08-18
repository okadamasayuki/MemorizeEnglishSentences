import SwiftUI

/// 画面下(タブバーの上)に出るミニプレイヤー。
/// 音声プレイヤーを下スワイプで閉じても再生は続き、ここに「今読んでいる文」が出る。
/// タップでいつもの全画面プレイヤーに戻る。
struct MiniPlayerBar: View {
    @ObservedObject private var audio = AudioSequencePlayer.shared
    /// タップで全画面プレイヤーを開く
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 今読んでいる文(なければ項目番号)
            VStack(alignment: .leading, spacing: 2) {
                if let idx = audio.sequenceIndex {
                    Text("\(idx + 1) / \(audio.itemCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(audio.currentSentence ?? "再生中")
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 一時停止 / 再開
            Button {
                if audio.isPaused { audio.resume() } else { audio.pause() }
            } label: {
                Image(systemName: audio.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            // 停止(ミニプレイヤーも消える)
            Button {
                audio.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
