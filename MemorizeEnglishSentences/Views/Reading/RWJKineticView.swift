import SwiftUI

/// RWJ(Ray William Johnson)風の「動画っぽい」再生画面のプロトタイプ。
/// 実体は動画ファイルではなく、再生中の音声に同期したリアルタイム描画:
/// - いま読んでいる文をド迷惑なくらい大きな文字で出し、現在の単語がバウンドして弾ける
/// - 文が変わるたびにジャンプカット風に背景色と傾きが切り替わる
/// - 下部に和訳がミーム字幕風に出る
/// AudioPlayerView の🎬ボタンから全画面で開く。音声はそのまま流れ続ける。
struct RWJKineticView: View {
    @ObservedObject private var audio = AudioSequencePlayer.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            KineticStage(item: audio.currentItem,
                         blockIndex: audio.sequenceIndex ?? 0,
                         highlight: audio.highlight,
                         isPaused: audio.isPaused)
                .ignoresSafeArea()

            // 上部: 進捗と閉じる(視覚モードを閉じても再生は続く)
            VStack {
                HStack {
                    if let idx = audio.sequenceIndex {
                        Text("\(idx + 1) / \(audio.itemCount)")
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }
        }
        .statusBarHidden()
        // 画面タップで一時停止/再開(動画アプリと同じ操作感)
        .onTapGesture {
            if audio.isPaused { audio.resume() } else { audio.pause() }
        }
    }
}

/// 実際の描画部分。単語ハイライト(高頻度更新)を監視するのはここだけに閉じる。
private struct KineticStage: View {
    let item: AudioPlaybackItem?
    let blockIndex: Int
    @ObservedObject var highlight: SequenceHighlight
    let isPaused: Bool

    /// 最後に検出できた文番号(ハイライトが途切れる合間も表示を保つ)
    @State private var lastSegmentIndex = 0

    /// ジャンプカット用の背景パレット(暗めの vivid 系)
    private static let palettes: [[Color]] = [
        [Color(red: 0.08, green: 0.09, blue: 0.16), Color(red: 0.16, green: 0.05, blue: 0.25)],
        [Color(red: 0.14, green: 0.04, blue: 0.09), Color(red: 0.30, green: 0.08, blue: 0.05)],
        [Color(red: 0.03, green: 0.12, blue: 0.14), Color(red: 0.02, green: 0.23, blue: 0.20)],
        [Color(red: 0.05, green: 0.07, blue: 0.22), Color(red: 0.02, green: 0.16, blue: 0.33)],
        [Color(red: 0.16, green: 0.11, blue: 0.02), Color(red: 0.30, green: 0.18, blue: 0.02)],
    ]
    private static let tilts: [Double] = [-1.6, 1.2, -0.9, 1.8, -1.2, 0.8]

    var body: some View {
        // 表示する文(セグメント)と単語列を決める
        let segs = segments
        let segIndex = currentSegmentIndex(in: segs)
        let seg = segs.indices.contains(segIndex) ? segs[segIndex] : nil
        let words = seg.map { tokenize($0) } ?? []
        let wordIndex = currentWordIndex(in: words)

        ZStack {
            // ジャンプカット風の背景(文ごとに切り替え)
            LinearGradient(colors: Self.palettes[(blockIndex + segIndex) % Self.palettes.count],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .animation(.easeOut(duration: 0.12), value: segIndex)

            VStack(spacing: 0) {
                Spacer()

                // 本体: 現在の文をデカ文字で。現在の単語だけ弾む
                FlowLayout(spacing: 10, lineSpacing: 14) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                        Text(word.text)
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(i == wordIndex ? Color.yellow
                                             : (i < wordIndex ? Color.white : Color.white.opacity(0.35)))
                            .scaleEffect(i == wordIndex ? 1.22 : 1.0)
                            .rotationEffect(.degrees(i == wordIndex ? Self.tilts[i % Self.tilts.count] : 0))
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 3)
                            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: wordIndex)
                    }
                }
                .padding(.horizontal, 28)
                .rotationEffect(.degrees(Self.tilts[(blockIndex + segIndex) % Self.tilts.count]))
                .animation(.easeOut(duration: 0.12), value: segIndex)
                .frame(maxWidth: .infinity)

                Spacer()

                // ミーム字幕風の和訳
                if let ja = seg?.ja, !ja.isEmpty {
                    Text(ja)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.55)))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 46)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // 一時停止の表示
            if isPaused {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .onChange(of: segIndex) { _, newIndex in
            lastSegmentIndex = newIndex
        }
        .onChange(of: blockIndex) { _, _ in
            lastSegmentIndex = 0
        }
    }

    // MARK: - 文と単語の決定

    private struct DisplaySegment {
        let en: String
        let ja: String
        let range: NSRange
    }

    private struct DisplayWord {
        let text: String
        let range: NSRange
    }

    /// 表示単位の文リスト。文ペアが無いブロックは全文を1文として扱う
    private var segments: [DisplaySegment] {
        guard let item else { return [] }
        if let segs = item.segments, !segs.isEmpty {
            return segs.map { DisplaySegment(en: $0.en, ja: $0.ja, range: $0.range) }
        }
        return [DisplaySegment(en: item.english, ja: item.japanese,
                               range: NSRange(location: 0, length: (item.english as NSString).length))]
    }

    /// いま鳴っている単語ハイライトが属する文。見つからない間は直前の文を保つ
    private func currentSegmentIndex(in segs: [DisplaySegment]) -> Int {
        guard let range = highlight.range, range.location != NSNotFound else {
            return min(lastSegmentIndex, max(segs.count - 1, 0))
        }
        for (i, seg) in segs.enumerated() {
            if range.location >= seg.range.location,
               range.location < seg.range.location + seg.range.length {
                return i
            }
        }
        return min(lastSegmentIndex, max(segs.count - 1, 0))
    }

    /// 文の英文を表示用の単語列に分ける(ブロック全文の中での NSRange 付き)
    private func tokenize(_ seg: DisplaySegment) -> [DisplayWord] {
        var out: [DisplayWord] = []
        let ns = seg.en as NSString
        var cursor = 0
        for piece in seg.en.split(whereSeparator: { $0.isWhitespace }) {
            let word = String(piece)
            let r = ns.range(of: word, options: [], range: NSRange(location: cursor, length: ns.length - cursor))
            guard r.location != NSNotFound else { continue }
            out.append(DisplayWord(text: word,
                                   range: NSRange(location: seg.range.location + r.location, length: r.length)))
            cursor = r.location + r.length
        }
        return out
    }

    /// いま鳴っている単語の番号(-1 = まだ文の頭)
    private func currentWordIndex(in words: [DisplayWord]) -> Int {
        guard let range = highlight.range, range.location != NSNotFound else { return -1 }
        for (i, word) in words.enumerated() {
            if range.location >= word.range.location,
               range.location < word.range.location + word.range.length {
                return i
            }
        }
        return -1
    }

}
