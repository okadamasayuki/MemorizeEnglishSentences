import AVFoundation
import Combine

/// 熟語タブの音声プレイヤー。1熟語ごとに「和訳(VOICEVOX)→ 英文(edge-tts)」の順で再生し、
/// 読み終わったら少し間をおいて次の熟語へ進む(和訳→英文→和訳→英文…)。
/// 音声ファイルが無い場合は内蔵TTS(和訳=日本語、英文=Google発音)にフォールバックする。
final class IdiomPlayer: NSObject, ObservableObject {
    static let shared = IdiomPlayer()

    struct Item: Identifiable {
        let id: Int          // Idiom.number(級内で一意)
        let phrase: String   // 見出し(熟語)
        let meaning: String  // 熟語の意味
        let en: String       // 例文(英)
        let ja: String       // 例文の和訳
    }

    @Published var index = 0
    @Published var isPlaying = false
    /// 再生セッションが生きているか(一時停止中も true)。ミニプレイヤー等の判定用
    @Published var sessionActive = false

    private(set) var items: [Item] = []
    /// 再生倍率(1.0=標準)。音声の速さと間隔の両方に効く
    var speed: Double = 1.0
    /// 一番下まで来たら先頭に戻って繰り返す
    var loop = false

    // 標準(1倍)のときの間(秒)。倍率で割って使う
    private let baseGapJaToEn = 0.35   // 和訳 → 英文 の間
    private let baseGapBetween = 0.7   // 英文 → 次の熟語 の間
    private var gapJaToEn: Double { baseGapJaToEn / speed }
    private var gapBetween: Double { baseGapBetween / speed }
    private var playRate: Float { Float(speed) }

    private var player: AVAudioPlayer?
    private var onFinish: (() -> Void)?
    private let synth = AVSpeechSynthesizer()
    private var afterSpeech: (() -> Void)?
    private var token = 0
    private var advanceWork: DispatchWorkItem?

    override init() {
        super.init()
        synth.delegate = self
    }

    func configure(items: [Item], startAt: Int = 0) {
        self.items = items
        index = min(max(0, startAt), max(0, items.count - 1))
    }

    var currentItem: Item? { items.indices.contains(index) ? items[index] : nil }

    // MARK: - 操作

    func play() {
        guard !items.isEmpty else { return }
        // 他の音声(音読・暗記・単語学習)と二重に鳴らさない
        AudioSequencePlayer.shared.stop()
        SpeechSynthesisService.shared.stop()
        StudyWordPlayer.shared.stopAll()
        sessionActive = true
        isPlaying = true
        speakCurrent()
    }
    func pause() { isPlaying = false; cancelChain(); AudioSessionHelper.releaseIfIdle() }
    func toggle() { isPlaying ? pause() : play() }
    func jump(to i: Int) {
        cancelChain()
        sessionActive = true
        index = min(max(0, i), max(0, items.count - 1))
        speakCurrent()
    }
    func next() { jump(to: min(items.count - 1, index + 1)) }
    func prev() { jump(to: max(0, index - 1)) }
    func stopAll() {
        isPlaying = false
        sessionActive = false
        cancelChain()
        AudioSessionHelper.releaseIfIdle()
    }

    // MARK: - 連鎖(和訳→英文→次へ)

    private func cancelChain() {
        token &+= 1
        onFinish = nil
        afterSpeech = nil
        advanceWork?.cancel(); advanceWork = nil
        player?.stop(); player = nil
        synth.stopSpeaking(at: .immediate)
    }

    private func setupSession() {
        if !SpeechRecognitionService.isAnyRecording {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    /// 音声ファイルを鳴らす。鳴らせたら true。終わったら then を呼ぶ
    private func playFile(_ url: URL, then: @escaping () -> Void) -> Bool {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        setupSession()
        p.delegate = self
        if playRate != 1.0 { p.enableRate = true; p.rate = playRate }
        onFinish = then
        player = p
        p.play()
        return true
    }

    /// 内蔵TTSで読む(ファイルが無い時のフォールバック)。終わったら then を呼ぶ
    private func speakTTS(_ text: String, lang: String, then: @escaping () -> Void) {
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: lang)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * min(1.0, playRate)
        afterSpeech = then
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    private func speakCurrent() {
        guard items.indices.contains(index) else { return }
        token &+= 1
        let my = token
        let it = items[index]
        // ① 和訳(VOICEVOX)。無ければ内蔵の日本語TTS
        if let u = IdiomAudioStore.jaURL(it.ja),
           playFile(u, then: { [weak self] in self?.step2En(my, it) }) {
        } else {
            speakTTS(it.ja, lang: "ja-JP", then: { [weak self] in self?.step2En(my, it) })
        }
    }

    private func step2En(_ my: Int, _ it: Item) {
        guard my == token else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + gapJaToEn) { [weak self] in
            guard let self, my == self.token else { return }
            // ② 英文(edge-tts)。無ければGoogle発音→内蔵英語TTS
            if let u = IdiomAudioStore.enURL(it.en),
               self.playFile(u, then: { [weak self] in self?.scheduleAdvance(my) }) {
            } else {
                GoogleTTS.shared.speak(it.en,
                    onFallback: { self.speakTTS(it.en, lang: "en-US", then: { [weak self] in self?.scheduleAdvance(my) }) },
                    onFinished: { [weak self] in self?.scheduleAdvance(my) })
            }
        }
    }

    private func scheduleAdvance(_ my: Int) {
        guard my == token, isPlaying else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, my == self.token, self.isPlaying else { return }
            if self.index + 1 < self.items.count {
                self.index += 1
                self.speakCurrent()
            } else if self.loop {
                self.index = 0
                self.speakCurrent()
            } else {
                self.isPlaying = false
            }
        }
        advanceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + gapBetween, execute: work)
    }
}

extension IdiomPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let cb = onFinish; onFinish = nil; cb?()
    }
}

extension IdiomPlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let cb = afterSpeech; afterSpeech = nil; cb?()
    }
}
