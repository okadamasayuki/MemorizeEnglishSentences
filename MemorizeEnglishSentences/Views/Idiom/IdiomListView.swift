import SwiftData
import SwiftUI
import Translation

/// 熟語タブ。熟語+例文を表示し、タップすると熟語の横に意味、英文の下に和訳を表示するカード。
/// 熟語・例文の単語長押しで意味+発音、元スクショ、しおり(左スワイプ)・削除(右スワイプ)。
struct IdiomListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Idiom.number) private var idioms: [Idiom]
    /// 意味を表示中のカード
    @State private var revealed: Set<Int> = []
    /// 表示中の元スクショ
    @State private var sourceImage: IdentifiableImage?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var didRestore = false

    // 単語長押し(音読タブと同じ仕組み)
    @State private var selectedWord: SelectedWord?
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?

    var body: some View {
        NavigationStack {
            Group {
                if idioms.isEmpty {
                    ContentUnavailableView(
                        "熟語がまだありません",
                        systemImage: "text.book.closed",
                        description: Text("写真から熟語を取り込むと、ここでカード学習できます。")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(idioms) { idiom in
                                card(idiom)
                                    .id(idiom.number)
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
                                    // 右スワイプで削除
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            revealed.remove(idiom.number)
                                            context.delete(idiom)
                                            try? context.save()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        // 一番上に少し余白を足す
                        .contentMargins(.top, 12, for: .scrollContent)
                        .onAppear {
                            scrollProxy = proxy
                            restoreBookmarkIfNeeded(proxy)
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
            }
            .sheet(item: $selectedWord) { selected in
                WordPopupView(word: selected.word, meaning: wordMeaning)
            }
            .sheet(item: $sourceImage) { item in
                SourceImageView(image: item.image)
            }
            // 単語の翻訳(常駐セッション 1 本に、長押しされた単語を流し込む)
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
            .onAppear {
                if wordConfiguration == nil {
                    wordConfiguration = TranslationSession.Configuration(
                        source: TranslationAvailability.english,
                        target: TranslationAvailability.japanese
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ idiom: Idiom) -> some View {
        let isRevealed = revealed.contains(idiom.number)
        VStack(alignment: .leading, spacing: 8) {
            // 熟語(単語長押し可) + (タップで)横に意味 + しおり/元スクショ(縦中心をそろえる)
            HStack(alignment: .center, spacing: 10) {
                // 熟語の見出し。長押しで熟語の意味+発音
                Text(idiom.phrase)
                    .font(.title3.bold())
                    .onLongPressGesture { showIdiomMeaning(idiom) }
                if isRevealed {
                    Text(idiom.meaning)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if idiom.isBookmarked {
                    Image(systemName: "bookmark.fill").font(.subheadline).foregroundStyle(.orange)
                }
                if PageImageStore.hasImage(forBlockText: idiom.example) {
                    Button {
                        sourceImage = PageImageStore.image(forBlockText: idiom.example).map(IdentifiableImage.init)
                    } label: {
                        Image(systemName: "photo").font(.subheadline).foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // 例文(単語長押しで意味+発音。熟語の一部を長押ししたら熟語の意味を表示)
            exampleTokens(idiom)

            // 英文の和訳(タップで英文の下に表示)
            if isRevealed, !idiom.exampleJa.isEmpty {
                Text(idiom.exampleJa)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        // タップで意味の表示/非表示(モーションなし)
        .onTapGesture {
            if isRevealed { revealed.remove(idiom.number) } else { revealed.insert(idiom.number) }
        }
    }

    /// 例文を、単語ごとに長押しできるトークンとして折り返し表示する。
    /// 熟語の一部(見出しの語)は太字にし、長押しで熟語の意味を表示する。
    @ViewBuilder
    private func exampleTokens(_ idiom: Idiom) -> some View {
        let keys = idiomKeys(idiom.phrase)
        FlowLayout(spacing: 4, lineSpacing: 6) {
            ForEach(WordTokenizer.tokenize(idiom.example)) { token in
                let word = token.normalized
                let isIdiom = isIdiomWord(word, keys)
                Text(token.display)
                    .font(.subheadline)
                    .fontWeight(isIdiom ? .bold : .regular)
                    .onLongPressGesture {
                        if word.count >= 2, word.contains(where: { $0.isLetter }) {
                            showWord(word, in: idiom.example)
                        }
                    }
            }
        }
    }

    /// 熟語見出しの構成語(~ / A / B などのプレースホルダーは除く)
    private func idiomKeys(_ phrase: String) -> [String] {
        phrase.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    /// 例文のこの語が熟語の一部か(語尾変化を許容してマッチ)
    private func isIdiomWord(_ token: String, _ keys: [String]) -> Bool {
        guard token.count >= 2 else { return false }
        return keys.contains { key in
            token == key
                || (key.count >= 3 && token.hasPrefix(key))   // bail→bailing, act→acting
                || (token.count >= 3 && key.hasPrefix(token))  // 念のため逆向きも
        }
    }

    /// 熟語の見出し長押し: 熟語の意味(そのまま)と発音を表示する
    private func showIdiomMeaning(_ idiom: Idiom) {
        wordMeaning.reset()
        wordMeaning.japanese = idiom.meaning
        selectedWord = SelectedWord(word: idiom.phrase)
    }

    /// 単語の意味を表示(音読タブと同じ: 事前生成の文脈キャッシュ→内蔵辞書→Apple翻訳)。
    /// 例文中の熟語部分は文脈キャッシュに熟語形の訳が入っているので、それが表示される。
    private func showWord(_ word: String, in example: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)
        if let cached = WordSenseLookup.cached(word: word, blockText: example, modelContext: context) {
            wordMeaning.apply(cached)
            return
        }
        if let entry = BasicWordDictionary.lookup(word) {
            wordMeaning.japanese = entry
            return
        }
        wordBroker.request(word)
    }

    /// しおりを付け替える(全体で1か所)
    private func toggleBookmark(_ idiom: Idiom) {
        let wasMarked = idiom.isBookmarked
        for other in idioms where other.isBookmarked { other.isBookmarked = false }
        idiom.isBookmarked = !wasMarked
        try? context.save()
    }

    /// 起動後、しおり位置へ一度だけスクロールする
    private func restoreBookmarkIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didRestore else { return }
        didRestore = true
        guard let marked = idioms.first(where: { $0.isBookmarked }) else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation { proxy.scrollTo(marked.number, anchor: .center) }
        }
    }
}
