import SwiftData
import SwiftUI
import Translation

/// 長押しされた熟語(シート表示用)。例文中に現れた形も持つ
private struct SelectedIdiom: Identifiable {
    let id = UUID()
    let idiom: Idiom
    let surfaceForm: String
}

/// 熟語タブ(音読特化)。例文を読み上げながら熟語を覚える。
/// - 例文中の熟語部分は強調表示。長押しで「この文での意味+発音」
/// - それ以外の単語の長押しで文中での意味(音読タブと同じ事前生成キャッシュ)
/// - カードをタップで熟語+意味+和訳を表示(既定は隠して自己テスト)
/// - 左スワイプでしおり(全体1か所)、右スワイプで削除
struct IdiomListView: View {
    @Environment(\.modelContext) private var context
    /// 全熟語(番号順)。@Query にすると、このタブを一度開いた後は
    /// アプリ内のどんな保存(しおり自動保存など)でも1000件を再取得してしまい、
    /// アプリ全体が遅くなる。表示時に一度だけ手動で読み込む
    /// (カード内の変化は Observation が行単位で拾うので一覧の再取得は不要。
    ///  追加取り込みは起動時=読み込み前に終わっている)。
    @State private var allIdioms: [Idiom] = []
    /// 意味を表示中のカード番号
    @State private var revealed: Set<Int> = []
    /// 選択中の級(セグメント)。未選択時は最初の級
    @AppStorage("idiomSelectedLevel") private var storedLevel = ""
    /// 表示中の元スクショ
    @State private var sourceImage: IdentifiableImage?
    @State private var scrollProxy: ScrollViewProxy?

    // 熟語の意味シート
    @State private var selectedIdiom: SelectedIdiom?

    // 単語長押し(音読タブと同じ仕組み)
    @State private var selectedWord: SelectedWord?
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?

    /// 登録されている級の一覧(易→難: 2級→準1級→1級)。
    /// 読み込み時に1回だけ計算して保持する。computed にすると、ツールバーの
    /// 級Pickerの Binding(get:) からレイアウトのたびに何千回も呼ばれ、
    /// 1000件走査(1.3ms)×数千回=タブ切替のたびに数秒のフリーズになっていた。
    @State private var levels: [String] = []

    private func computeLevels() {
        var seen: [String] = []
        for idiom in allIdioms where !seen.contains(idiom.level) {
            seen.append(idiom.level)
        }
        let order = ["2級", "準1級", "1級"]
        levels = seen.sorted { a, b in
            let ia = order.firstIndex(of: a) ?? order.count
            let ib = order.firstIndex(of: b) ?? order.count
            return ia == ib ? a < b : ia < ib
        }
    }

    private var effectiveLevel: String {
        levels.contains(storedLevel) ? storedLevel : (levels.first ?? "")
    }

    /// 表示対象(選択中の級だけ)
    private var idioms: [Idiom] {
        PerfLog.measure("idioms filter") {
            allIdioms.filter { $0.level == effectiveLevel }
        }
    }

    /// 読み込みが済んだか(済む前に「まだありません」を出さないため)
    @State private var didLoad = false

