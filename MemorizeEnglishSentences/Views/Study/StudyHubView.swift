import SwiftData
import SwiftUI

/// 単語学習ハブ。
/// ①「チェックした英文」を開いて、意味と結びつかない単語をタップで選ぶ
/// ②選んだ単語リストを確認して、シス単風プレイヤーで再生する
struct StudyHubView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StudyStore.shared
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            List {
                // 覚える単語リスト
                Section("覚える単語(\(store.words.count))") {
                    if store.words.isEmpty {
                        Text("下の「チェックした英文」で、意味と結びつかない単語をタップすると、ここに集まります。")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Button {
                            showPlayer = true
                        } label: {
                            Label("単語リストを再生(シス単風)", systemImage: "play.circle.fill")
                                .font(.body.weight(.semibold))
                        }
                        ForEach(store.words) { w in
                            HStack {
                                Text(w.word).font(.body.weight(.medium))
                                Text(w.meaning).font(.subheadline).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .swipeActions {
                                Button(role: .destructive) { store.removeWord(w.id) } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }

                // チェックした英文(ここで単語を選ぶ)
                Section("チェックした英文(\(store.flagged.count))") {
                    if store.flagged.isEmpty {
                        Text("音読プレイヤーでしおりボタンを押すと、その英文がここに入ります。")
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
            }
            .navigationTitle("単語学習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                StudyWordPlayerView(words: store.words)
            }
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
