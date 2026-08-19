import AVFoundation
import CryptoKit
import Foundation

/// ブロック内の1文分(英文とその和訳、ブロック全文の中での位置と音声内の開始時刻)
struct AudioSegment {
    let en: String
    let ja: String
    /// ブロック全文(english)の中でのこの文のNSRange(単語ハイライトの座標変換に使う)
    let range: NSRange
    /// この文の最初の単語が鳴る時刻(秒)。文単位の区間再生に使う
    let start: Double
}

/// 連続再生する1ブロック分(英文+和訳+教材音声+単語タイミング)
struct AudioPlaybackItem {
    let english: String
    let japanese: String
    let url: URL
    let words: [AudioWordTiming]
    /// 文ごとの英↔和ペア(あれば「英文1文→和訳→…」の交互表示と文単位の区間再生に使う)
    let segments: [AudioSegment]?
    /// 文ごとの再生回数(segments と同数。0=その文はスキップ)
    var repeatCounts: [Int]
    /// 音声内の無音区間(音量解析による)。文の「話し終わり」の正確な検出に使う
    let silences: [(start: Double, end: Double)]
    /// ブロック全体(文ごとの回数設定を1周)を何回再生するか
    var blockRepeat: Int = 1

    /// 文ペア(en/ja)をブロック全文の中に順に探し、座標と音声内開始時刻付きのセグメントにする。
    /// 1つでも見つからなければ nil(全文+全訳のフォールバック表示になる)。
    static func buildSegments(english: String, pairs: [(en: String, ja: String)],
                              words: [AudioWordTiming]) -> [AudioSegment]? {
        let ns = english as NSString
        var searchLocation = 0
        var out: [AudioSegment] = []
        for pair in pairs {
            let sentence = pair.en.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { continue }
            let searchRange = NSRange(location: searchLocation, length: ns.length - searchLocation)
            let r = ns.range(of: sentence, options: [], range: searchRange)
            guard r.location != NSNotFound else { return nil }
            let firstWord = words.first {
                $0.range.location >= r.location && $0.range.location < r.location + r.length
            }
            out.append(AudioSegment(en: sentence, ja: pair.ja, range: r, start: firstWord?.start ?? 0))
            searchLocation = r.location + r.length
        }
        return out.isEmpty ? nil : out
    }
}

/// 文ごとの再生回数設定の永続保存(ブロック英文ハッシュ → [回数])。
/// 次回の再生でも同じ設定(×2で繰り返す・×0で飛ばす等)が使われる。
enum SentenceRepeatStore {
    private static let defaultsKey = "sentenceRepeatCounts"

    private static func key(forBlockText text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// このブロックの文ごとの回数(未設定の文は1回)
    static func counts(forBlockText text: String, sentenceCount: Int) -> [Int] {
        let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [Int]] ?? [:]
        var counts = dict[key(forBlockText: text)] ?? []
        if counts.count < sentenceCount {
            counts += Array(repeating: 1, count: sentenceCount - counts.count)
        }
        return Array(counts.prefix(sentenceCount))
    }

    static func set(_ counts: [Int], forBlockText text: String) {
        var dict = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: [Int]] ?? [:]
        dict[key(forBlockText: text)] = counts
        UserDefaults.standard.set(dict, forKey: defaultsKey)
    }

    // MARK: ブロック全体の繰り返し回数(1周=文ごとの回数設定を消化)。
    // 項目ごとではなく全項目共通の設定(1か所で変えると全部に効く)

    private static let blockGlobalKey = "blockRepeatGlobal"

    static var globalBlockCount: Int {
        get { max(1, UserDefaults.standard.integer(forKey: blockGlobalKey)) }
        set { UserDefaults.standard.set(newValue, forKey: blockGlobalKey) }
    }

    /// 回数設定を全て既定(×1)へ戻す一度きりの掃除。
    /// ×3廃止・×1↔×2トグル化(2026-08-18の要望)に合わせて、
    /// それまでにちょこちょこ変えた保存値をリセットする。
    static func resetAllToOneIfNeeded() {
        let doneKey = "didResetRepeatsToOne_v1"
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        globalBlockCount = 1
        UserDefaults.standard.set(true, forKey: doneKey)
    }
}

/// 再生進捗(現在位置と合計時間)。高頻度更新なので本体と分離して監視させる。
/// 合計時間は文ごとの回数設定(×2で2倍など)を織り込んだ「実際に鳴る長さ」。
final class PlaybackProgress: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
}

