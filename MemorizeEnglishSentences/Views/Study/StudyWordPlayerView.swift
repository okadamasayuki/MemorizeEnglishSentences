import SwiftUI

/// 覚える単語リストをシス単風に再生する画面。
/// 単語+意味を並べ、今の単語をハイライトして自動送り。各単語はGoogle発音(オフライン可)で読む。
struct StudyWordPlayerView: View {
    let words: [StudyStore.StudyWord]
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var isPlaying = true
    @State private var timer: Timer?
    /// 1単語あたりの間隔(秒)。速い/普通/ゆっくり
    @AppStorage("studyWordInterval") private var interval = 2.5

    private let intervals: [(String, Double)] = [("速い", 1.8), ("普通", 2.5), ("ゆっくり", 3.5)]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(min(index + 1, words.count)) / \(words.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    stop()
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
                            row(w, current: i == index)
                                .id(i)
                                .onTapGesture { jump(to: i) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: index) { _, i in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(i, anchor: .center) }
                }
            }

            // 速度
            HStack(spacing: 8) {
                ForEach(intervals, id: \.1) { label, value in
                    Button {
                        interval = value
                        if isPlaying { restartTimer() }
                    } label: {
                        Text(label)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .fill(interval == value ? Color.accentColor : Color(.secondarySystemBackground)))
                            .foregroundStyle(interval == value ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // 前 / 再生・一時停止 / 次
            HStack(spacing: 24) {
                Button { jump(to: max(0, index - 1)) } label: {
                    Image(systemName: "backward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
                Button {
                    if isPlaying { pause() } else { play() }
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title).frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                Button { jump(to: min(words.count - 1, index + 1)) } label: {
                    Image(systemName: "forward.fill").font(.title2)
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 20)
        }
        .onAppear { if !words.isEmpty { play() } }
        .onDisappear { stop() }
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

    // MARK: - 再生制御

    private func play() {
        guard !words.isEmpty else { return }
        isPlaying = true
        speakCurrent()
        restartTimer()
    }
    private func pause() {
        isPlaying = false
        timer?.invalidate(); timer = nil
    }
    private func stop() {
        timer?.invalidate(); timer = nil
        isPlaying = false
    }
    private func jump(to i: Int) {
        index = min(max(0, i), words.count - 1)
        speakCurrent()
        if isPlaying { restartTimer() }
    }
    private func speakCurrent() {
        guard words.indices.contains(index) else { return }
        let w = words[index].word
        GoogleTTS.shared.speak(w) { SpeechSynthesisService.shared.speak(w) }
    }
    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            if index + 1 < words.count {
                index += 1
                speakCurrent()
            } else {
                pause()  // 最後まで来たら止まる
            }
        }
    }
}
