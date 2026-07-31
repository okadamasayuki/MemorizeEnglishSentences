import SwiftData
import SwiftUI
import Translation

private struct SelectedWord: Identifiable {
    let id = UUID()
    let word: String
}

private struct TranslationTimeoutError: Error {}

/// 翻訳にタイムアウトを付ける(起動直後はエラーも返さず固まることがあるため)
private func translate(
    _ session: TranslationSession, _ text: String, timeoutSeconds: Double
) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            try await session.translate(text).targetText
        }
        group.addTask {
            try await Task.sleep(for: .seconds(timeoutSeconds))
            throw TranslationTimeoutError()
        }
        guard let result = try await group.next() else {
            throw TranslationTimeoutError()
        }
        group.cancelAll()
        return result
    }
}

/// 単語翻訳のリクエストを、常駐している翻訳セッションへ流し込むための橋渡し。
/// (タップごとに invalidate() でセッションを作り直す方式は、シート表示と
///  タイミングが重なる初回タップで再実行されないことがあるため)
@MainActor
private final class WordTranslationBroker {
    private var continuation: AsyncStream<String>.Continuation?
    private var pending: String?
    private var retried = Set<String>()

    /// セッション作り直しリトライをまだ試していない単語か
    func shouldRetry(_ word: String) -> Bool {
        !retried.contains(word)
    }

    /// セッション作り直し後に再翻訳するため、単語を積み直す
    func stashForRetry(_ word: String) {
        retried.insert(word)
        pending = word
        continuation = nil
    }

    func requests() -> AsyncStream<String> {
        AsyncStream { continuation in
            print("[WT] stream consumer attached")
            self.continuation = continuation
            if let pending {
                print("[WT] flushing pending: \(pending)")
                continuation.yield(pending)
                self.pending = nil
            }
        }
    }

