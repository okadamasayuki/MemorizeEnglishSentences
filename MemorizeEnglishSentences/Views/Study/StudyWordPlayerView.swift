import SwiftUI

/// 覚える単語リストをシス単風に再生する画面。
/// 単語+意味を並べ、今の単語をハイライトして自動送り。
/// 各単語は「英語 → 日本語の意味 → 英語(もう一度)」の順で読む(シス単のCDと同じ流れ)。
struct StudyWordPlayerView: View {
    let words: [StudyStore.StudyWord]
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = StudyWordPlayer.shared
    /// 再生倍率(1.0=標準)。音声の速さと間隔の両方に効く。アプリを閉じても記憶。
    @AppStorage("studyWordSpeed") private var speed = 1.0
    /// 一番下まで来たら先頭に戻って繰り返す(リピート)。アプリを閉じても記憶
    @AppStorage("studyWordLoop") private var loop = false

    // 倍率(左=ゆっくり0.75倍 → 右=速い3倍)。標準1倍が本家シス単の実測テンポ
    private let speeds: [Double] = [0.75, 1.0, 1.5, 2.0, 3.0]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(min(player.index + 1, words.count)) / \(words.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    player.stopAll()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            // 単語リスト(現在をハイライト・自動スクロール)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { i, w in
                            row(w, current: i == player.index)
                                .id(i)
                                .onTapGesture { player.jump(to: i) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: player.index) { _, i in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(i, anchor: .center) }
                }
            }

            // 再生倍率(左=ゆっくり0.75倍 → 右=速い3倍)
            HStack(spacing: 6) {
                ForEach(speeds, id: \.self) { value in
                    Button {
                        speed = value
                        player.speed = value
                    } label: {
                        Text(speedLabel(value))
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(speed == value ? Color.accentColor : Color(.secondarySystemBackground)))
                            .foregroundStyle(speed == value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // 前 / 再生・一時停止 / 次 / リピート
            HStack(spacing: 20) {
                Button { player.prev() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title).frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
                // リピート(一番下まで来たら先頭へ戻って繰り返す)。ONは青
                Button {
                    loop.toggle()
                    player.loop = loop
                } label: {
                    Image(systemName: "repeat").font(.title3)
                        .foregroundStyle(loop ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            player.speed = speed
            player.loop = loop
            // ミニプレイヤーから開き直した時(再生継続中)は続きから。
            // 初めて開いた時だけ、単語をセットして最初から再生する
            if !player.sessionActive {
                player.configure(words: words)
                if !words.isEmpty { player.play() }
            }
        }
        // 画面を閉じても再生は止めない(下スワイプでミニプレイヤーに残す)。
        // 完全に止めるのは×ボタンかミニプレイヤーのスワイプで
    }

    /// 倍率の表示("0.75倍" "1倍" "1.5倍" "2倍" "3倍")
    private func speedLabel(_ v: Double) -> String {
        String(format: "%g倍", v)
    }

    @ViewBuilder
    private func row(_ w: StudyStore.StudyWord, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(w.word)
                .font(current ? .title.bold() : .title3.weight(.medium))
                .foregroundStyle(current ? Color.white : Color.primary)
            if !w.meaning.isEmpty {
                Text(w.meaning)
                    .font(current ? .body : .subheadline)
                    .foregroundStyle(current ? Color.white.opacity(0.9) : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, current ? 14 : 10)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(current ? Color.accentColor : Color(.secondarySystemBackground)))
        .opacity(current ? 1 : 0.85)
    }
}
