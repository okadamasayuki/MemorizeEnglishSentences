import Combine
import SwiftUI

/// 各タブの下部に「教材音声の再生中だけ」ミニプレイヤーを挿し込む。
/// (タブバー上のアクセサリ枠は空でも白い枠が出てしまうため、タブの中に置く方式)
struct MiniPlayerHost: ViewModifier {
    @State private var audioActive = false
    @State private var wordActive = false
    @State private var showFullPlayer = false
    @State private var showWordPlayer = false

    private var active: Bool { audioActive || wordActive }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 6) {
                if active {
                    // タブを行き来した時に下からせり上がって見えないよう、
                    // 出現・消滅はアニメーションなしの即時表示にする
                    MiniPlayerBar {
                        // 単語学習が鳴っていればそのプレイヤー、そうでなければ音読プレイヤーを開く
                        if StudyWordPlayer.shared.sessionActive { showWordPlayer = true }
                        else { showFullPlayer = true }
                    }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .padding(.horizontal, 12)
                }
            }
            .sheet(isPresented: $showFullPlayer) {
                AudioPlayerView()
            }
            .sheet(isPresented: $showWordPlayer) {
                StudyWordPlayerView(words: StudyWordPlayer.shared.words)
            }
            .onReceive(AudioSequencePlayer.shared.$isPlayingSequence) { playing in
                if audioActive != playing { audioActive = playing }
            }
            .onReceive(StudyWordPlayer.shared.$sessionActive) { on in
                if wordActive != on { wordActive = on }
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
    @ObservedObject private var word = StudyWordPlayer.shared
    /// タップで全画面プレイヤーを開く
    let onOpen: () -> Void

    /// 単語学習(シス単風)が鳴っているか。そちらを優先して表示・操作する
    private var wordMode: Bool { word.sessionActive }

    var body: some View {
        HStack(spacing: 10) {
            // 今読んでいるもの(音読=文、単語学習=単語と意味)。
            // 縦幅は4行分に固定し、短い文は縦中央に置く
            Text(displayText)
                .font(.footnote)
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 72, alignment: .leading)

            // 一時停止 / 再開
            Button {
                togglePause()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        // 左右・下方向どのスワイプでも停止(全画面プレイヤーの✕と同じ挙動。ミニプレイヤーも消える)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = abs(value.translation.width) > 40
                    let downward = value.translation.height > 40
                    if horizontal || downward { stopActive() }
                }
        )
    }

    private var isPaused: Bool {
        wordMode ? !word.isPlaying : audio.isPaused
    }

    private func togglePause() {
        if wordMode {
            if word.isPlaying { word.pause() } else { word.play() }
        } else {
            if audio.isPaused { audio.resume() } else { audio.pause() }
        }
    }

    private func stopActive() {
        if wordMode { word.stopAll() } else { audio.stop() }
    }

    /// 表示する内容: 単語学習は「単語 — 意味」、音読は今読んでいる文(和訳中は和訳)
    private var displayText: String {
        if wordMode {
            let w = word.currentWord
            let m = word.currentMeaning
            return m.isEmpty ? w : "\(w) — \(m)"
        }
        if audio.speakingJaSegment != nil, let ja = audio.currentSentenceJa, !ja.isEmpty {
            return ja
        }
        return audio.currentSentence ?? "再生中"
    }
}
