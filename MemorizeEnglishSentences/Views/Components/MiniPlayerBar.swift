import SwiftUI

/// 画面下(タブバーの上)に出るミニプレイヤー。
/// 音声プレイヤーを下スワイプで閉じても再生は続き、ここに「今読んでいる文」が出る。
/// タップでいつもの全画面プレイヤーに戻る。
struct MiniPlayerBar: View {
    @ObservedObject private var audio = AudioSequencePlayer.shared
    /// タップで全画面プレイヤーを開く
    let onOpen: () -> Void

    var body: some View {
        // tabViewBottomAccessory(タブバーの上の帯)に入るため、背景は持たずコンパクトに
        HStack(spacing: 10) {
            if let idx = audio.sequenceIndex {
                Text("\(idx + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            // 今読んでいる文
            Text(audio.currentSentence ?? "再生中")
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 一時停止 / 再開
            Button {
                if audio.isPaused { audio.resume() } else { audio.pause() }
            } label: {
                Image(systemName: audio.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            // 停止(ミニプレイヤーも消える)
            Button {
                audio.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}
