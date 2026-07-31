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

struct ReadingView: View {
    @Environment(\.modelContext) private var context
    let passage: Passage

    @State private var expandedBlockIDs: Set<PersistentIdentifier> = []
    @State private var selectedWord: SelectedWord?
    @State private var selectedSentence: SelectedSentence?
    @State private var retryConfiguration: TranslationSession.Configuration?

    private var blocks: [Block] {
        passage.orderedBlocks
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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
                }
            }
            .padding()
        }
        .navigationTitle(passage.title)
        .navigationBarTitleDisplayMode(.inline)
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
            if blocks.contains(where: { $0.japaneseText == nil }) {
                retryConfiguration = TranslationSession.Configuration(
                    source: TranslationAvailability.english,
                    target: TranslationAvailability.japanese
                )
            }
        }
    }

    private func toggle(_ block: Block) {
        if expandedBlockIDs.contains(block.persistentModelID) {
            expandedBlockIDs.remove(block.persistentModelID)
        } else {
            expandedBlockIDs.insert(block.persistentModelID)
        }
    }

    private func retryTranslations(with session: TranslationSession) async {
        let untranslated = blocks.filter { $0.japaneseText == nil }
        guard !untranslated.isEmpty else { return }
        do {
            try await session.prepareTranslation()
            let requests = untranslated.map { block in
                TranslationSession.Request(sourceText: block.englishText, clientIdentifier: "\(block.index)")
            }
            for try await response in session.translate(batch: requests) {
                if let identifier = response.clientIdentifier,
                   let index = Int(identifier),
                   let block = blocks.first(where: { $0.index == index }) {
                    block.japaneseText = response.targetText
                }
            }
            try? context.save()
        } catch {
            // オフライン・言語データ未ダウンロード時は静かに諦める(次回表示時に再試行)
        }
    }
}
