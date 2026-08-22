import AVFoundation
import SwiftUI

/// 覚える単語リストをシス単風に再生する画面。
/// 単語+意味を並べ、今の単語をハイライトして自動送り。
/// 各単語は「英語(Google発音・オフライン可)→ 日本語の意味」の順で読む。
struct StudyWordPlayerView: View {
    let words: [StudyStore.StudyWord]
    @Environment(\.dismiss) private var dismiss

    @State private var index = 0
    @State private var isPlaying = true
    @State private var timer: Timer?
    /// 1単語あたりの間隔(秒)。速い/普通/ゆっくり
    @AppStorage("studyWordInterval") private var interval = 2.5

    // 英語+日本語の2つを読むので、間隔は少し長めにする
    private let intervals: [(String, Double)] = [("速い", 2.8), ("普通", 3.8), ("ゆっくり", 5.0)]
    /// 日本語の意味読み上げ用
    private let jaSynth = AVSpeechSynthesizer()

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
        let item = words[index]
        // シス単風: まず英語、少し置いて日本語の意味
        GoogleTTS.shared.speak(item.word) { SpeechSynthesisService.shared.speak(item.word) }
        let meaning = item.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaning.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard isPlaying || true else { return }  // 手動送りでも意味は読む
            let u = AVSpeechUtterance(string: meaning)
            u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            jaSynth.stopSpeaking(at: .immediate)
            jaSynth.speak(u)
        }
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
