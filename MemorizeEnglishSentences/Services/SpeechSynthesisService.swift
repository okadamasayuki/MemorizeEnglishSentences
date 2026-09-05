import AVFoundation
import Foundation

/// AVSpeechSynthesizer wrapper。
/// synthesizer はシングルトンで長寿命保持(ローカル変数だと解放されて無音になる)。
/// ブロック読み上げ中は、いま読んでいる文字範囲を公開して単語ハイライトに使う。
/// 連続再生で「今読んでいる単語の範囲」だけを持つ軽い監視オブジェクト。
/// 単語ごとに高頻度で更新されるので、本体(ボタン等)と分離して再描画の巻き添えを防ぐ。
final class SequenceHighlight: ObservableObject {
    @Published var range: NSRange?
}

final class SpeechSynthesisService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechSynthesisService()

    /// 連続再生のハイライト(単語範囲)。本体とは別に監視させる
    let sequenceHighlight = SequenceHighlight()

    private let synthesizer = AVSpeechSynthesizer()

    /// 複数英文の連続再生中か(暗記タブの連続リスニング用)
    @Published var isPlayingSequence = false
    /// 連続再生を一時停止中か
    @Published var isPaused = false
    /// 各英文を2回ずつ読む(オンなら同じ英文を続けてもう一度読んでから次へ)
    @Published var repeatSentence = false
    /// 今の英文をこれまで繰り返した回数(0=まだ1回目)
    private var currentRepeatDone = 0
    /// 連続再生で今読んでいる英文の番号(0始まり。未再生は nil)
    @Published var sequenceIndex: Int?
    /// 連続再生で今読んでいる英文(全文)
    @Published var currentText: String?
    /// 連続再生する全英文
    private var sequenceTexts: [String] = []
    /// 今読んでいる英文の番号(0始まり)
    private var currentIndex = 0
    /// 今読み上げ中の utterance(自然終了=次へ進む判定に使う。これ以外のコールバックは無視)
    private var currentUtterance: AVSpeechUtterance?
    /// 再生世代。停止/スキップ/速度変更のたびに +1 して、古い遅延処理・コールバックを無効化する
    private var playGeneration = 0
    /// 連続再生の読み上げ速度(0=最遅 〜 1=最速。既定は標準速度)
    private var sequenceRate: Float = AVSpeechUtteranceDefaultSpeechRate
    /// 連続再生で使うボイスの識別子(nil なら既定の englishVoice)
    private var sequenceVoiceID: String?

    /// 連続再生で使うボイス(選択があればそれ、無ければ既定の Samantha 系)。
    /// Siri 専用ボイスなど AVSpeechSynthesizer で鳴らせないものは無視して既定にする。
    private var sequenceVoice: AVSpeechSynthesisVoice? {
        if let id = sequenceVoiceID, let voice = AVSpeechSynthesisVoice(identifier: id),
           !Self.isUnusableVoice(voice) {
            return voice
        }
        return englishVoice
    }

    /// AVSpeechSynthesizer では鳴らない(=無音になる)ボイスか。
    /// Siri 用ボイス(識別子に "siri"、または Nicky/Aaron)は再生できない。
    static func isUnusableVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        if voice.identifier.localizedCaseInsensitiveContains("siri") { return true }
        return ["Nicky", "Aaron"].contains { voice.name.localizedCaseInsensitiveContains($0) }
    }

    /// 英文読み上げ用に選べる、自然なアメリカ英語ボイスの一覧(表示用データ)。
    /// 抑揚が不自然になりやすいノベルティ/旧式音声は除外し、品質の高い順に並べる。
    static func naturalEnglishVoices() -> [(id: String, name: String, quality: String)] {
        let novelty = ["Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos",
                       "Good News", "Jester", "Organ", "Superstar", "Trinoids", "Whisper",
                       "Wobble", "Zarvox", "Eddy", "Flo", "Grandma", "Grandpa", "Reed",
                       "Rocko", "Sandy", "Shelley", "Junior", "Kathy", "Ralph", "Fred"]
        func qualityLabel(_ q: AVSpeechSynthesisVoiceQuality) -> String {
            switch q {
            case .premium: return "最高品質"
            case .enhanced: return "高品質"
            default: return "標準"
            }
        }
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "en-US" }
            .filter { v in !novelty.contains { v.name.localizedCaseInsensitiveContains($0) } }
            // Siri 専用ボイスは AVSpeechSynthesizer では鳴らないので除外
            .filter { !isUnusableVoice($0) }
            .sorted { a, b in
                rank(a.quality) != rank(b.quality) ? rank(a.quality) > rank(b.quality) : a.name < b.name
            }
            .map { (id: $0.identifier, name: $0.name, quality: qualityLabel($0.quality)) }
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 英語は自然な抑揚のアメリカ英語(en-US)ボイスを使う。
    /// 「最高品質を選ぶ」だと抑揚に癖のあるボイスが選ばれて文章の読み上げが不自然になるため、
    /// 定番で自然な "Samantha" を優先し(あれば高品質版)、無ければ端末既定の en-US にする。
    private lazy var englishVoice: AVSpeechSynthesisVoice? = {
        let enUS = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        let samantha = enUS.filter { $0.name.localizedCaseInsensitiveContains("Samantha") }
        if let best = samantha.max(by: { rank($0) < rank($1) }) {
            return best
        }
        // Samantha が無い端末は既定の en-US(自然な抑揚)にフォールバック
        return AVSpeechSynthesisVoice(language: "en-US") ?? enUS.first
    }()

    /// 単語などの単発読み上げ(ハイライトなし)
    func speak(_ text: String, slow: Bool = false) {
        stop()
        startUtterance(text, slow: slow)
    }

    /// 複数の英文を、1文ずつ(アメリカ英語で)順番に連続再生する。
    /// 1文ずつ再生し、自然終了(didFinish)で次へ進める。スキップ・停止時の古い
    /// コールバックは currentUtterance の同一性と playGeneration で無効化する。
    func speakSequence(_ texts: [String], speed: Double = 1.0, voiceID: String? = nil, startAt: Int = 0) {
        stop()
        let items = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return }
        AudioSequencePlayer.shared.stop()  // 教材音声と同時再生しない
        activatePlaybackSession()
        sequenceTexts = items
        sequenceRate = rate(forSpeed: speed)
        sequenceVoiceID = voiceID
        currentIndex = min(max(0, startAt), items.count - 1)
        currentRepeatDone = 0
        isPlayingSequence = true
        // stop() 直後は speak を受け付けないことがあるので少し待ってから鳴らす
        startCurrent(delay: 0.12)
    }

    /// 次の英文へ移動する(最後まで行ったら終了)
    func skipToNext() {
        guard isPlayingSequence else { return }
        if currentIndex + 1 < sequenceTexts.count {
            currentIndex += 1
            restartCurrent()
        } else {
            stop()
        }
    }

    /// 前の英文へ移動する(先頭より前には行かない)
    func skipToPrevious() {
        guard isPlayingSequence else { return }
        currentIndex = max(0, currentIndex - 1)
        restartCurrent()
    }

    /// 速度倍率(1.0=標準)を AVSpeechUtterance の rate に変換する
    private func rate(forSpeed speed: Double) -> Float {
        let r = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        return min(max(r, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    /// 連続再生の速度を変える。再生中なら今の英文の頭から新しい速度で読み直す。
    /// 一時停止中は値の保存だけ行い、再開時に反映する(勝手に再生を再開しない)。
    func setSequenceSpeed(_ speed: Double) {
        sequenceRate = rate(forSpeed: speed)
        guard isPlayingSequence, !isPaused else { return }
        restartCurrent()
    }

    /// 連続再生のボイスを変える。再生中なら今の英文の頭から新しいボイスで読み直す。
    /// 一時停止中は値の保存だけ行い、再開時に反映する(勝手に再生を再開しない)。
    func setSequenceVoice(_ voiceID: String?) {
        sequenceVoiceID = voiceID
        guard isPlayingSequence, !isPaused else { return }
        restartCurrent()
    }

    /// 今の英文(currentIndex)を頭から再生する。delay 秒後に鳴らす(stop 直後対策)。
    /// 表示(番号・本文)は即反映し、古い世代の遅延処理は playGeneration で弾く。
    private func startCurrent(delay: Double) {
        guard isPlayingSequence, sequenceTexts.indices.contains(currentIndex) else {
            stop()
            return
        }
        playGeneration += 1
        let gen = playGeneration
        let idx = currentIndex
        isPaused = false
        sequenceIndex = idx
        currentText = sequenceTexts[idx]
        sequenceHighlight.range = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isPlayingSequence, self.playGeneration == gen,
                  self.sequenceTexts.indices.contains(idx) else { return }
            let utterance = AVSpeechUtterance(string: self.sequenceTexts[idx])
            utterance.voice = self.sequenceVoice
            utterance.rate = self.sequenceRate
            utterance.volume = 1.0
            self.currentUtterance = utterance
            self.synthesizer.speak(utterance)
        }
    }

    /// スキップ・速度/声変更で、今の英文を止めて頭から鳴らし直す。
    private func restartCurrent() {
        guard isPlayingSequence else { return }
        currentUtterance = nil          // 古い utterance のコールバックを無効化
        playGeneration += 1             // 古い遅延処理も無効化
        currentRepeatDone = 0           // 繰り返し回数もリセット(頭から)
        isPaused = false
        synthesizer.stopSpeaking(at: .immediate)
        startCurrent(delay: 0.12)
    }

    /// 連続再生を一時停止する。プレミアム音声だと pause/continue の反応が重いので、
    /// 確実に即時停止する stopSpeaking を使い、位置(currentIndex)は保持しておく。
    func pauseSequence() {
        guard isPlayingSequence, !isPaused else { return }
        currentUtterance = nil   // 古いコールバックを無効化(次へ進めない)
        playGeneration += 1      // 予約済みの遅延再生も無効化
        synthesizer.stopSpeaking(at: .immediate) // 確実に即・無音
        isPaused = true
    }

    /// 一時停止した連続再生を再開する(今の英文の頭から)
    func resumeSequence() {
        guard isPlayingSequence, isPaused else { return }
        startCurrent(delay: 0)
    }

    func stop() {
        playGeneration += 1     // 予約済みの遅延再生を無効化
        // 実際に喋っていた/連続再生中だった時だけセッションを手放す。
        // (他プレイヤーが開始時に空振りで呼ぶ場合に、直後の有効化と競合させない)
        let wasActive = synthesizer.isSpeaking || synthesizer.isPaused || isPlayingSequence
        currentUtterance = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlayingSequence = false
        isPaused = false
        sequenceIndex = nil
        currentText = nil
        sequenceHighlight.range = nil
        sequenceTexts = []
        currentIndex = 0
        sequenceVoiceID = nil
        if wasActive { AudioSessionHelper.releaseIfIdle() }
    }

    /// 再生用にオーディオセッションを整える(録音中は触らない)
    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        if !SpeechRecognitionService.isAnyRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])
    }

    private func startUtterance(_ text: String, slow: Bool) {
        // 実際に録音中のときだけ playAndRecord のまま触らない(切り替えると無音になる)。
        // 録音していなければ、たとえ録音用の設定が残っていても
        // 再生専用に切り替えてフル音量のスピーカーで鳴らす。
        activatePlaybackSession()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = englishVoice
        utterance.rate = slow ? 0.3 : AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        DispatchQueue.main.async {
            // 連続再生中は本体と分離したハイライト用オブジェクトを更新して、
            // 単語ごとの再描画でボタン等が巻き添えにならないようにする
            guard self.isPlayingSequence, utterance === self.currentUtterance else { return }
            self.sequenceHighlight.range = characterRange
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            // 連続再生: いま鳴っていた英文が自然に終わったら次へ進む(または同じ英文を繰り返す)。
            // スキップ/停止でキャンセルされた古い utterance はここには来ない(didCancel 側)。
            guard self.isPlayingSequence, utterance === self.currentUtterance else { return }
            self.currentUtterance = nil
            // 「各文2回」がオンで、まだ1回しか読んでいなければ同じ英文をもう一度
            if self.repeatSentence, self.currentRepeatDone < 1 {
                self.currentRepeatDone += 1
                self.startCurrent(delay: 0.3)
                return
            }
            self.currentRepeatDone = 0
            if self.currentIndex + 1 < self.sequenceTexts.count {
                self.currentIndex += 1
                self.startCurrent(delay: 0.3) // 文と文の間に少し間を置く
            } else {
                self.stop()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // 連続再生のスキップ/停止によるキャンセルは無視(次の再生は startCurrent が担う)
    }
}
