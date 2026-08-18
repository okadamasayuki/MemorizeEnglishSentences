import Combine
import SwiftUI

/// 各タブの下部に「教材音声の再生中だけ」ミニプレイヤーを挿し込む。
/// (タブバー上のアクセサリ枠は空でも白い枠が出てしまうため、タブの中に置く方式)
struct MiniPlayerHost: ViewModifier {
    @State private var active = false
    @State private var showFullPlayer = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 6) {
                if active {
                    MiniPlayerBar { showFullPlayer = true }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $showFullPlayer) {
                AudioPlayerView()
            }
            .onReceive(AudioSequencePlayer.shared.$isPlayingSequence) { playing in
                if active != playing {
                    withAnimation(.easeInOut(duration: 0.2)) { active = playing }
                }
            }
    }
}

extension View {
    /// 教材音声の再生中だけ下部にミニプレイヤーを出す
    func miniPlayerHost() -> some View { modifier(MiniPlayerHost()) }
}

/// 画面下(タブバーの上)に出るミニプレイヤー。
/// 音声プレイヤーを下スワイプで閉じても再生は続き、ここに「今読んでいる文」が出る。
/// タップでいつもの全画面プレイヤーに戻る。
struct MiniPlayerBar: View {
    @ObservedObject private var audio = AudioSequencePlayer.shared
    /// タップで全画面プレイヤーを開く
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 今読んでいる文(英語を読んでいる時は英文、和訳を読んでいる時は和訳)。
            // 番号(N/240)や×は置かず、文の表示にスペースを使い切る
            Text(displayText)
                .font(.footnote)
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 一時停止 / 再開
            Button {
                togglePause()
            } label: {
                Image(systemName: audio.isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        // 左右どちらへのスワイプでも一時停止/再開(一時停止ボタンと同じ動き)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if abs(value.translation.width) > 40, abs(value.translation.width) > abs(value.translation.height) {
                        togglePause()
                    }
                }
        )
    }

    private func togglePause() {
        if audio.isPaused { audio.resume() } else { audio.pause() }
    }

    /// 表示する文: 和訳の読み上げ中は和訳、それ以外は英文
    private var displayText: String {
        if audio.speakingJaSegment != nil, let ja = audio.currentSentenceJa, !ja.isEmpty {
            return ja
        }
        return audio.currentSentence ?? "再生中"
    }
}
