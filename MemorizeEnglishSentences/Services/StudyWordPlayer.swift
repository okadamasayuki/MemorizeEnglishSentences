import AVFoundation
import Combine

/// 覚える単語リストを「シス単風」に読み上げる再生エンジン。
/// 1語ごとに 英単語 → 日本語の意味 → 英単語(もう一度) の順で読み、
/// 読み終わったら少し間をおいて次の語へ進む(シス単のCDと同じ流れ)。
///
/// View(構造体)だと再生完了のデリゲートを受けられず連鎖が途切れるため、
/// 参照型のエンジンに切り出している。曲送り/一時停止は token で古い連鎖を無効化する。
final class StudyWordPlayer: NSObject, ObservableObject {
    /// いま開いている単語プレイヤー。音読側が再生を始めるとき、これを止めて二重再生を防ぐ
    static weak var active: StudyWordPlayer?

    @Published var index = 0
    @Published var isPlaying = false

    private(set) var words: [StudyStore.StudyWord] = []
    /// 1語を読み終えてから次の語へ進むまでの間(秒)。速度切り替えで変える
    var gap: Double = 1.0

    private let jaSynth = AVSpeechSynthesizer()
    /// 進行中の連鎖の世代。曲送り/一時停止のたびに増やして古い連鎖を捨てる
    private var token = 0
    /// 日本語の読み上げが終わったら呼ぶ続き(英語2回目へ)
    private var afterJa: (() -> Void)?
    private var advanceWork: DispatchWorkItem?

    override init() {
        super.init()
        jaSynth.delegate = self
    }

    func configure(words: [StudyStore.StudyWord]) {
        self.words = words
        if index >= words.count { index = 0 }
    }

    // MARK: - 操作

    func play() {
        guard !words.isEmpty else { return }
        // 音読タブの音声と二重に鳴らさない(片方が鳴ったらもう片方は止める)
        Self.active = self
        AudioSequencePlayer.shared.stop()
        SpeechSynthesisService.shared.stop()
        isPlaying = true
        speakCurrent()
    }

    func pause() {
        isPlaying = false
        cancelChain()
    }

    func toggle() { isPlaying ? pause() : play() }

    /// 指定の語へ移動して読み直す(タップ・前へ・次へ)
    func jump(to i: Int) {
        Self.active = self
        AudioSequencePlayer.shared.stop()
        SpeechSynthesisService.shared.stop()
        cancelChain()
        index = min(max(0, i), max(0, words.count - 1))
        speakCurrent()
    }

    func next() { jump(to: min(words.count - 1, index + 1)) }
    func prev() { jump(to: max(0, index - 1)) }

    func stopAll() {
        isPlaying = false
        cancelChain()
        if Self.active === self { Self.active = nil }
    }

    // MARK: - 連鎖(英→和→英→次へ)

    private func cancelChain() {
        token &+= 1
        afterJa = nil
        advanceWork?.cancel()
        advanceWork = nil
        jaSynth.stopSpeaking(at: .immediate)
        GoogleTTS.shared.stop()
    }

    private func speakCurrent() {
        guard words.indices.contains(index) else { return }
        token &+= 1
        let my = token
        let w = words[index]
        // ① 英語
        GoogleTTS.shared.speak(w.word,
                               onFallback: { SpeechSynthesisService.shared.speak(w.word) },
                               onFinished: { [weak self] in self?.step2Ja(my, w) })
    }

    private func step2Ja(_ my: Int, _ w: StudyStore.StudyWord) {
        guard my == token else { return }
        let meaning = w.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaning.isEmpty else { step3En(my, w); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, my == self.token else { return }
            let u = AVSpeechUtterance(string: meaning)
            u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
            // ② 日本語の意味 → 読み終わったら英語2回目へ
            self.afterJa = { [weak self] in self?.step3En(my, w) }
            self.jaSynth.speak(u)
        }
    }

    private func step3En(_ my: Int, _ w: StudyStore.StudyWord) {
        guard my == token else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, my == self.token else { return }
            // ③ 英語(もう一度) → 鳴り終わったら次の語へ
            GoogleTTS.shared.speak(w.word,
                                   onFallback: { SpeechSynthesisService.shared.speak(w.word) },
                                   onFinished: { [weak self] in self?.scheduleAdvance(my) })
        }
    }

    private func scheduleAdvance(_ my: Int) {
        guard my == token, isPlaying else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, my == self.token, self.isPlaying else { return }
            if self.index + 1 < self.words.count {
                self.index += 1
                self.speakCurrent()
            } else {
                self.isPlaying = false  // 最後まで来たら止まる
            }
        }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gap, execute: work)
    }
}

extension StudyWordPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = afterJa
        afterJa = nil
        cb?()
    }
}
