import SwiftData
import SwiftUI
import Translation

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
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?
    @State private var retryConfiguration: TranslationSession.Configuration?
    @State private var isSelecting = false
    @State private var selection = Set<PersistentIdentifier>()
    @State private var scrollProxy: ScrollViewProxy?
    /// 表示中の元スクショ(nil = 非表示)
    @State private var sourceImage: IdentifiableImage?
    /// 画面中央付近にあるブロック(現在位置の表示・しおりの自動更新に使う)
    @State private var currentBlockID: PersistentIdentifier?
    /// 起動後に前回位置(しおり)へ一度だけスクロールしたか
    @State private var didRestore = false

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
                                    // 各行の画面上の位置を報告(中央に一番近い行を現在位置とする)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: BlockCenterKey.self,
                                                value: [block.persistentModelID: geo.frame(in: .global).midY]
                                            )
                                        }
                                    )
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
                        // 選択モード中は背景色を少し変えてわかるようにする
                        .scrollContentBackground(.hidden)
                        .background(isSelecting ? Color.red.opacity(0.07) : Color(.systemBackground))
                        .animation(.easeInOut(duration: 0.2), value: isSelecting)
                        // 中央に最も近い行を現在位置として更新する
                        .onPreferenceChange(BlockCenterKey.self) { positions in
                            updateCurrentBlock(from: positions)
                        }
                        .onAppear {
                            scrollProxy = proxy
                            restoreLastPositionIfNeeded(proxy)
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
                    // 現在位置(240件中 N件目)
                    if !isSelecting {
                        ToolbarItem(placement: .principal) {
                            Text("\(blocks.count)件中 \(currentPositionText)件目")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
                WordPopupView(word: selected.word, meaning: wordMeaning)
            }
            .sheet(item: $sourceImage) { item in
                SourceImageView(image: item.image)
            }
            // スクロールが落ち着いたら現在位置のブロックにしおりを保存する(書き込み過多を防ぐ)
            .task(id: currentBlockID) {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                persistBookmark()
            }
            // 単語の翻訳(常駐セッション 1 本に、タップされた単語をストリームで流し込む)
            .translationTask(wordConfiguration) { session in
                // ダミー翻訳でセッションの生存確認。
                // 起動直後は言語カタログの読み込みが間に合わず
                // unsupportedSourceLanguage で壊れたセッションになることがあるため、
                // その場合は少し待ってセッションを作り直す。
                do {
                    let r = try await translate(session, "hello", timeoutSeconds: 3)
                    warmupRetryCount = 0
                } catch {
                    if warmupRetryCount < 8 {
                        warmupRetryCount += 1
                        try? await Task.sleep(for: .seconds(0.5))
                        wordConfiguration?.invalidate()
                        return
                    }
                }

                for await target in wordBroker.requests() {
                    do {
                        let translated = try await translate(session, target, timeoutSeconds: 10)
                        if selectedWord?.word == target {
                            wordMeaning.japanese = translated
                        }
                        saveWordCache(target, translated)
                    } catch {
                        // セッション不良の可能性があるので、作り直して 1 回だけ再翻訳
                        if wordBroker.shouldRetry(target) {
                            wordBroker.stashForRetry(target)
                            wordConfiguration?.invalidate()
                            return
                        }
                        if selectedWord?.word == target {
                            wordMeaning.failed = true
                        }
                    }
                }
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
                onWordTap: { word, occurrence in
                    showWord(word, occurrence: occurrence, sentenceContext: block.englishText)
                },
                sentencePairs: SentencePairLookup.cached(blockText: block.englishText, modelContext: context),
                onShowSource: PageImageStore.hasImage(forBlockText: block.englishText)
                    ? { sourceImage = PageImageStore.image(forBlockText: block.englishText).map(IdentifiableImage.init) }
                    : nil
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

    /// 単語の意味を表示。Claude Code が事前生成した「その文中での意味」を最優先し、
    /// キャッシュにない単語は内蔵辞書 → キャッシュ → Apple 翻訳で解決する
    private func showWord(_ word: String, occurrence: Int, sentenceContext: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)

        // 事前生成済みの「この文中での意味」があれば最優先(無料・オフライン)
        if let cached = WordSenseLookup.cached(word: word, occurrence: occurrence, blockText: sentenceContext, modelContext: context) {
            wordMeaning.apply(cached)
            return
        }
        legacyLookup(word)
    }

    /// 従来の解決手段: 内蔵辞書 → キャッシュ → Apple 翻訳
    private func legacyLookup(_ word: String) {
        if let entry = BasicWordDictionary.lookup(word) {
            wordMeaning.japanese = entry
            return
        }
        let target = word
        let descriptor = FetchDescriptor<WordCacheEntry>(
            predicate: #Predicate { $0.word == target }
        )
        if let cached = try? context.fetch(descriptor).first {
            wordMeaning.japanese = cached.japanese
            return
        }
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
    /// 現在位置の表示に使う番号(1始まり)。未確定のときは 1
    private var currentPositionText: String {
        guard let id = currentBlockID,
              let index = blocks.firstIndex(where: { $0.persistentModelID == id }) else { return "1" }
        return "\(index + 1)"
    }

    /// 各行の中央 Y から、画面中央に一番近い行を現在位置として選ぶ
    private func updateCurrentBlock(from positions: [PersistentIdentifier: CGFloat]) {
        guard !positions.isEmpty else { return }
        let screenCenter = UIScreen.main.bounds.height / 2
        let nearest = positions.min { abs($0.value - screenCenter) < abs($1.value - screenCenter) }
        if let id = nearest?.key, id != currentBlockID {
            currentBlockID = id
        }
    }

    /// 現在位置のブロックにしおりを自動で付け替える(1か所だけ)
    private func persistBookmark() {
        guard let id = currentBlockID,
              let target = blocks.first(where: { $0.persistentModelID == id }) else { return }
        var changed = false
        for block in blocks where block.isMarked && block.persistentModelID != id {
            block.isMarked = false
            changed = true
        }
        if !target.isMarked {
            target.isMarked = true
            changed = true
        }
        if changed { try? context.save() }
    }

    /// 起動後、前回のしおり位置へ一度だけスクロールする
    private func restoreLastPositionIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didRestore else { return }
        didRestore = true
        guard let marked = blocks.first(where: { $0.isMarked }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation { proxy.scrollTo(marked.persistentModelID, anchor: .center) }
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

/// 各ブロックの画面上の中央 Y を集める PreferenceKey(現在位置の判定に使う)
private struct BlockCenterKey: PreferenceKey {
    static let defaultValue: [PersistentIdentifier: CGFloat] = [:]
    static func reduce(value: inout [PersistentIdentifier: CGFloat], nextValue: () -> [PersistentIdentifier: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
