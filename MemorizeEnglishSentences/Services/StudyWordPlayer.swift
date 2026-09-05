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
    /// 再生倍率(1.0=標準。0.75=ゆっくり、2.0/3.0=速い)。音声の再生速度と間隔の両方に効く
    var speed: Double = 1.0
    /// 一番下まで来たら先頭に戻って繰り返すか(リピート)
    var loop: Bool = false

    // 本家シス単の音声を実測して合わせた、標準(1倍)のときの間(秒)。倍率で割って使う
    /// 英語① → 日本語の意味 の間
    private let baseGapEnToJa = 0.65
    /// 日本語の意味 → 英語②(もう一度) の間
    private let baseGapJaToEn = 0.55
    /// 英語②(2回目) → 次の単語 の間(実測 約1.2秒)
    private let baseGapBetween = 1.2

    // 倍率を反映した実際の間・再生レート
    private var gapEnToJa: Double { baseGapEnToJa / speed }
    private var gapJaToEn: Double { baseGapJaToEn / speed }
    private var gapBetween: Double { baseGapBetween / speed }
    private var playRate: Float { Float(speed) }

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
        let wasActive = isPlaying || sessionActive
        isPlaying = false
        cancelChain()
        if wasActive { AudioSessionHelper.releaseIfIdle() }
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
        let wasActive = isPlaying || sessionActive
        isPlaying = false
        sessionActive = false
        cancelChain()
        if wasActive { AudioSessionHelper.releaseIfIdle() }
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
        GoogleTTS.shared.speak(w.word, rate: playRate,
                               onFallback: { SpeechSynthesisService.shared.speak(w.word) },
                               onFinished: { [weak self] in self?.step2Ja(my, w) })
    }

    private func step2Ja(_ my: Int, _ w: StudyStore.StudyWord) {
        guard my == token else { return }
        let meaning = w.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meaning.isEmpty else { step3En(my, w); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + gapEnToJa) { [weak self] in
            guard let self, my == self.token else { return }
            // ② 日本語の意味 → Googleの音声(翻訳と同じ声)で読む。取れなければ内蔵読み上げ。
            //    読み終わったら英語2回目へ
            GoogleTTS.shared.speak(meaning, lang: "ja", rate: self.playRate,
                                   onFallback: { self.speakJaFallback(meaning) },
                                   onFinished: { [weak self] in self?.step3En(my, w) })
        }
    }

    /// Googleの日本語音声が取れないとき(オフライン等)の内蔵読み上げフォールバック
    private func speakJaFallback(_ meaning: String) {
        let u = AVSpeechUtterance(string: meaning)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        jaSynth.stopSpeaking(at: .immediate)
        jaSynth.speak(u)
    }

    private func step3En(_ my: Int, _ w: StudyStore.StudyWord) {
        guard my == token else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + gapJaToEn) { [weak self] in
            guard let self, my == self.token else { return }
            // ③ 英語(もう一度) → 鳴り終わったら次の語へ
            GoogleTTS.shared.speak(w.word, rate: self.playRate,
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
            } else if self.loop {
                self.index = 0            // 一番下まで来たら先頭に戻って続ける(ループ)
                self.speakCurrent()
            } else {
                self.isPlaying = false    // 最後まで来たら止まる
            }
        }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gapBetween, execute: work)
    }
}

extension StudyWordPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = afterJa
        afterJa = nil
        cb?()
    }
}
