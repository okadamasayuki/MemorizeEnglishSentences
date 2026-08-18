import SwiftUI
import UIKit

/// 教材音声(MP3)の連続再生プレイヤー画面。
/// いま読んでいる英文を大きく表示し、再生位置の単語をハイライト、下に和訳を表示する。
/// 操作はTTS版(SentencePlayerView)と同じ: 前後・一時停止・速度・各文2回読み。
struct AudioPlayerView: View {
    @ObservedObject private var audio = AudioSequencePlayer.shared
    @Environment(\.dismiss) private var dismiss
    /// 読み上げ速度倍率(1.0=標準)。TTS版と共有・記憶
    @AppStorage("listenSpeed") private var listenSpeed = 1.0
    /// 各英文の後にその文の和訳をTTSで読むか(全項目共通・記憶)
    @AppStorage("audioJaAfterSentence") private var jaAfterSentence = false
    /// 和訳を英文の上に表示するか(文のどこかを長押しで入れ替え。全項目共通・記憶)
    @AppStorage("audioJaFirst") private var jaFirst = false
    /// 現在ブロックの文ごと再生回数(表示用。保存は SentenceRepeatStore)
    @State private var counts: [Int] = []
    /// ブロック全体の繰り返し回数(全項目共通)
    @State private var blockCount: Int = 1
    /// RWJ風の動画っぽい表示(プロトタイプ)を出しているか
    @State private var showKinetic = false
    /// このブロックで報告済みの文番号(押した丸を赤く塗る目印)
    @State private var reportedHeads: Set<Int> = []
    @State private var reportedTails: Set<Int> = []

