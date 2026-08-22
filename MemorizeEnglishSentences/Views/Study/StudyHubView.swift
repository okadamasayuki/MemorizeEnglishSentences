import SwiftData
import SwiftUI

/// 単語学習ハブ。
/// ①「チェックした英文」を開いて、意味と結びつかない単語をタップで選ぶ
///   (このタブでは教材音声で英文を順番に読み上げて、どこが分からなかったか復習できる)
/// ②選んだ単語リストを確認して、シス単風プレイヤーで再生する
struct StudyHubView: View {
    /// 呼び出し元(音読タブ)の modelContext を明示的に受け取る。
    /// sheet の @Environment(\.modelContext) が空だと passage 検索・意味引きが失敗し、
    /// 教材音声が使えず読み上げに落ちてしまうため、確実に効く context を渡す。
    let context: ModelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyStore.shared
    private var speech: SpeechSynthesisService { .shared }
    @AppStorage("listenSpeed") private var listenSpeed = 1.0
    @State private var showWordPlayer = false
    @State private var showAudioPlayer = false
    @State private var showSentencePlayer = false
    @State private var sentenceItems: [PlaybackItem] = []
    /// 0=チェックした英文(左) / 1=覚える単語(右)。件数が増えても押しづらくならないようタブ分け
    @State private var tab = 0

