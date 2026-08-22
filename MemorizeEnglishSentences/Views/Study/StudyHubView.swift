import SwiftData
import SwiftUI

/// 単語学習ハブ。
/// ①「チェックした英文」を開いて、意味と結びつかない単語をタップで選ぶ
///   (このタブでは英文を順番に読み上げて、どこが分からなかったか復習できる)
/// ②選んだ単語リストを確認して、シス単風プレイヤーで再生する
struct StudyHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyStore.shared
    private var speech: SpeechSynthesisService { .shared }
    @State private var showWordPlayer = false
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
            .fullScreenCover(isPresented: $showWordPlayer) {
                StudyWordPlayerView(words: store.words)
            }
            .fullScreenCover(isPresented: $showSentencePlayer) {
                SentencePlayerView(items: sentenceItems)
            }
        }
    }

    // チェックした英文タブ(ここで単語を選ぶ。複数選択可。左上の再生で順番に読み上げ)
    private var flaggedTab: some View {
        List {
            if store.flagged.isEmpty {
                Text("音読プレイヤーで各文のしおりボタンを押すと、その英文がここに入ります。左上の再生ボタンで、チェックした英文を順番に読み上げて復習できます。")
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

    /// チェックした英文を上から順番に読み上げる(復習用)。他の音声とは二重に鳴らさない
    private func playFlaggedSentences() {
        let items = store.flagged.map { PlaybackItem(english: $0.en, japanese: $0.ja) }
        guard !items.isEmpty else { return }
        AudioSequencePlayer.shared.stop()
        StudyWordPlayer.active?.stopAll()
        sentenceItems = items
        speech.speakSequence(items.map(\.english), startAt: 0)
        showSentencePlayer = true
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
        // この文での意味を最優先で引く(無ければ内蔵辞書)
        let occ = WordTokenizer.occurrence(of: token, in: tokens)
        var meaning = ""
        if let sense = WordSenseLookup.cached(word: word, occurrence: occ,
                                              blockText: sentence.en, modelContext: context) {
            meaning = sense.meaningJa
        } else if let entry = BasicWordDictionary.lookup(word) {
            meaning = entry
        }
        store.toggleWord(word, meaning: meaning)
    }
}
