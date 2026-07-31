import SwiftData
import SwiftUI
import Translation

private struct SelectedWord: Identifiable {
    let id = UUID()
    let word: String
}

private struct SelectedSentence: Identifiable {
    let id = UUID()
    let sentence: String
}

/// 音読タブ。文章の分類はせず、登録したすべての英文ブロックを 1 画面に連続表示する。
struct PassageListView: View {
    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "reading" },
        sort: \Passage.createdAt, order: .reverse
    ) private var passages: [Passage]

    @State private var showingAdd = false
    @State private var expandedBlockIDs: Set<PersistentIdentifier> = []
    @State private var selectedWord: SelectedWord?
    @State private var selectedSentence: SelectedSentence?
    @State private var retryConfiguration: TranslationSession.Configuration?

    private var blocks: [Block] {
        passages.flatMap { $0.orderedBlocks }
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "book",
                        description: Text("右上の + から英文を登録しましょう。音声入力でも写真でも OK です。")
                    )
                } else {
                    List {
                        ForEach(blocks) { block in
                            BlockCardView(
                                block: block,
                                isExpanded: expandedBlockIDs.contains(block.persistentModelID),
                                onToggle: { toggle(block) },
                                onWordTap: { word in
                                    selectedWord = SelectedWord(word: word)
                                },
                                onLongPress: {
                                    selectedSentence = SelectedSentence(sentence: block.englishText)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(block)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                startRetryTranslationIfNeeded()
            }) {
                AddPassageView(purpose: .reading)
            }
            .sheet(item: $selectedWord) { selected in
                WordPopupView(word: selected.word)
            }
            .sheet(item: $selectedSentence) { selected in
                SyntaxAnalysisView(sentence: selected.sentence)
            }
            // 未翻訳ブロックは表示時に再翻訳を試みる
            .translationTask(retryConfiguration) { session in
                await retryTranslations(with: session)
            }
            .onAppear {
                startRetryTranslationIfNeeded()
            }
        }
    }

    private func delete(_ block: Block) {
        let passage = block.passage
        context.delete(block)
        // ブロックがなくなった文章は本体ごと削除する
        if let passage, passage.blocks.filter({ $0.persistentModelID != block.persistentModelID }).isEmpty {
            context.delete(passage)
        }
        try? context.save()
    }

    private func toggle(_ block: Block) {
        if expandedBlockIDs.contains(block.persistentModelID) {
            expandedBlockIDs.remove(block.persistentModelID)
        } else {
            expandedBlockIDs.insert(block.persistentModelID)
        }
    }

    private func startRetryTranslationIfNeeded() {
        guard blocks.contains(where: { $0.japaneseText == nil }) else { return }
        if retryConfiguration == nil {
            retryConfiguration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
        } else {
            retryConfiguration?.invalidate()
        }
    }

    private func retryTranslations(with session: TranslationSession) async {
        let untranslated = blocks.filter { $0.japaneseText == nil }
        guard !untranslated.isEmpty else { return }
        do {
            try await session.prepareTranslation()
            let requests = untranslated.enumerated().map { index, block in
                TranslationSession.Request(sourceText: block.englishText, clientIdentifier: "\(index)")
            }
            for try await response in session.translate(batch: requests) {
                if let identifier = response.clientIdentifier,
                   let index = Int(identifier),
                   index < untranslated.count {
                    untranslated[index].japaneseText = response.targetText
                }
            }
            try? context.save()
        } catch {
            // オフライン・言語データ未ダウンロード時は静かに諦める(次回表示時に再試行)
        }
    }
}