    /// 左上の再生ボタンを押せるか(表示中タブの中身が空なら押せない)
    private var canPlay: Bool { tab == 0 ? !store.flagged.isEmpty : !store.words.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("チェックした英文").tag(0)
                    Text("覚える単語").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if tab == 0 { flaggedTab } else { wordsTab }
            }
            .navigationTitle("単語学習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 左上=再生(表示中タブの内容を再生)。閉じる(×)の対角に置く
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if tab == 0 { playFlaggedSentences() } else { showWordPlayer = true }
                    } label: {
                        Image(systemName: "play.circle.fill").font(.title2)
                    }
                    .disabled(!canPlay)
                }
                // 右上=閉じる(×アイコン)
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold))
                    }
                }
            }
            // 他のボタンと合わせて青(アクセント)で表示する
            .tint(Color.accentColor)
            // 再生中に下スワイプで下げると、ミニプレイヤーに残す(音読と同じ操作感)
            .miniPlayerHost()
            .sheet(isPresented: $showWordPlayer) {
                StudyWordPlayerView(words: store.words)
            }
            // 教材音声のプレイヤー(音読タブと同じ画面)。下スワイプで閉じると
            // 再生は続いてミニプレイヤーに残る
            .sheet(isPresented: $showAudioPlayer) {
                AudioPlayerView()
            }
            .fullScreenCover(isPresented: $showSentencePlayer) {
                SentencePlayerView(items: sentenceItems)
            }
            .onAppear {
                backfillBlockRefs()
                backfillMeanings()
            }
        }
    }

    // チェックした英文タブ(ここで単語を選ぶ。複数選択可。左上の再生で順番に読み上げ)
    private var flaggedTab: some View {
        List {
            if store.flagged.isEmpty {
                Text("音読プレイヤーで各文のしおりボタンを押すと、その英文がここに入ります。左上の再生ボタンで、チェックした英文を教材音声で順番に読み上げて復習できます。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(store.flagged) { s in
                    FlaggedSentenceRow(sentence: s, context: context)
                        .swipeActions {
                            Button(role: .destructive) { store.removeFlagged(s.id) } label: {
                                Image(systemName: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    // 覚える単語タブ(再生は左上のボタンから。シス単風プレイヤーが開く)
    private var wordsTab: some View {
        List {
            if store.words.isEmpty {
                Text("「チェックした英文」タブで、意味と結びつかない単語をタップすると、ここに集まります。左上の再生ボタンでシス単風(英→和→英)に再生します。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(store.words) { w in
                    HStack {
                        Text(w.word).font(.body.weight(.medium))
                        Text(w.meaning).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.removeWord(w.id) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    /// チェックした英文を、教材の本物音声(音読タブと同じ)で上から順番に読み上げる。
    /// 出典ブロックのMP3を使い、その文だけを鳴らす(他の文はスキップ)。
    /// 音声が見つからない文しか無ければ、従来の読み上げ(合成音声)にフォールバックする。
    private func playFlaggedSentences() {
        let flaggedList = store.flagged
        guard !flaggedList.isEmpty else { return }
        let allPassages = (try? context.fetch(FetchDescriptor<Passage>())) ?? []

        // 各チェック文の出典ブロック全文を求める(保存済みblockEn優先、無ければ本文検索)
        func blockText(for s: StudyStore.FlaggedSentence) -> String? {
            let saved = s.blockEn.trimmingCharacters(in: .whitespacesAndNewlines)
            if !saved.isEmpty { return saved }
            let sent = s.en.trimmingCharacters(in: .whitespacesAndNewlines)
            return allPassages.first { $0.englishFullText.contains(sent) }?.englishFullText
        }

        // ブロック全文 → そのブロックでチェックされた文(英文)の集合
        var byBlock: [String: Set<String>] = [:]
        for s in flaggedList {
            guard let bt = blockText(for: s) else { continue }
            byBlock[bt, default: []].insert(s.en.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // ブロックは文章の並び順で(該当passageが無いものは後ろへ)
        let ordered = allPassages.map { $0.englishFullText }.filter { byBlock[$0] != nil }
        let extras = byBlock.keys.filter { !ordered.contains($0) }

        var items: [AudioPlaybackItem] = []
        for bt in ordered + extras {
            guard let ens = byBlock[bt],
                  BlockAudioStore.hasAudio(forBlockText: bt),
                  let a = BlockAudioStore.item(forBlockText: bt),
                  let pairs = SentencePairLookup.cached(blockText: bt, modelContext: context),
                  let segments = AudioPlaybackItem.buildSegments(
                      english: bt, pairs: pairs.map { ($0.en, $0.ja) }, words: a.words)
            else { continue }
            // チェック済みの文だけ回数1、他の文は0(=スキップ)にして、その文だけ鳴らす
            let counts = segments.map {
                ens.contains($0.en.trimmingCharacters(in: .whitespacesAndNewlines)) ? 1 : 0
            }
            guard counts.contains(where: { $0 > 0 }) else { continue }
            let jp = allPassages.first { $0.englishFullText == bt }?.japaneseFullText ?? ""
            items.append(AudioPlaybackItem(english: bt, japanese: jp, url: a.url, words: a.words,
                                           segments: segments, repeatCounts: counts,
                                           silences: a.silences, blockRepeat: 1))
        }

        AudioSequencePlayer.shared.stop()
        StudyWordPlayer.shared.stopAll()

        if items.isEmpty {
            // 教材音声が見つからない → 従来の読み上げ(合成音声)にフォールバック
            let tts = flaggedList.map { PlaybackItem(english: $0.en, japanese: $0.ja) }
            sentenceItems = tts
            speech.speakSequence(tts.map(\.english), speed: listenSpeed, startAt: 0)
            showSentencePlayer = true
            return
        }
        AudioSequencePlayer.shared.start(items: items, startAt: 0, speed: listenSpeed, source: .study)
        showAudioPlayer = true
    }

    /// 古いチェック文(出典ブロック未記録)に、本文検索でブロック全文を紐づける。
    /// これで教材音声の再生も、文脈に合った意味引きも効くようになる。
    private func backfillBlockRefs() {
        let needs = store.flagged.filter { $0.blockEn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !needs.isEmpty else { return }
        let allPassages = (try? context.fetch(FetchDescriptor<Passage>())) ?? []
        guard !allPassages.isEmpty else { return }
        for s in needs {
            let sent = s.en.trimmingCharacters(in: .whitespacesAndNewlines)
            if let block = allPassages.first(where: { $0.englishFullText.contains(sent) })?.englishFullText {
                store.setBlockEn(s.id, blockEn: block)
            }
        }
    }

    /// 覚える単語に日本語訳が入っていないものを補う。
    /// まずその単語を含むチェック文の出典ブロックで文脈に合った意味を引き、無ければ内蔵辞書。
    private func backfillMeanings() {
        let empties = store.words.filter { $0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !empties.isEmpty else { return }
        for w in empties {
            var meaning = ""
            // この単語を含むチェック文を探し、その出典ブロックを文脈にして意味を引く
            if let s = store.flagged.first(where: {
                WordTokenizer.tokenize($0.en).contains { tok in
                    (tok.normalized.isEmpty ? tok.display : tok.normalized).lowercased() == w.word.lowercased()
                }
            }) {
                let block = s.blockEn.isEmpty ? s.en : s.blockEn
                if let sense = WordSenseLookup.cached(word: w.word, blockText: block, modelContext: context) {
                    meaning = sense.meaningJa
                }
            }
            if meaning.isEmpty, let entry = BasicWordDictionary.lookup(w.word) { meaning = entry }
            if !meaning.isEmpty { store.setMeaning(w.id, meaning: meaning) }
        }
    }
}

/// チェックした英文1件。単語をタップすると「覚える単語」に出し入れできる。
private struct FlaggedSentenceRow: View {
    let sentence: StudyStore.FlaggedSentence
    let context: ModelContext
    @ObservedObject private var store = StudyStore.shared

    private var tokens: [WordToken] { WordTokenizer.tokenize(sentence.en) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 4, lineSpacing: 6) {
                ForEach(tokens) { token in
                    let word = token.normalized.isEmpty ? token.display : token.normalized
                    let picked = store.hasWord(word)
                    Text(token.display)
                        .font(.body)
                        .foregroundStyle(picked ? Color.white : Color.primary)
                        .padding(.horizontal, picked ? 5 : 0)
                        .padding(.vertical, picked ? 2 : 0)
                        .background(picked ? Capsule().fill(Color.accentColor) : nil)
                        .onTapGesture { toggle(word: word, token: token) }
                }
            }
            if !sentence.ja.isEmpty {
                Text(sentence.ja).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(word: String, token: WordToken) {
        if store.hasWord(word) {
            store.toggleWord(word, meaning: "")  // 既にある→外す
            return
        }
        // この文での意味を最優先で引く。文脈は出典ブロック全文(あれば)を使うと精度が高い
        let occ = WordTokenizer.occurrence(of: token, in: tokens)
        let blockText = sentence.blockEn.isEmpty ? sentence.en : sentence.blockEn
        var meaning = ""
        if let sense = WordSenseLookup.cached(word: word, occurrence: occ,
                                              blockText: blockText, modelContext: context) {
            meaning = sense.meaningJa
        } else if let sense = WordSenseLookup.cached(word: word, blockText: blockText,
                                                     modelContext: context) {
            meaning = sense.meaningJa
        } else if let entry = BasicWordDictionary.lookup(word) {
            meaning = entry
        }
        store.toggleWord(word, meaning: meaning)
    }
}