    func request(_ word: String) {
        print("[WT] request '\(word)' continuation=\(continuation != nil)")
        if let continuation {
            continuation.yield(word)
        } else {
            pending = word
        }
    }
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
    @State private var wordJapanese: String?
    @State private var wordFailed = false
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?
    @State private var retryConfiguration: TranslationSession.Configuration?
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var scrollProxy: ScrollViewProxy?

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
                    ScrollViewReader { proxy in
                        List {
                            ForEach(blocks) { block in
                                blockRow(block)
                                    .id(block.persistentModelID)
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
                                    // 右スワイプでどこまで読んだかの目印を付ける
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            toggleMark(block)
                                        } label: {
                                            Image(systemName: block.isMarked ? "bookmark.slash" : "bookmark.fill")
                                        }
                                        .tint(.orange)
                                    }
                            }
                        }
                        .listStyle(.plain)
                        // 選択モード中は背景色を少し変えてわかるようにする
                        .scrollContentBackground(.hidden)
                        .background(isSelecting ? Color.red.opacity(0.07) : Color(.systemBackground))
                        .animation(.easeInOut(duration: 0.2), value: isSelecting)
                        .onAppear {
                            scrollProxy = proxy
                        }
                    }
                }
            }
            .toolbar {
                if !blocks.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation {
                                isSelecting.toggle()
                                selection.removeAll()
                            }
                        } label: {
                            Image(systemName: isSelecting ? "checkmark.circle.fill" : "checkmark.circle")
                                .foregroundStyle(isSelecting ? Color.red : Color.accentColor)
                        }
                    }
                    // 目印(しおり)へジャンプ
                    if let marked = blocks.first(where: { $0.isMarked }), !isSelecting {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                withAnimation {
                                    scrollProxy?.scrollTo(marked.persistentModelID, anchor: .center)
                                }
                            } label: {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSelecting {
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selection.isEmpty)
                    } else {
                        Button {
                            showingAdd = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                startRetryTranslationIfNeeded()
            }) {
                AddPassageView(purpose: .reading)
            }
            .sheet(item: $selectedWord) { selected in
                WordPopupView(word: selected.word, japanese: wordJapanese, failed: wordFailed)
            }
            // 単語の翻訳(常駐セッション 1 本に、タップされた単語をストリームで流し込む)
            .translationTask(wordConfiguration) { session in
                // ダミー翻訳でセッションの生存確認。
                // 起動直後は言語カタログの読み込みが間に合わず
                // unsupportedSourceLanguage で壊れたセッションになることがあるため、
                // その場合は少し待ってセッションを作り直す。
                print("[WT] task started")
                do {
                    let r = try await translate(session, "hello", timeoutSeconds: 3)
                    print("[WT] warmup ok: \(r)")
                    warmupRetryCount = 0
                } catch {
                    print("[WT] warmup error (retry \(warmupRetryCount)): \(error)")
                    if warmupRetryCount < 8 {
                        warmupRetryCount += 1
                        try? await Task.sleep(for: .seconds(0.5))
                        wordConfiguration?.invalidate()
                        return
                    }
                }

                for await target in wordBroker.requests() {
                    print("[WT] translating '\(target)'")
                    do {
                        let translated = try await translate(session, target, timeoutSeconds: 10)
                        print("[WT] translated '\(target)' -> \(translated)")
                        if selectedWord?.word == target {
                            wordJapanese = translated
                        }
                        saveWordCache(target, translated)
                    } catch {
                        print("[WT] translate error '\(target)': \(error)")
                        // セッション不良の可能性があるので、作り直して 1 回だけ再翻訳
                        if wordBroker.shouldRetry(target) {
                            print("[WT] retrying '\(target)' with new session")
                            wordBroker.stashForRetry(target)
                            wordConfiguration?.invalidate()
                            return
                        }
                        if selectedWord?.word == target {
                            wordFailed = true
                        }
                    }
                }
                print("[WT] task ended")
            }
            // 未翻訳ブロックは表示時に再翻訳を試みる
            .translationTask(retryConfiguration) { session in
                await retryTranslations(with: session)
            }
            .onAppear {
                startRetryTranslationIfNeeded()
                // 単語翻訳セッションを事前に確立しておく
                // (最初の単語タップ時にシートの裏でセッション初期化して固まるのを防ぐ)
                if wordConfiguration == nil {
                    wordConfiguration = TranslationSession.Configuration(
                        source: TranslationAvailability.english,
                        target: TranslationAvailability.japanese
                    )
                }
            }
        }
    }

    /// 選択モード中はタップで赤くハイライトし、通常時はいつも通りのカード
    @ViewBuilder
    private func blockRow(_ block: Block) -> some View {
        let isSelected = selection.contains(block.persistentModelID)
        ZStack {
            BlockCardView(
                block: block,
                isExpanded: expandedBlockIDs.contains(block.persistentModelID),
                onToggle: { toggle(block) },
                onWordTap: { word in
                    showWord(word)
                }
            )
            .allowsHitTesting(!isSelecting)

            if isSelecting {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.red.opacity(0.18) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.red : Color.clear, lineWidth: 2)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        if isSelected {
                            selection.remove(block.persistentModelID)
                        } else {
                            selection.insert(block.persistentModelID)
                        }
                    }
            }
        }
    }

    /// 単語の意味を表示: 内蔵辞書 → キャッシュ → Apple 翻訳の順で解決
    private func showWord(_ word: String) {
        print("[WT] tap word='\(word)'")
        wordJapanese = nil
        wordFailed = false
        selectedWord = SelectedWord(word: word)

        if let entry = BasicWordDictionary.lookup(word) {
            print("[WT] dict hit: \(entry)")
            wordJapanese = entry
            return
        }
        let target = word
        let descriptor = FetchDescriptor<WordCacheEntry>(
            predicate: #Predicate { $0.word == target }
        )
        if let cached = try? context.fetch(descriptor).first {
            print("[WT] cache hit: \(cached.japanese)")
            wordJapanese = cached.japanese
            return
        }
        print("[WT] no dict/cache -> requesting translation")
        wordBroker.request(word)
    }

    private func saveWordCache(_ word: String, _ translation: String) {
        let target = word
        let descriptor = FetchDescriptor<WordCacheEntry>(
            predicate: #Predicate { $0.word == target }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.japanese = translation
            existing.updatedAt = .now
        } else {
            context.insert(WordCacheEntry(word: target, japanese: translation))
        }
        try? context.save()
    }

    /// どこまで読んだかの目印。全体で 1 か所だけ(付け直すと移動、同じ場所なら解除)
    private func toggleMark(_ block: Block) {
        let wasMarked = block.isMarked
        for other in blocks where other.isMarked {
            other.isMarked = false
        }
        block.isMarked = !wasMarked
        try? context.save()
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

    private func deleteSelected() {
        let ids = selection
        let targets = blocks.filter { ids.contains($0.persistentModelID) }
        var affectedPassages: [PersistentIdentifier: Passage] = [:]
        for block in targets {
            if let passage = block.passage {
                affectedPassages[passage.persistentModelID] = passage
            }
            context.delete(block)
        }
        // ブロックがなくなった文章は本体ごと削除する
        for passage in affectedPassages.values {
            if passage.blocks.filter({ !ids.contains($0.persistentModelID) }).isEmpty {
                context.delete(passage)
            }
        }
        try? context.save()
        withAnimation {
            selection.removeAll()
            isSelecting = false
        }
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