    /// 全熟語を一度だけ読み込む(取り込みは起動時に終わっているので以後の再取得は不要)
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        PerfLog.measure("idiom fetch") {
            let descriptor = FetchDescriptor<Idiom>(sortBy: [SortDescriptor(\.number)])
            allIdioms = (try? context.fetch(descriptor)) ?? []
            computeLevels()
        }
    }

    var body: some View {
        let _ = PerfLog.log("IdiomListView body")
        NavigationStack {
            Group {
                if !didLoad {
                    ProgressView()
                        .onAppear { loadIfNeeded() }
                } else if allIdioms.isEmpty {
                    ContentUnavailableView(
                        "熟語がまだありません",
                        systemImage: "text.book.closed",
                        description: Text("Macから熟語データを取り込むと、ここで音読学習できます。")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            // 識別子は「番号」に統一する。行に別系統の .id() を振ると、
                            // List が全行のIDを知るために300行を毎回組み立ててしまい、
                            // タブに入るたび約5秒・出るたび約3秒フリーズしていた
                            // (しおりへの scrollTo はこの番号識別子で動く)。
                            ForEach(idioms, id: \.number) { idiom in
                                card(idiom)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    // 左スワイプでしおりの付け外し(全体で1か所)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            toggleBookmark(idiom)
                                        } label: {
                                            Image(systemName: idiom.isBookmarked ? "bookmark.slash" : "bookmark.fill")
                                        }
                                        .tint(.orange)
                                    }
                                    // 右スワイプで削除(手動読み込みの一覧からも取り除く)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            revealed.remove(idiom.number)
                                            allIdioms.removeAll { $0.persistentModelID == idiom.persistentModelID }
                                            context.delete(idiom)
                                            try? context.save()
                                            computeLevels()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .contentMargins(.top, 10, for: .scrollContent)
                        .onAppear {
                            scrollProxy = proxy
                            PerfLog.log("idiom list appeared (\(idioms.count) rows)")
                            restoreBookmarkIfNeeded(proxy)
                        }
                    }
                }
            }
            .navigationTitle("熟語")
            .navigationBarTitleDisplayMode(.inline)
            // 級を切り替えたら「意味を表示中」状態をリセットする
            // (番号は級をまたいで重複しうるため、他の級に持ち越さない)
            .onChange(of: effectiveLevel) { _, _ in
                revealed.removeAll()
            }
            .toolbar {
                // しおりへジャンプ
                if let marked = idioms.first(where: { $0.isBookmarked }) {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation { scrollProxy?.scrollTo(marked.number, anchor: .center) }
                        } label: {
                            Image(systemName: "bookmark.fill").foregroundStyle(.orange)
                        }
                    }
                }
                // 級の切り替え(複数の級があるときだけ)
                if levels.count > 1 {
                    ToolbarItem(placement: .principal) {
                        Picker("級", selection: Binding(
                            get: { effectiveLevel },
                            set: { storedLevel = $0 }
                        )) {
                            ForEach(levels, id: \.self) { level in
                                Text(level).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }
                }
            }
            .sheet(item: $selectedIdiom) { selected in
                IdiomPopupView(idiom: selected.idiom, surfaceForm: selected.surfaceForm)
            }
            .sheet(item: $selectedWord) { selected in
                WordPopupView(word: selected.word, meaning: wordMeaning)
            }
            .sheet(item: $sourceImage) { item in
                SourceImageView(image: item.image)
            }
            // 単語の翻訳(常駐セッション 1 本に、長押しされた単語を流し込む)。
            // 事前生成キャッシュにない単語だけがここに来る
            .translationTask(wordConfiguration) { session in
                do {
                    _ = try await translate(session, "hello", timeoutSeconds: 3)
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
                        if selectedWord?.word == target { wordMeaning.japanese = translated }
                        saveWordCache(target, translated)
                    } catch {
                        if wordBroker.shouldRetry(target) {
                            wordBroker.stashForRetry(target)
                            wordConfiguration?.invalidate()
                            return
                        }
                        if selectedWord?.word == target { wordMeaning.failed = true }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ idiom: Idiom) -> some View {
        IdiomCardView(
            idiom: idiom,
            isRevealed: revealed.contains(idiom.number),
            onToggle: { toggle(idiom) },
            onWordTap: { word, occurrence, isIdiomPart in
                if isIdiomPart {
                    showIdiom(idiom)
                } else {
                    showWord(word, occurrence: occurrence, sentenceContext: idiom.example)
                }
            },
            onSpeak: { SpeechSynthesisService.shared.speak(idiom.example) },
            onShowSource: PageImageStore.hasImage(forBlockText: idiom.example)
                ? { sourceImage = PageImageStore.image(forBlockText: idiom.example).map(IdentifiableImage.init) }
                : nil
        )
        .equatable()
    }

    private func toggle(_ idiom: Idiom) {
        if revealed.contains(idiom.number) {
            revealed.remove(idiom.number)
        } else {
            revealed.insert(idiom.number)
        }
    }

    /// 例文中に現れた形(熟語トークンをつないだもの)で熟語シートを出す
    private func showIdiom(_ idiom: Idiom) {
        let tokens = WordTokenizer.tokenize(idiom.example)
        let surface = idiom.idiomTokenIndexes.sorted().compactMap { index -> String? in
            guard tokens.indices.contains(index) else { return nil }
            let token = tokens[index]
            // 表示形から前後の句読点だけ落とす(大文字は保つ)
            let trimmed = token.display.trimmingCharacters(
                in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’")).inverted
            )
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: " ")
        selectedIdiom = SelectedIdiom(idiom: idiom, surfaceForm: surface)
    }

    /// 単語の意味を表示。事前生成した「この文中での意味」を最優先し、
    /// なければ内蔵辞書 → キャッシュ → Apple 翻訳で解決する(音読タブと同じ)
    private func showWord(_ word: String, occurrence: Int, sentenceContext: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)

        if let cached = WordSenseLookup.cached(word: word, occurrence: occurrence, blockText: sentenceContext, modelContext: context) {
            wordMeaning.apply(cached)
            return
        }
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
        if wordConfiguration == nil {
            wordConfiguration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
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

    /// 起動後の初回表示時に、しおりの位置まで自動スクロールする
    /// (識別子を番号に統一したので、音読タブと同じく全行構築なしで飛べる)
    @State private var didRestore = false
    private func restoreBookmarkIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didRestore else { return }
        didRestore = true
        guard let marked = idioms.first(where: { $0.isBookmarked }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            proxy.scrollTo(marked.number, anchor: .center)
        }
    }

    /// しおりは全体で1か所。付け直すと移動、同じ場所なら解除
    private func toggleBookmark(_ idiom: Idiom) {
        let wasBookmarked = idiom.isBookmarked
        for other in allIdioms where other.isBookmarked {
            other.isBookmarked = false
        }
        idiom.isBookmarked = !wasBookmarked
        try? context.save()
    }

}