    // 教材音声はレート変換の音質を考慮して 0.5〜2x
    private let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 12) {
            // 上部: 進捗・閉じる
            HStack {
                if let idx = audio.sequenceIndex {
                    Text("\(idx + 1) / \(audio.itemCount)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // RWJ風の動画っぽい表示(プロトタイプ)
                Button {
                    showKinetic = true
                } label: {
                    Image(systemName: "movieclapper")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.plain)
                // 各英文の後にその文の和訳を読み上げるモード。
                // 長押しで和訳の「声」を切り替えられる(比較用。記憶される)
                Button {
                    jaAfterSentence.toggle()
                    audio.setJaAfterSentence(jaAfterSentence)
                } label: {
                    Text("和訳")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(jaAfterSentence ? Color.accentColor
                                                                   : Color(.secondarySystemBackground)))
                        .foregroundStyle(jaAfterSentence ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    ForEach(JaAudioStore.voices, id: \.id) { voice in
                        Button {
                            JaAudioStore.selectedVariant = voice.id
                        } label: {
                            if JaAudioStore.selectedVariant == voice.id {
                                Label(voice.name, systemImage: "checkmark")
                            } else {
                                Text(voice.name)
                            }
                        }
                    }
                }
                // ブロック全体(文ごとの一式)を何回再生するか(全項目共通)。
                // ×3は使わないため廃止し、タップで ×1↔×2 を切り替える
                Button {
                    setBlockCount(blockCount == 1 ? 2 : 1)
                } label: {
                    Text("×\(blockCount)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(blockCount > 1 ? Color.accentColor
                                                                  : Color(.secondarySystemBackground)))
                        .foregroundStyle(blockCount > 1 ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                Button {
                    audio.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)

            // いま読んでいるブロック。暗記タブと同じページめくり(指に追従)で
            // 左右スワイプすると前後の項目へ移動し、その項目の頭から再生される。
            TabView(selection: Binding(
                get: { audio.sequenceIndex ?? 0 },
                set: { audio.jump(to: $0) }
            )) {
                // TabView(.page) は全ページを一度に作ってしまうため、
                // 表示中と左右1ページ以外は空にして軽くする(240項目で顕著に効く)
                ForEach(0..<max(audio.itemCount, 1), id: \.self) { index in
                    Group {
                        if abs(index - (audio.sequenceIndex ?? 0)) <= 1 {
                            page(index)
                        } else {
                            Color.clear
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // 再生時間スライダー(×2などの回数設定を織り込んだ合計時間)
            AudioProgressSlider(progress: audio.progress) { value in
                audio.seekVirtual(to: value)
            }
            .padding(.horizontal, 24)

            // 速度ボタン
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(speedOptions, id: \.self) { speed in
                        Button {
                            listenSpeed = speed
                            audio.setSpeed(speed)
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

            // 5秒戻し / 一時停止・再開 / 5秒送り(前後の項目は左右スワイプで)
            HStack(spacing: 14) {
                Button {
                    audio.seek(by: -5)
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.title3)
                }
                .buttonStyle(.bordered)

                Button {
                    if audio.isPaused {
                        audio.resume()
                    } else {
                        audio.pause()
                    }
                } label: {
                    Image(systemName: audio.isPaused ? "play.fill" : "pause.fill")
                        .font(.title)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    audio.seek(by: 5)
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 24)
        }
        // RWJ風の動画っぽい表示(プロトタイプ)。音声はそのまま流れ続ける
        .fullScreenCover(isPresented: $showKinetic) {
            RWJKineticView()
        }
        // 再生が終わったら自動で閉じる
        .onChange(of: audio.isPlayingSequence) { _, playing in
            if !playing { dismiss() }
        }
        .onAppear {
            syncCounts()
        }
        // ブロックが変わったら、そのブロックの保存済み回数設定を読み込む
        .onChange(of: audio.sequenceIndex) { _, _ in
            syncCounts()
            reportedHeads.removeAll()
            reportedTails.removeAll()
        }
    }

    /// ハイライト無し(表示中でないページ用)の空のハイライト
    private static let idleHighlight = SequenceHighlight()

    /// 1項目分のページ。文ペアがあれば「英文1文→その和訳→…」の交互表示
    /// (再生位置の単語ハイライト付き)。無ければ全文+全訳。
    @ViewBuilder
    private func page(_ index: Int) -> some View {
        let item = audio.item(at: index)
        let isCurrent = index == audio.sequenceIndex
        ScrollView {
            if let item, let segments = item.segments {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 6) {
                                // 英文と和訳の表示順(長押しで入れ替え。和訳→英文は和文英訳の練習用)
                                if jaFirst, !seg.ja.isEmpty {
                                    Text(seg.ja)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                AudioSegmentHighlightView(text: seg.en, segmentRange: seg.range,
                                                          highlight: isCurrent ? audio.highlight : Self.idleHighlight)
                                    .font(.title3.weight(.medium))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !jaFirst, !seg.ja.isEmpty {
                                    Text(seg.ja)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            // ダブルタップでこの文の最初から再生
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                if isCurrent { audio.playSegment(i) }
                            }
                            // 長押しで英文と和訳の上下を入れ替える(全文・全項目に効く。記憶される)
                            .onLongPressGesture {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    jaFirst.toggle()
                                }
                            }
                            // 文頭・文末の「切れ目が変」ワンタップ報告(押すと赤くなり改善タブへ自動追加)
                            .overlay(alignment: .topLeading) {
                                if isCurrent {
                                    reportDot(reported: reportedHeads.contains(i)) {
                                        reportedHeads.insert(i)
                                        reportSegmentIssue(seg: seg, index: i, part: "文頭")
                                    }
                                    .offset(x: -22, y: jaFirst && !seg.ja.isEmpty ? 24 : 2)
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if isCurrent {
                                    reportDot(reported: reportedTails.contains(i)) {
                                        reportedTails.insert(i)
                                        reportSegmentIssue(seg: seg, index: i, part: "文末")
                                    }
                                    .offset(x: 6, y: !jaFirst && !seg.ja.isEmpty ? -24 : -2)
                                }
                            }
                            // ×0は薄く表示(スキップされる文)
                            .opacity(countFor(i) == 0 ? 0.35 : 1)

                            // この文の再生回数(記憶される)。×3は廃止し、タップで ×1↔×2。
                            // 表示中のページだけに出す(スワイプ途中の隣ページには出さない)
                            if isCurrent {
                                Button {
                                    setCount(i, countFor(i) == 1 ? 2 : 1)
                                } label: {
                                    Text("×\(countFor(i))")
                                        .font(.footnote.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            Capsule().fill(countFor(i) > 1 ? Color.accentColor
                                                                           : Color(.secondarySystemBackground))
                                        )
                                        .foregroundStyle(countFor(i) > 1 ? Color.white
                                                         : (countFor(i) == 0 ? Color.secondary : Color.primary))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            } else if let item {
                if jaFirst, !item.japanese.isEmpty {
                    Text(item.japanese)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
                SentenceHighlightView(text: item.english, highlight: isCurrent ? audio.highlight : Self.idleHighlight)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    // 長押しで英文と和訳の上下を入れ替える(記憶される)
                    .onLongPressGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            jaFirst.toggle()
                        }
                    }

                if !jaFirst, !item.japanese.isEmpty {
                    Text(item.japanese)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
            }
        }
    }

    private func speedLabel(_ speed: Double) -> String {
        String(format: "%gx", speed)
    }

    /// この文の再生回数(未読込なら1)
    private func countFor(_ i: Int) -> Int {
        counts.indices.contains(i) ? counts[i] : 1
    }

    /// この文の再生回数を設定し、保存+再生中のスケジュールへ即反映する
    private func setCount(_ i: Int, _ n: Int) {
        guard let item = audio.currentItem, let segs = item.segments else { return }
        if counts.count != segs.count {
            counts = SentenceRepeatStore.counts(forBlockText: item.english, sentenceCount: segs.count)
        }
        guard counts.indices.contains(i) else { return }
        counts[i] = n
        SentenceRepeatStore.set(counts, forBlockText: item.english)
        audio.updateCurrentCounts(counts)
    }

    /// ブロック全体の繰り返し回数を設定する(全項目共通。保存+再生中のスケジュールへ即反映)
    private func setBlockCount(_ n: Int) {
        blockCount = n
        SentenceRepeatStore.globalBlockCount = n
        audio.updateGlobalBlockRepeat(n)
    }

    /// 「切れ目が変」のワンタップ報告ボタン(押すと赤くなる)
    private func reportDot(reported: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: reported ? "circle.fill" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(reported ? Color.red : Color(.systemGray3))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(reported)
    }

    /// 切れ目が変な文の報告を改善タブの一覧へ書き込む(あとでスワイプしてMacへ送る)
    private func reportSegmentIssue(seg: AudioSegment, index: Int, part: String) {
        let block = audio.currentItem?.english ?? ""
        let report = """
        【音声の区切り修正】\(part)が変
        文: \(seg.en)
        (項目\((audio.sequenceIndex ?? 0) + 1)・文\(index + 1)、ブロック先頭: \(String(block.prefix(60)))…)
        """
        ImprovementStore.shared.add(report)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 現在ブロックの保存済み回数設定を読み込む
    private func syncCounts() {
        if let item = audio.currentItem, let segs = item.segments {
            counts = SentenceRepeatStore.counts(forBlockText: item.english, sentenceCount: segs.count)
        } else {
            counts = []
        }
        blockCount = SentenceRepeatStore.globalBlockCount
    }
}

/// 再生時間スライダー(現在位置/合計時間)。進捗は高頻度更新なので
/// このビューだけが再描画されるよう分離している。ドラッグ中は指の位置を表示し、
/// 離した時にシークする。
private struct AudioProgressSlider: View {
    @ObservedObject var progress: PlaybackProgress
    let onSeek: (Double) -> Void
    /// ドラッグ中の値(nil=ドラッグしていない)
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { scrubValue ?? min(progress.position, progress.duration) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(progress.duration, 0.01)
            ) { editing in
                if !editing, let value = scrubValue {
                    onSeek(value)
                    scrubValue = nil
                }
            }
            HStack {
                Text(format(scrubValue ?? progress.position))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(format(progress.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ t: Double) -> String {
        let sec = max(0, Int(t.rounded()))
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }
}

/// ブロック内の1文だけを表示し、その文の範囲に入った単語ハイライトを
/// 座標変換して色付けするビュー(交互表示用)。
/// ハイライトは高頻度更新なので、このビューだけが再描画される。
private struct AudioSegmentHighlightView: View {
    let text: String          // この1文の英文
    let segmentRange: NSRange // ブロック全文の中でのこの文の範囲
    @ObservedObject var highlight: SequenceHighlight

    var body: some View {
        highlighted
    }

    private var highlighted: Text {
        guard let global = highlight.range, global.location != NSNotFound,
              global.location >= segmentRange.location,
              global.location + global.length <= segmentRange.location + segmentRange.length else {
            return Text(text)
        }
        // ブロック全文の座標 → この文内の座標へ変換
        let local = NSRange(location: global.location - segmentRange.location, length: global.length)
        let ns = text as NSString
        guard local.location + local.length <= ns.length else { return Text(text) }
        let before = ns.substring(to: local.location)
        let word = ns.substring(with: local)
        let after = ns.substring(from: local.location + local.length)
        // 太字にすると文字幅が変わってずれるので、色だけでハイライトする
        return Text(before)
            + Text(word).foregroundColor(.accentColor)
            + Text(after)
    }
}
