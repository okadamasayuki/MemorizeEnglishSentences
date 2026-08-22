import AVFoundation
import Combine

/// 覚える単語リストを「シス単風」に読み上げる再生エンジン。
/// 1語ごとに 英単語 → 日本語の意味 → 英単語(もう一度) の順で読み、
/// 読み終わったら少し間をおいて次の語へ進む(シス単のCDと同じ流れ)。
///
/// View(構造体)だと再生完了のデリゲートを受けられず連鎖が途切れるため、
/// 参照型のエンジンに切り出している。曲送り/一時停止は token で古い連鎖を無効化する。
final class StudyWordPlayer: NSObject, ObservableObject {
    /// 画面を閉じても再生を続けられるよう共有インスタンスにする(ミニプレイヤー対応)
    static let shared = StudyWordPlayer()

    @Published var index = 0
    @Published var isPlaying = false
    /// 再生セッションが生きているか(一時停止中も true)。ミニプレイヤーの表示判定に使う
    @Published var sessionActive = false

    private(set) var words: [StudyStore.StudyWord] = []
    /// 英語②(2回目)を読み終えてから次の語へ進むまでの間(秒)。速度切り替えで変える。
    /// 本家シス単の実測(単語間 約1.2秒)を「普通」に採用
    var gap: Double = 1.2

    // 本家シス単の音声を実測して合わせた、語の中の間(秒)
    /// 英語① → 日本語の意味 の間
    private let gapEnToJa = 0.65
    /// 日本語の意味 → 英語②(もう一度) の間
    private let gapJaToEn = 0.55

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
        AudioSequencePlayer.shared.stop()
        SpeechSynthesisService.shared.stop()
        sessionActive = true
        isPlaying = true
        speakCurrent()
    }

    /// いま読んでいる単語(ミニプレイヤーの表示用)
    var currentWord: String { words.indices.contains(index) ? words[index].word : "" }
    var currentMeaning: String { words.indices.contains(index) ? words[index].meaning : "" }

    func pause() {
        isPlaying = false
        cancelChain()
    }

    func toggle() { isPlaying ? pause() : play() }

    /// 指定の語へ移動して読み直す(タップ・前へ・次へ)
    func jump(to i: Int) {
        AudioSequencePlayer.shared.stop()
        SpeechSynthesisService.shared.stop()
        sessionActive = true
        cancelChain()
        index = min(max(0, i), max(0, words.count - 1))
        speakCurrent()
    }

    func next() { jump(to: min(words.count - 1, index + 1)) }
    func prev() { jump(to: max(0, index - 1)) }

    func stopAll() {
        isPlaying = false
        sessionActive = false
        cancelChain()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + gapEnToJa) { [weak self] in
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
        DispatchQueue.main.asyncAfter(deadline: .now() + gapJaToEn) { [weak self] in
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
