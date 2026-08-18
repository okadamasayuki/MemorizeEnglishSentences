import SwiftUI

/// 連続再生する1文の英文と和訳
struct PlaybackItem: Identifiable {
    let id = UUID()
    let english: String
    let japanese: String
}

/// 暗記タブの連続再生中に、いま読んでいる英文を大きく開いて表示し、
/// 読んでいる単語をハイライトするプレイヤー画面。
struct SentencePlayerView: View {
    let items: [PlaybackItem]
    @ObservedObject private var speech = SpeechSynthesisService.shared
    @Environment(\.dismiss) private var dismiss
    /// 読み上げ速度倍率(1.0=標準)。一覧と共有・記憶
    @AppStorage("listenSpeed") private var listenSpeed = 1.0
    /// ボイス識別子(空=既定)。一覧と共有・記憶
    @AppStorage("listenVoiceID") private var listenVoiceID = ""
    /// 各英文を2回ずつ読むか。記憶する
    @AppStorage("repeatEachSentence") private var repeatEach = false

    // 内蔵音声は約2xが上限(それ以上は頭打ち)なので 0.75〜2x を用意
    private let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    // 端末のボイス一覧は列挙が重いので一度だけ取得してキャッシュする(再描画のたびに列挙しない)
    @State private var voices: [(id: String, name: String, quality: String)] = []

    var body: some View {
        VStack(spacing: 20) {
            // 上部: 進捗・ボイス選択・閉じる
            HStack {
                if let idx = speech.sequenceIndex {
                    Text("\(idx + 1) / \(items.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // 各英文を2回ずつ読む
                Button {
                    repeatEach.toggle()
                    speech.repeatSentence = repeatEach
                } label: {
                    Image(systemName: "repeat.1")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(repeatEach ? Color.white : Color.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(repeatEach ? Color.accentColor : Color(.secondarySystemBackground)))
                }
                voiceMenu
                Button {
                    speech.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()

            // いま読んでいる英文(読んでいる単語をハイライト)。
            // ハイライトは単語ごとに高頻度で更新されるので、専用の監視オブジェクトを持つ
            // 別ビューに分けて、ボタン等が巻き添えで再描画されないようにする。
            ScrollView {
                SentenceHighlightView(text: currentEnglish, highlight: speech.sequenceHighlight)
                    .font(.title.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)

                if let japanese = currentJapanese, !japanese.isEmpty {
                    Text(japanese)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
            }

            Spacer()

            // 速度(ボタン + スライダー)を再生・停止の上に置く
            speedControls

            // 前の英文 / 一時停止・再開 / 次の英文
            HStack(spacing: 24) {
                Button {
                    speech.skipToPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)

                Button {
                    if speech.isPaused {
                        speech.resumeSequence()
                    } else {
                        speech.pauseSequence()
                    }
                } label: {
                    Image(systemName: speech.isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                        .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    speech.skipToNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 24)
        }
        // 再生が終わったら自動で閉じる
        .onChange(of: speech.isPlayingSequence) { _, playing in
            if !playing { dismiss() }
        }
        .onAppear {
            if voices.isEmpty { voices = SpeechSynthesisService.naturalEnglishVoices() }
            speech.repeatSentence = repeatEach
        }
    }

    /// ボイス選択メニュー(自然な英語ボイスから選ぶ)
    private var voiceMenu: some View {
        Menu {
            Button {
                listenVoiceID = ""
                speech.setSequenceVoice(nil)
            } label: {
                if listenVoiceID.isEmpty {
                    Label("おすすめ(自動)", systemImage: "checkmark")
                } else {
                    Text("おすすめ(自動)")
                }
            }
            Divider()
            ForEach(voices, id: \.id) { voice in
                Button {
                    listenVoiceID = voice.id
                    speech.setSequenceVoice(voice.id)
                } label: {
                    if listenVoiceID == voice.id {
                        Label("\(voice.name)(\(voice.quality))", systemImage: "checkmark")
                    } else {
                        Text("\(voice.name)(\(voice.quality))")
                    }
                }
            }
        } label: {
            Label(currentVoiceName, systemImage: "person.wave.2")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
        }
    }

    /// 速度コントロール(プリセットボタンを横一列 + スライダー)
    private var speedControls: some View {
        VStack(spacing: 10) {
            // プリセットの速度ボタンを横一列で全部表示
            HStack(spacing: 6) {
                ForEach(speedOptions, id: \.self) { speed in
                    Button {
                        listenSpeed = speed
                        speech.setSequenceSpeed(speed)
                    } label: {
                        Text(speedLabel(speed))
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(listenSpeed == speed ? Color.accentColor : Color(.secondarySystemBackground))
                            )
                            .foregroundStyle(listenSpeed == speed ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    /// 速度の表示(例: "1.0x")
    private func speedLabel(_ speed: Double) -> String {
        String(format: "%gx", speed)
    }

    /// 選択中のボイス名(表示用)
    private var currentVoiceName: String {
        if listenVoiceID.isEmpty { return "声" }
        return voices.first(where: { $0.id == listenVoiceID })?.name ?? "声"
    }

    /// 今読んでいる英文の和訳
    private var currentJapanese: String? {
        guard let idx = speech.sequenceIndex, idx < items.count else { return nil }
        return items[idx].japanese
    }

    /// 今読んでいる英文(全文)
    private var currentEnglish: String {
        speech.currentText
            ?? speech.sequenceIndex.flatMap { $0 < items.count ? items[$0].english : nil }
            ?? ""
    }
}

/// 今読んでいる英文を、読んでいる単語だけ色付きにして表示する。
/// ハイライト(単語範囲)は高頻度で更新されるので、これだけを別ビューにして
/// 本体(ボタン等)の再描画を巻き添えにしないようにする。
/// (TTSプレイヤーと教材音声プレイヤーの両方で使う)
struct SentenceHighlightView: View {
    let text: String
    @ObservedObject var highlight: SequenceHighlight

    var body: some View {
        highlighted
    }

    private var highlighted: Text {
        guard let range = highlight.range, range.location != NSNotFound else {
            return Text(text)
        }
        let ns = text as NSString
        guard range.location + range.length <= ns.length else { return Text(text) }
        let before = ns.substring(to: range.location)
        let word = ns.substring(with: range)
        let after = ns.substring(from: range.location + range.length)
        // 太字にすると文字幅が変わって周りの単語がずれるので、色だけでハイライトする
        return Text(before)
            + Text(word).foregroundColor(.accentColor)
            + Text(after)
    }
}
