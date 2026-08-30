import SwiftUI

/// 熟語を音声で流す画面。1熟語ごとに「和訳 → 英文」の順で読み、今の熟語をハイライトして自動送り。
struct IdiomPlayerView: View {
    let items: [IdiomPlayer.Item]
    let startAt: Int
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var player = IdiomPlayer.shared
    /// 再生倍率(1.0=標準)。アプリを閉じても記憶
    @AppStorage("idiomSpeed") private var speed = 1.0
    /// 最後まで来たら先頭へ戻って繰り返す
    @AppStorage("idiomLoop") private var loop = false
    private let speeds: [Double] = [0.75, 1.0, 1.5, 2.0]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("\(min(player.index + 1, items.count)) / \(items.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button {
                    player.stopAll(); dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal).padding(.top, 20)

            // 熟語リスト(現在をハイライト・自動スクロール)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                            row(it, current: i == player.index)
                                .id(i)
                                .onTapGesture { player.jump(to: i) }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                .onChange(of: player.index) { _, i in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(i, anchor: .center) }
                }
            }

            // 倍率
            HStack(spacing: 6) {
                ForEach(speeds, id: \.self) { v in
                    Button {
                        speed = v; player.speed = v
                    } label: {
                        Text(String(format: "%g倍", v))
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(speed == v ? Color.accentColor : Color(.secondarySystemBackground)))
                            .foregroundStyle(speed == v ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // 前 / 再生・一時停止 / 次 / リピート
            HStack(spacing: 20) {
                Button { player.prev() } label: { Image(systemName: "backward.fill").font(.title2) }
                    .buttonStyle(.bordered)
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.title).frame(minWidth: 56)
                }
                .buttonStyle(.borderedProminent)
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.title2) }
                    .buttonStyle(.bordered)
                Button {
                    loop.toggle(); player.loop = loop
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
            // ミニプレイヤーから開き直した時は続きから。初回だけ最初から再生
            if !player.sessionActive {
                player.configure(items: items, startAt: startAt)
                if !items.isEmpty { player.play() }
            }
        }
    }

    @ViewBuilder
    private func row(_ it: IdiomPlayer.Item, current: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(it.phrase).font(current ? .title3.bold() : .body.weight(.semibold))
                    .foregroundStyle(current ? Color.white : Color.primary)
                Spacer(minLength: 6)
                Text(it.meaning).font(.subheadline)
                    .foregroundStyle(current ? Color.white.opacity(0.9) : Color.secondary)
                    .lineLimit(1)
            }
            Text(it.en).font(.subheadline)
                .foregroundStyle(current ? Color.white : Color.primary.opacity(0.9))
            if !it.ja.isEmpty {
                Text(it.ja).font(.footnote)
                    .foregroundStyle(current ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, current ? 12 : 9)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(current ? Color.accentColor : Color(.secondarySystemBackground)))
        .opacity(current ? 1 : 0.9)
    }
}