/// 教材音声(MP3)の連続再生プレイヤー。
/// ブロック内は「文ごとの区間」を単位に再生し、文ごとの回数設定(×0〜×3)に従って
/// 繰り返し・スキップする。再生位置に合わせて「今読んでいる単語」のハイライトを公開する。
final class AudioSequencePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioSequencePlayer()

    /// 今読んでいる単語のハイライト(高頻度更新なので本体と分離)
    let highlight = SequenceHighlight()
    /// 現在ブロックの再生進捗(回数設定を織り込んだ位置/合計)
    let progress = PlaybackProgress()

    @Published var isPlayingSequence = false
    @Published var isPaused = false
    /// 今読んでいるブロックの番号(0始まり)
    @Published var sequenceIndex: Int?
    /// 今読んでいる文(ミニプレイヤーの表示用。文の切り替わり時だけ更新)
    @Published var currentSentence: String?
    /// 今読んでいる文の和訳(ミニプレイヤーで和訳読み上げ中に表示する)
    @Published var currentSentenceJa: String?
    /// いま和訳を読み上げ中の文番号(和訳のハイライト表示用。読んでいない時は nil)
    @Published var speakingJaSegment: Int?
    /// いま再生中の文番号(長いブロックの自動スクロール用。文の切り替わり時だけ更新)
    @Published var currentSegmentIndex: Int?

    private var items: [AudioPlaybackItem] = []
    private var currentIndex = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var speed: Double = 1.0
    /// ハイライト検索の前回位置(毎tickの全探索を避ける)
    private var lastWordIndex = -1

    // 文ごと再生スケジュール(現在のブロック)
    /// 各文の再生開始時刻(先頭の文は0=ブロック冒頭から)
    private var segStarts: [Double] = []
    /// 各文の再生回数設定(0=スキップ)
    private var segCounts: [Int] = []
    /// 各文の「話し終わり」時刻(最後の単語の終了+少しの余韻)。繰り返し時はここで切り、
    /// 次の文への息継ぎ・間を再生しない
    private var segSpeechEnds: [Double] = []
    /// 繰り返し再生の開始時刻(最初の単語の少し手前。冒頭の間・息継ぎを飛ばす)
    private var segReplayStarts: [Double] = []
    /// いま再生中の文の番号
    private var curSeg = 0
    /// いまの文を何回読み終えたか
    private var curRep = 0
    /// 再生窓の列(文×回数を展開した仮想タイムライン)
    private struct PlayWindow {
        let pass: Int
        let seg: Int
        let rep: Int
        let start: Double
        let end: Double
        let cumBefore: Double
        /// 和訳読み上げの窓か(スライダーの合計時間に和訳の分も入れるため)
        var isJa: Bool = false
        /// 文頭の和訳(「和訳→英文」順)か
        var jaLead: Bool = false
    }
    private var windows: [PlayWindow] = []
    /// 各文の和訳音声の長さ(和訳モードON時のみ計算。0=和訳なし)
    private var segJaDurations: [Double] = []
    /// 和訳読み上げの開始時刻(TTS時の進捗推定に使う)
    private var jaStartedAt: CFAbsoluteTime = 0
    /// 和訳ファイルの長さのキャッシュ(パス→秒)
    private static var jaDurationCache: [String: Double] = [:]
    /// ブロック全体を何周するか(現在ブロック)
    private var blockRepeatCount = 1
    /// 何周終えたか(0始まり)
    private var blockPassesDone = 0

    /// 各英文の後に、その文の和訳をTTSで読むか(全項目共通の設定)
    private var jaAfterSentence = false
    /// 和訳読み上げ用のTTS(事前生成音声が無い文のフォールバック)
    private let jaSynthesizer = AVSpeechSynthesizer()
    /// 事前生成の和訳音声(VOICEVOX)の再生用
    private var jaPlayer: AVAudioPlayer?
    /// 「和訳→英文」順で、いま文頭の和訳を読み上げ中(読み終えたら英文を流す)
    private var jaLeadPending = false
    /// 一時停止のまま項目を移動した(次の startFile は再生せず一時停止で待つ)
    private var startPaused = false
    /// いま和訳を読み上げ中か(ファイル再生・TTSどちらも)
    private var isSpeakingJa = false
    /// 和訳読み上げ用の日本語ボイス。端末に入っている中で最高品質のものを選ぶ
    /// (既定のコンパクト版Kyokoは機械音声すぎるため。高品質版は
    ///  設定 > アクセシビリティ > 読み上げコンテンツ > 声 からダウンロードできる)
    private lazy var japaneseVoice: AVSpeechSynthesisVoice? = {
        let ja = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "ja-JP" && !SpeechSynthesisService.isUnusableVoice($0)
        }
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        return ja.max(by: { rank($0) < rank($1) }) ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }()

    private override init() {
        super.init()
        jaSynthesizer.delegate = self
    }

    /// 今読んでいるブロック
    var currentItem: AudioPlaybackItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var itemCount: Int { items.count }

    /// 指定ブロックの内容(プレイヤー画面のページ表示用)
    func item(at index: Int) -> AudioPlaybackItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// 指定のブロックへ移動して頭から再生する(ページスワイプ用)
    func jump(to index: Int) {
        guard isPlayingSequence, items.indices.contains(index), index != currentIndex else { return }
        cancelJaSpeech()
        startPaused = isPaused  // 一時停止中の移動は、移動先でも一時停止のまま待つ
        currentIndex = index
        playCurrent()
    }

    /// 連続再生を開始する(startAt番目から)
    func start(items: [AudioPlaybackItem], startAt: Int, speed: Double) {
        stop()
        SpeechSynthesisService.shared.stop()  // TTSと同時再生しない
        guard !items.isEmpty else { return }
        self.items = items
        self.speed = speed
        jaAfterSentence = UserDefaults.standard.bool(forKey: "audioJaAfterSentence")
        currentIndex = min(max(0, startAt), items.count - 1)
        isPlayingSequence = true
        activatePlaybackSession()
        playCurrent()
    }

    /// 「英文→和訳」交互モードの切り替え(再生中でも即反映)。
    /// スライダーの合計時間も和訳の分を含めて作り直す
    func setJaAfterSentence(_ on: Bool) {
        jaAfterSentence = on
        if !on { cancelJaSpeech(resume: true) }
        if isPlayingSequence {
            computeJaDurations()
            rebuildWindows()
        }
    }

    /// 次のブロックへ(最後まで行ったら終了)
    func skipToNext() {
        guard isPlayingSequence else { return }
        cancelJaSpeech()
        startPaused = isPaused
        if currentIndex + 1 < items.count {
            currentIndex += 1
            playCurrent()
        } else {
            stop()
        }
    }

    /// 前のブロックへ(先頭より前には行かない)
    func skipToPrevious() {
        guard isPlayingSequence else { return }
        cancelJaSpeech()
        startPaused = isPaused
        currentIndex = max(0, currentIndex - 1)
        playCurrent()
    }

    /// 再生速度を変える(再生中でも即反映。和訳音声にも効く)
    func setSpeed(_ speed: Double) {
        self.speed = speed
        player?.rate = Float(speed)
        jaPlayer?.rate = Float(speed)
    }

    /// 再生位置を前後に動かす(±5秒スキップ用)。タイムライン全体を移動できるので、
    /// 文の境界を越えて前後の文(繰り返し分を含む)へも移動する。
    func seek(by seconds: Double) {
        guard isPlayingSequence, let player,
              let w = windows.first(where: { !$0.isJa && $0.pass == blockPassesDone && $0.seg == curSeg && $0.rep == curRep }) else { return }
        let pos = w.cumBefore + max(0, min(player.currentTime - w.start, w.end - w.start))
        seekVirtual(to: pos + seconds)
    }

    /// 指定の文の最初から再生し直す(ダブルタップ用)。一時停止中なら再生を再開する
    func playSegment(_ i: Int) {
        guard isPlayingSequence, let player, segStarts.indices.contains(i) else { return }
        cancelJaSpeech()
        isPaused = false
        // 進捗表示をこの文の頭に合わせる
        if let w = windows.first(where: { !$0.isJa && $0.pass == blockPassesDone && $0.seg == i && $0.rep == 0 })
            ?? windows.first(where: { !$0.isJa && $0.seg == i }) {
            blockPassesDone = w.pass
            progress.position = w.cumBefore
        }
        lastWordIndex = -1
        highlight.range = nil
        // 「和訳→英語」順ならダブルタップでもその文の和訳から読む(通常の文送りと同じ経路)
        beginSegment(i)
        if !isSpeakingJa, !player.isPlaying {
            player.play()
            if timer == nil { startTimer() }
        }
    }

    /// スライダーからのシーク。仮想タイムライン上の位置を(文, 回数, 実時間)へ変換して移動する
    func seekVirtual(to value: Double) {
        guard isPlayingSequence, let player, !windows.isEmpty else { return }
        cancelJaSpeech()
        var v = max(0, min(value, progress.duration))
        var w = windows.last { $0.cumBefore <= v } ?? windows[0]
        // 和訳の窓に着地したら、直後の英文の窓へ寄せる(シークで和訳の途中には入らない)
        if w.isJa {
            if let after = windows.first(where: { !$0.isJa && $0.cumBefore >= w.cumBefore }) {
                w = after
            } else if let before = windows.last(where: { !$0.isJa && $0.cumBefore <= w.cumBefore }) {
                w = before
            }
            v = w.cumBefore
        }
        blockPassesDone = w.pass
        curSeg = w.seg
        curRep = w.rep
        publishCurrentSentence()
        player.currentTime = min(w.start + (v - w.cumBefore), max(w.start, w.end - 0.05))
        lastWordIndex = -1
        highlight.range = nil
        progress.position = v
        if !isPaused {
            if !player.isPlaying { player.play() }
            if timer == nil { startTimer() }
        }
    }

    /// 今のブロックの文ごと回数を差し替える(再生中の設定変更用)。
    /// いま読んでいる文が×0にされたら、その文を打ち切って次へ進む。
    func updateCurrentCounts(_ counts: [Int]) {
        guard isPlayingSequence, items.indices.contains(currentIndex) else { return }
        items[currentIndex].repeatCounts = counts
        guard counts.count == segCounts.count else { return }
        segCounts = counts
        rebuildWindows()
        if segCounts.indices.contains(curSeg), segCounts[curSeg] == 0 {
            advanceAfterSegment(force: true)
        }
    }

    /// ブロック全体の繰り返し回数を差し替える(全項目共通。再生中の設定変更用)
    func updateGlobalBlockRepeat(_ count: Int) {
        guard isPlayingSequence else { return }
        for i in items.indices {
            items[i].blockRepeat = count
        }
        blockRepeatCount = max(1, count)
        rebuildWindows()
    }

    /// 一時停止(即・無音。位置は保持)
    func pause() {
        guard isPlayingSequence, !isPaused else { return }
        player?.pause()
        if isSpeakingJa {
            jaPlayer?.pause()
            jaSynthesizer.pauseSpeaking(at: .immediate)
        }
        stopTimer()
        isPaused = true
    }

    /// 再開(止めたところから)
    func resume() {
        guard isPlayingSequence, isPaused else { return }
        isPaused = false
        if isSpeakingJa {
            if let jaPlayer {
                jaPlayer.play()
            } else {
                jaSynthesizer.continueSpeaking()
            }
            return
        }
        if let player {
            player.play()
            startTimer()
        } else {
            playCurrent()
        }
    }

    func stop() {
        cancelJaSpeech()
        player?.stop()
        player = nil
        stopTimer()
        isPlayingSequence = false
        isPaused = false
        sequenceIndex = nil
        currentSentence = nil
        highlight.range = nil
        items = []
        currentIndex = 0
        segStarts = []
        segCounts = []
        segSpeechEnds = []
        segReplayStarts = []
        windows = []
        progress.position = 0
        progress.duration = 0
        blockRepeatCount = 1
        blockPassesDone = 0
        curSeg = 0
        curRep = 0
    }

    // MARK: - 内部

    /// 今のブロックを(文ごとの回数設定に従って)頭から再生する。
    /// 全文が×0のブロックは飛ばして次のブロックへ進む。
    private func playCurrent() {
        player?.stop()
        stopTimer()
        blockPassesDone = 0
        while items.indices.contains(currentIndex) {
            buildSchedule()
            if let first = nextScheduled(from: 0) {
                startFile(atSegment: first)
                return
            }
            currentIndex += 1  // 全文スキップ設定のブロック
        }
        stop()
    }

    /// 現在ブロックの文スケジュール(開始時刻と回数)を組み立てる
    private func buildSchedule() {
        let item = items[currentIndex]
        blockRepeatCount = max(1, item.blockRepeat)
        if let segs = item.segments, !segs.isEmpty, item.repeatCounts.count == segs.count {
            // 先頭の文はブロック冒頭(0秒)から。2文目以降は最初の単語の少し手前から
            segStarts = segs.enumerated().map { i, s in i == 0 ? 0 : max(0, s.start - 0.05) }
            segCounts = item.repeatCounts
            // 「話し終わり」= 次の文の手前にある無音区間の開始+余韻。
            // ただし無音検出が文中の弱い語(文末の小さな声など)を「終わり」と誤認して
            // 最後の単語が切れることがあるため、その文の最終単語の終了時刻より
            // 手前では絶対に切らない(尻切れ防止)。
            segSpeechEnds = segs.indices.map { i in
                let segStart = segs[i].start
                let boundary = i + 1 < segs.count ? segs[i + 1].start : Double.greatestFiniteMagnitude
                // この文の範囲に含まれる最終単語の終了時刻
                let segRange = segs[i].range
                let lastWordEnd = item.words
                    .filter { $0.range.location >= segRange.location
                              && $0.range.location < segRange.location + segRange.length }
                    .map(\.end).max()
                let gap = item.silences.last { $0.start >= segStart && $0.start <= boundary + 0.1 }
                var end: Double
                if let gap {
                    end = gap.start + 0.22
                } else {
                    // 無音が見つからない場合: 次の文の0.35秒前で切る(最後の文は末尾まで)
                    end = boundary == .greatestFiniteMagnitude ? boundary : max(segStart, boundary - 0.35)
                }
                if let lastWordEnd, end < lastWordEnd + 0.22 {
                    end = lastWordEnd + 0.22
                }
                // 次の文の頭にはかぶせない
                if boundary != .greatestFiniteMagnitude {
                    end = min(end, boundary)
                }
                return end
            }
            segReplayStarts = segs.map { max(0, $0.start - 0.05) }
        } else {
            // 文情報が無いブロックは従来どおり全体を1回
            segStarts = [0]
            segCounts = [1]
            segSpeechEnds = [Double.greatestFiniteMagnitude]
            segReplayStarts = [0]
        }
        computeJaDurations()
    }

    /// i番目以降で回数>0の最初の文
    private func nextScheduled(from i: Int) -> Int? {
        (max(0, i)..<segCounts.count).first { segCounts[$0] > 0 }
    }

    /// i番目の文の終了時刻(次の文の開始時刻。最後の文はnil=ファイル末尾まで)
    private func windowEnd(_ i: Int) -> Double? {
        i + 1 < segStarts.count ? segStarts[i + 1] : nil
    }

    /// 音声ファイルを読み込み、指定の文から再生を始める
    private func startFile(atSegment seg: Int) {
        let item = items[currentIndex]
        sequenceIndex = currentIndex
        highlight.range = nil
        lastWordIndex = -1
        guard let newPlayer = try? AVAudioPlayer(contentsOf: item.url) else {
            // 読み込めないファイルはスキップ
            currentIndex += 1
            playCurrent()
            return
        }
        newPlayer.delegate = self
        newPlayer.enableRate = true
        newPlayer.rate = Float(speed)
        newPlayer.prepareToPlay()
        curSeg = seg
        curRep = 0
        publishCurrentSentence()
        newPlayer.currentTime = segStarts[seg]
        player = newPlayer
        isPaused = false
        rebuildWindows()
        progress.position = 0
        if startPaused {
            // 一時停止のまま項目を移動してきた: 頭出しだけして再生は待つ
            startPaused = false
            isPaused = true
            stopTimer()
        } else if jaAfterSentence, jaOrderFirst, let ja = jaText(forSegment: seg), !ja.isEmpty {
            // 「和訳→英文」順のときは、ブロック最初の文も和訳から
            jaLeadPending = true
            speakJa(ja)
            startTimer()  // 和訳中もスライダーを進める
        } else {
            newPlayer.play()
            startTimer()
        }
    }

    /// 各文の和訳音声の長さを求める(和訳モードON時だけ。スライダーの合計時間に使う)
    private func computeJaDurations() {
        segJaDurations = []
        guard jaAfterSentence, items.indices.contains(currentIndex) else { return }
        let item = items[currentIndex]
        segJaDurations = (0..<segCounts.count).map { i in
            guard let ja = jaText(forSegment: i), !ja.isEmpty else { return 0 }
            if let url = JaAudioStore.url(forBlockText: item.english, segmentIndex: i) {
                if let cached = Self.jaDurationCache[url.path] { return cached }
                let d = (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
                Self.jaDurationCache[url.path] = d
                return d
            }
            // TTSフォールバック分は文字数からおおよその長さを見積もる
            return Double(ja.count) * 0.135 + 0.3
        }
    }

    /// 文×回数を展開した再生窓の列と合計時間を作る(回数設定を織り込んだ長さになる)。
    /// 和訳モードON時は和訳読み上げの窓も挟み、スライダーに和訳の時間も加味する
    private func rebuildWindows() {
        windows = []
        guard let player else {
            progress.duration = 0
            return
        }
        let dur = player.duration
        let lastScheduled = (0..<segCounts.count).last { segCounts[$0] > 0 }
        var cum = 0.0
        let jaOn = jaAfterSentence
        let jaLeadMode = jaOrderFirst
        for pass in 0..<blockRepeatCount {
            for i in 0..<segCounts.count where segCounts[i] > 0 {
                let jaDur = (jaOn && segJaDurations.indices.contains(i)) ? segJaDurations[i] : 0
                // 「和訳→英文」順: 文頭に和訳の窓
                if jaDur > 0, jaLeadMode {
                    windows.append(PlayWindow(pass: pass, seg: i, rep: 0, start: 0, end: jaDur,
                                              cumBefore: cum, isJa: true, jaLead: true))
                    cum += jaDur
                }
                for r in 0..<segCounts[i] {
                    // 各周の最後の窓はファイル末尾まで(自然な間を保つ)
                    let isPassLast = (i == lastScheduled && r == segCounts[i] - 1)
                    let start = segReplayStarts.indices.contains(i) ? segReplayStarts[i] : 0
                    var end = isPassLast ? dur : min(segSpeechEnds.indices.contains(i) ? segSpeechEnds[i] : dur, dur)
                    if end < start { end = start }
                    windows.append(PlayWindow(pass: pass, seg: i, rep: r, start: start, end: end, cumBefore: cum))
                    cum += end - start
                }
                // 「英文→和訳」順: 文末に和訳の窓
                if jaDur > 0, !jaLeadMode {
                    windows.append(PlayWindow(pass: pass, seg: i, rep: max(0, segCounts[i] - 1), start: 0, end: jaDur,
                                              cumBefore: cum, isJa: true, jaLead: false))
                    cum += jaDur
                }
            }
        }
        progress.duration = cum
    }

    /// 仮想タイムライン上の現在位置を更新する(変化が小さい時は publish しない)
    private func updateProgress(player: AVAudioPlayer) {
        guard let w = windows.first(where: { !$0.isJa && $0.pass == blockPassesDone && $0.seg == curSeg && $0.rep == curRep }) else { return }
        let pos = w.cumBefore + max(0, min(player.currentTime - w.start, w.end - w.start))
        if abs(pos - progress.position) > 0.15 {
            progress.position = pos
        }
    }

    /// 和訳読み上げ中のスライダー位置を更新する
    private func updateJaProgress() {
        guard let w = windows.first(where: { $0.isJa && $0.pass == blockPassesDone && $0.seg == curSeg && $0.jaLead == jaLeadPending }) else { return }
        let elapsed: Double
        if let jaPlayer {
            elapsed = jaPlayer.currentTime
        } else {
            // TTSは実位置が取れないため経過時間で近似する
            elapsed = CFAbsoluteTimeGetCurrent() - jaStartedAt
        }
        let pos = w.cumBefore + max(0, min(elapsed, w.end - w.start))
        if abs(pos - progress.position) > 0.15 {
            progress.position = pos
        }
    }

    /// 表示が「和訳→英文」の順のとき、音声も和訳を先に読む(表示順と音声順を一致させる)
    private var jaOrderFirst: Bool {
        UserDefaults.standard.bool(forKey: "audioJaFirst")
    }

    /// この文の和訳を読み上げる。事前生成音声(VOICEVOX)があればそれを再生し、無い文だけTTSで読む
    private func speakJa(_ ja: String) {
        isSpeakingJa = true
        speakingJaSegment = curSeg
        jaStartedAt = CFAbsoluteTimeGetCurrent()
        if items.indices.contains(currentIndex),
           let url = JaAudioStore.url(forBlockText: items[currentIndex].english, segmentIndex: curSeg),
           let filePlayer = try? AVAudioPlayer(contentsOf: url) {
            filePlayer.delegate = self
            filePlayer.enableRate = true
            filePlayer.rate = Float(speed)
            jaPlayer = filePlayer
            filePlayer.play()
        } else {
            let utterance = AVSpeechUtterance(string: ja)
            utterance.voice = japaneseVoice
            jaSynthesizer.speak(utterance)
        }
    }

    /// いまの文を1回読み終えた時の分岐(繰り返す / 和訳を挟む / 次の文へ / 次のブロックへ)。
    /// force=true は「設定変更でいまの文が×0になった」時で、回数消化とみなして先へ進む。
    private func advanceAfterSegment(force: Bool = false) {
        guard let player else { return }
        if !force {
            curRep += 1
            if curSeg < segCounts.count, curRep < segCounts[curSeg] {
                let from = segReplayStarts.indices.contains(curSeg) ? segReplayStarts[curSeg] : segStarts[curSeg]
                replay(from: from, player: player)
                return
            }
        }
        // 「英文→和訳」順のとき: この文の繰り返しを消化したら、和訳を読み上げてから先へ進む。
        // (「和訳→英文」順のときは文の頭で読み上げ済みなので、ここでは読まない)
        if jaAfterSentence, !jaOrderFirst, !isSpeakingJa, !force, let ja = jaText(forSegment: curSeg), !ja.isEmpty {
            player.pause()
            speakJa(ja)
            if timer == nil { startTimer() }  // 和訳中もスライダーを進める
            return
        }
        advanceToNextScheduled()
    }

    /// 指定の文へ入る。「和訳→英文」順のときは、先に和訳を読み上げてから英文を流す
    private func beginSegment(_ seg: Int) {
        guard let player else { return }
        curSeg = seg
        curRep = 0
        publishCurrentSentence()
        if jaAfterSentence, jaOrderFirst, !isSpeakingJa, let ja = jaText(forSegment: seg), !ja.isEmpty {
            player.pause()
            highlight.range = nil
            jaLeadPending = true
            speakJa(ja)
            if timer == nil { startTimer() }  // 和訳中もスライダーを進める
            return
        }
        let from = segReplayStarts.indices.contains(seg) ? segReplayStarts[seg] : segStarts[seg]
        replay(from: from, player: player)
    }

    /// 次の予定(次の文 / 次の周 / 次のブロック)へ進む
    private func advanceToNextScheduled() {
        guard player != nil else { return }
        if let next = nextScheduled(from: curSeg + 1) {
            beginSegment(next)
            return
        }
        // ブロック内の予定を消化 → 全体繰り返しが残っていればもう1周
        if blockPassesDone + 1 < blockRepeatCount, let first = nextScheduled(from: 0) {
            blockPassesDone += 1
            beginSegment(first)
            return
        }
        // 次のブロックへ
        currentIndex += 1
        playCurrent()
    }

    /// ミニプレイヤー用に「今読んでいる文」を更新する(文が変わった時だけ publish)
    private func publishCurrentSentence() {
        guard items.indices.contains(currentIndex) else {
            if currentSentence != nil { currentSentence = nil }
            return
        }
        let item = items[currentIndex]
        let text: String
        let ja: String
        if let segs = item.segments, segs.indices.contains(curSeg) {
            text = segs[curSeg].en
            ja = segs[curSeg].ja
        } else {
            text = item.english
            ja = item.japanese
        }
        if currentSentence != text { currentSentence = text }
        if currentSentenceJa != ja { currentSentenceJa = ja }
        if currentSegmentIndex != curSeg { currentSegmentIndex = curSeg }
    }

    /// この文の和訳(文ペアがあればその文の和訳、無いブロックは全訳)
    private func jaText(forSegment i: Int) -> String? {
        guard items.indices.contains(currentIndex) else { return nil }
        let item = items[currentIndex]
        if let segs = item.segments {
            return segs.indices.contains(i) ? segs[i].ja : nil
        }
        return item.japanese
    }

    /// いまの文の英文部分を頭から流す(文頭の和訳読みを終えた後に使う)
    private func startEnglishOfCurrentSegment() {
        guard let player else { return }
        let from = segReplayStarts.indices.contains(curSeg) ? segReplayStarts[curSeg] : (segStarts.indices.contains(curSeg) ? segStarts[curSeg] : 0)
        replay(from: from, player: player)
    }

    /// 和訳読み上げを中断する。resume=true なら教材音声の再生も再開する
    /// (文頭の和訳読みの途中だった場合は、次へ飛ばずにいまの文の英文から再開する)
    private func cancelJaSpeech(resume: Bool = false) {
        guard isSpeakingJa else { return }
        isSpeakingJa = false
        speakingJaSegment = nil
        let wasLead = jaLeadPending
        jaLeadPending = false
        jaPlayer?.stop()
        jaPlayer = nil
        jaSynthesizer.stopSpeaking(at: .immediate)
        if resume, isPlayingSequence, !isPaused {
            if wasLead {
                startEnglishOfCurrentSegment()
            } else {
                advanceToNextScheduled()
            }
        }
    }

    /// 同じファイル内で再生位置を移して続ける(繰り返し・次の文への移動)
    private func replay(from t: Double, player: AVAudioPlayer) {
        player.currentTime = t
        highlight.range = nil
        lastWordIndex = -1
        if !isPaused {
            if !player.isPlaying { player.play() }
            if timer == nil { startTimer() }
        }
    }

    private func startTimer() {
        stopTimer()
        let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = 0.02
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 毎tick: 文の終端に達したら次へ、そうでなければ単語ハイライトを更新
    private func tick() {
        guard isPlayingSequence, !isPaused else { return }
        // 和訳の読み上げ中もスライダーを進める(合計時間に和訳の分が入っているため)
        if isSpeakingJa {
            updateJaProgress()
            return
        }
        guard let player else { return }
        // 文の終わりは常に「話し終わり(+余韻)」で切り、文間の息継ぎ・間は再生しない。
        // ただしブロック最終文の最後の1回だけはファイル末尾まで自然に流す
        // (ブロック間の間はそのまま保つ)。
        let isFinalRep = curSeg >= segCounts.count || curRep + 1 >= segCounts[curSeg]
        let endPoint: Double? = (isFinalRep && windowEnd(curSeg) == nil)
            ? nil
            : (segSpeechEnds.indices.contains(curSeg) ? segSpeechEnds[curSeg] : windowEnd(curSeg))
        if let end = endPoint, player.currentTime >= end - 0.02 {
            advanceAfterSegment()
            return
        }
        updateHighlight(player: player)
        updateProgress(player: player)
    }

    /// 再生位置から「今読んでいる単語」を求めてハイライトを更新する
    private func updateHighlight(player: AVAudioPlayer) {
        guard items.indices.contains(currentIndex) else { return }
        let words = items[currentIndex].words
        guard !words.isEmpty else { return }
        let t = player.currentTime
        var idx = lastWordIndex
        if idx >= 0, idx < words.count, words[idx].start > t { idx = -1 }
        while idx + 1 < words.count, words[idx + 1].start <= t { idx += 1 }
        // 文単位再生中は、いま読んでいる文の範囲外の単語をハイライトしない
        // (文頭の少し手前から再生する時に、前の文の最後の単語が一瞬光るのを防ぐ)
        if idx >= 0, let segs = items[currentIndex].segments, segs.indices.contains(curSeg) {
            let r = segs[curSeg].range
            let w = words[idx].range
            if w.location < r.location || w.location >= r.location + r.length {
                idx = -1
            }
        }
        if idx != lastWordIndex {
            lastWordIndex = idx
            highlight.range = idx >= 0 ? words[idx].range : nil
        }
    }

    /// 再生用にオーディオセッションを整える(録音中は触らない)
    private func activatePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        if !SpeechRecognitionService.isAnyRecording {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try? session.setActive(true, options: [])
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            // 事前生成の和訳音声を読み終えた → (文頭読みなら英文へ / 文末読みなら次の予定へ)
            if finished === self.jaPlayer {
                self.jaPlayer = nil
                guard self.isSpeakingJa else { return }
                self.isSpeakingJa = false
                self.speakingJaSegment = nil
                guard self.isPlayingSequence, !self.isPaused else { return }
                if self.jaLeadPending {
                    self.jaLeadPending = false
                    self.startEnglishOfCurrentSegment()
                    return
                }
                self.advanceToNextScheduled()
                return
            }
            // isPaused も確認: 文末とほぼ同時に一時停止された場合に握り潰さない
            guard self.isPlayingSequence, !self.isPaused, finished === self.player else { return }
            // ファイル末尾に到達 = 最後の文を1回読み終えた
            self.advanceAfterSegment()
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate(「英文→和訳」交互モードの和訳読み上げ)

extension AudioSequencePlayer: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            guard self.isSpeakingJa else { return }
            self.isSpeakingJa = false
            self.speakingJaSegment = nil
            guard self.isPlayingSequence, !self.isPaused else { return }
            if self.jaLeadPending {
                self.jaLeadPending = false
                self.startEnglishOfCurrentSegment()
                return
            }
            self.advanceToNextScheduled()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeakingJa = false
            self.speakingJaSegment = nil
        }
    }
}
