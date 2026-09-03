import SwiftData
import SwiftUI
import UIKit

/// 復習タブ。音読の文章を「1文ずつ」和訳で並べ、タップすると英文が出る自己テスト用。
///
/// - 各文は既定で和訳だけを見せ、行をタップすると英文が開く(もう一度で閉じる)。
/// - 行の左のチェックで「もう覚えた」を記録する([[MemorizedSentenceStore]])。
/// - 右上のフィルターで、覚えた文を隠して未チェックだけを表示できる。
struct SentenceReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Passage> { $0.purposeRaw == "reading" })
    private var passages: [Passage]

    @ObservedObject private var store = MemorizedSentenceStore.shared

    /// 文ごとに一度だけ組み立てた一覧(描画のたびに JSON デコードしないためメモ化)
    @State private var built: [PassageSentences] = []
    /// いま英文を開いている文
    @State private var expandedIDs: Set<String> = []
    /// 覚えた文を隠して未チェックだけ表示するか
    @State private var hideMemorized = false

    var body: some View {
        NavigationStack {
            Group {
                if visiblePassages.isEmpty {
                    ContentUnavailableView(
                        hideMemorized ? "未チェックの文はありません" : "文がありません",
                        systemImage: hideMemorized ? "checkmark.circle" : "text.book.closed",
                        description: Text(hideMemorized ? "すべて覚えました。右上のフィルターを戻すと全文が出ます。"
                                          : "音読タブに文章を取り込むと、ここに1文ずつ並びます。")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("復習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { hideMemorized.toggle() }
                    } label: {
                        Image(systemName: hideMemorized
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(hideMemorized ? "覚えた文も表示" : "覚えた文を隠す")
                }
            }
            .task { if built.isEmpty { rebuild() } }
            .onChange(of: passages.count) { _, _ in rebuild() }
        }
    }

    private var list: some View {
        List {
            ForEach(visiblePassages) { p in
                Section(p.title) {
                    ForEach(p.visible(hideMemorized: hideMemorized, store: store)) { s in
                        row(s)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ s: ReviewSentence) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 左のチェック。押すと「覚えた」の記録が入り切りする
            Button {
                store.toggle(s.id)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: store.isMemorized(s.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(store.isMemorized(s.id) ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            // 和訳。タップで英文が開く(もう一度で閉じる)
            VStack(alignment: .leading, spacing: 6) {
                Text(s.japanese.isEmpty ? "(和訳なし)" : s.japanese)
                    .font(.body)
                    .foregroundStyle(store.isMemorized(s.id) ? .secondary : .primary)
                if expandedIDs.contains(s.id) {
                    Text(s.english)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if expandedIDs.contains(s.id) { expandedIDs.remove(s.id) }
                else { expandedIDs.insert(s.id) }
            }
        }
        .padding(.vertical, 2)
    }

    /// 表示するべき文章(フィルター中は、見せる文が1つも無い文章は出さない)
    private var visiblePassages: [PassageSentences] {
        guard hideMemorized else { return built }
        return built.filter { !$0.visible(hideMemorized: true, store: store).isEmpty }
    }

    /// 文章→文ごとのペアを一度だけ組み立てる。
    private func rebuild() {
        let ordered = orderedPassages()
        var result: [PassageSentences] = []
        for passage in ordered {
            let sentences = sentencesOf(passage)
            if !sentences.isEmpty {
                result.append(PassageSentences(id: passage.persistentModelID,
                                               title: passage.title,
                                               sentences: sentences))
            }
        }
        built = result
    }

    /// sortIndex(小さいほど上)→ 同値は作成日の新しい順
    private func orderedPassages() -> [Passage] {
        passages.sorted { a, b in
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt > b.createdAt
        }
    }

    /// 1つの文章を、文ごとの和訳→英文に分ける
    private func sentencesOf(_ passage: Passage) -> [ReviewSentence] {
        var sentences: [ReviewSentence] = []
        for block in passage.orderedBlocks {
            let pairs = SentencePairLookup.cached(blockText: block.englishText, modelContext: modelContext)
            if let pairs {
                for pair in pairs {
                    sentences.append(ReviewSentence(id: MemorizedSentenceStore.key(for: pair.en),
                                                    english: pair.en, japanese: pair.ja))
                }
            } else {
                // ペアが無いブロックは1ブロックを1文として出す(英文の頭が消えないように)
                sentences.append(ReviewSentence(id: MemorizedSentenceStore.key(for: block.englishText),
                                                english: block.englishText,
                                                japanese: block.japaneseText ?? ""))
            }
        }
        return sentences
    }
}

/// 1文(和訳→英文)。id は英文のハッシュ(チェックの保存キーと同じ)
private struct ReviewSentence: Identifiable {
    let id: String
    let english: String
    let japanese: String
}

/// 文章1つ分の文の並び
private struct PassageSentences: Identifiable {
    let id: PersistentIdentifier
    let title: String
    let sentences: [ReviewSentence]

    func visible(hideMemorized: Bool, store: MemorizedSentenceStore) -> [ReviewSentence] {
        hideMemorized ? sentences.filter { !store.isMemorized($0.id) } : sentences
    }
}
