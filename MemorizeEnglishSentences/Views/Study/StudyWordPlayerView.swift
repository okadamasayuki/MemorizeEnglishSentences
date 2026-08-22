import SwiftUI

/// 覚える単語リストをシス単風に再生する画面。
/// 単語+意味を並べ、今の単語をハイライトして自動送り。
/// 各単語は「英語 → 日本語の意味 → 英語(もう一度)」の順で読む(シス単のCDと同じ流れ)。
struct StudyWordPlayerView: View {
    let words: [StudyStore.StudyWord]
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = StudyWordPlayer.shared
    /// 1語を読み終えてから次へ進むまでの間(秒)。速い/普通/ゆっくり。アプリを閉じても記憶。
    /// 「普通」は本家シス単の実測(単語間 約1.2秒)に合わせている
    @AppStorage("studyWordGap") private var gap = 1.2

    // 英→和→英の3回読むので、ここでは語と語の間だけを持たせる(語の中の間はエンジン側で固定)
    private let gaps: [(String, Double)] = [("速い", 0.7), ("普通", 1.2), ("ゆっくり", 2.2)]

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

            // 速度(語間の休み)
            HStack(spacing: 8) {
                ForEach(gaps, id: \.1) { label, value in
                    Button {
                        gap = value
                        player.gap = value
                    } label: {
                        Text(label)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(gap == value ? Color.accentColor : Color(.secondarySystemBackground)))
                            .foregroundStyle(gap == value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // 前 / 再生・一時停止 / 次
            HStack(spacing: 24) {
                Button { player.prev() } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title).frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            player.gap = gap
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
