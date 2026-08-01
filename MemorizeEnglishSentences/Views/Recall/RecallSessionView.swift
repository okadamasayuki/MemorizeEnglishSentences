import SwiftData
import SwiftUI
import Translation

/// タイトルを見て英文全文を音声で回答、または「答えを見る」。
/// タイトルはタップで編集でき、習熟ステータス(要復習/どちらでもない/覚えた!)を登録できる。
struct RecallSessionView: View {
    @Environment(\.modelContext) private var context

    /// 一覧から開いた文章
    private let initialPassage: Passage

    // スワイプでの前後移動用に、一覧と同じ並び・絞り込みの文章リストを持つ
    private static let sortOrder: [SortDescriptor<Passage>] = [
        SortDescriptor(\Passage.sortIndex),
        SortDescriptor(\Passage.createdAt, order: .reverse),
    ]
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "recall" },
        sort: sortOrder
    ) private var allPassages: [Passage]
    @AppStorage("hideMemorized") private var hideMemorized = false

    init(passage: Passage) {
        self.initialPassage = passage
    }

    /// ページングで表示する文章のスナップショット(開いた時点の並び・絞り込み)
    @State private var pages: [Passage] = []
    /// いま表示しているページの文章 ID
    @State private var selectedID: PersistentIdentifier?

    @State private var speech = SpeechRecognitionService()
    @State private var showAnswer = false
    @State private var resultAttempt: RecallAttempt?
    @State private var showResult = false

    // ヒント: 文中の重要単語(キーワード)だけを語順どおりに表示
    @State private var showHint = false
    @State private var hintKeywords: [String] = []

    // 単語長押しで和訳+発音
    @State private var selectedWord: SelectedWord?
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?

    private var passage: Passage {
        pages.first { $0.persistentModelID == selectedID } ?? initialPassage
    }

    private var referenceText: String {
        passage.englishFullText
    }

    var body: some View {
        VStack(spacing: 0) {
            // ページをめくるように指に追従してスワイプで前後の文章へ移動できる
            TabView(selection: $selectedID) {
                ForEach(pages) { page in
                    pageView(page)
                        .tag(Optional(page.persistentModelID))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: selectedID) {
                // ページが替わったら回答・答え・ヒントをリセットして認識バイアスを合わせ直す
                speech.stop()
                speech.reset()
                showAnswer = false
                showHint = false
                hintKeywords = []
                configureSpeech()
            }

            HStack(spacing: 44) {
                Spacer()
                // 言い直し(認識テキストを消して最初から)
                Button {
                    speech.restartClean()
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(speech.fullText.isEmpty ? Color(.systemGray3) : Color.orange)
                }
                .buttonStyle(.borderless)
                .disabled(speech.fullText.isEmpty)
                // 音声で回答
                DictationButton(speech: speech, iconOnly: true)
                // 回答を確定して採点
                Button {
                    confirmAnswer()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(currentAnswer.isEmpty ? Color(.systemGray3) : Color.green)
                }
                .buttonStyle(.borderless)
                .disabled(currentAnswer.isEmpty)
                Spacer()
            }
            .padding()
        }
        // ステータスに合わせて背景色をうっすら変える(どちらでもない = 色なし)
        .background(
            (passage.memorizationStatus == .normal
                ? Color.clear
                : passage.memorizationStatus.color.opacity(0.06))
                .ignoresSafeArea()
        )
        .animation(.easeInOut(duration: 0.25), value: passage.memorizationStatus)
        .navigationBarTitleDisplayMode(.inline)
        // 暗記中は下のタブバーを隠す
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // ヒント(文中のキーワードだけを語順どおりに表示)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if !showHint {
                            hintKeywords = buildHintKeywords()
                        }
                        showHint.toggle()
                    }
                } label: {
                    Image(systemName: showHint ? "lightbulb.fill" : "lightbulb")
                        .foregroundStyle(showHint ? Color.yellow : Color.accentColor)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    MistakeAnalysisView(passage: passage)
                } label: {
                    Label("分析", systemImage: "chart.bar.fill")
                }
            }
        }
        .navigationDestination(isPresented: $showResult) {
            if let resultAttempt {
                RecallDiffView(attempt: resultAttempt)
            }
        }
        .sheet(item: $selectedWord) { selected in
            WordPopupView(word: selected.word, meaning: wordMeaning)
        }
        // 単語の翻訳(常駐セッション 1 本に、長押しされた単語をストリームで流し込む)
        .translationTask(wordConfiguration) { session in
            // ダミー翻訳でセッションの生存確認。起動直後は壊れたセッションに
            // なることがあるため、その場合は少し待って作り直す。
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
        .onAppear {
            // 単語翻訳セッションを事前に確立しておく
            if wordConfiguration == nil {
                wordConfiguration = TranslationSession.Configuration(
                    source: TranslationAvailability.english,
                    target: TranslationAvailability.japanese
                )
            }
            // ページ一覧のスナップショット(一覧と同じ並び・絞り込み)を作る
            if pages.isEmpty {
                var list = allPassages
                if hideMemorized {
                    let filtered = list.filter { $0.memorizationStatus != .memorized }
                    // 開いた文章が絞り込みで消える場合は全件で表示する
                    if filtered.contains(where: { $0.persistentModelID == initialPassage.persistentModelID }) {
                        list = filtered
                    }
                }
                pages = list.isEmpty ? [initialPassage] : list
                selectedID = initialPassage.persistentModelID
            }
            configureSpeech()
        }
        .onDisappear {
            speech.stop()
            try? context.save()
        }
    }

    /// 1 ページ分(1 文章分)の表示
    private func pageView(_ page: Passage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 習熟ステータス(アイコンで選択)
                HStack(spacing: 44) {
                    Spacer()
                    // 「どちらでもない」はアイコンなし = どちらも未選択の状態
                    ForEach([MemorizationStatus.needsReview, .memorized]) { status in
                        statusButton(for: status, of: page)
                    }
                    Spacer()
                }

                // 歩きながらでも読みやすいよう、本文はすべて大きめの文字にする。
                // 日本語が変なところで折り返されないよう行末まで詰めて表示する
                NaturalWrapText(text: page.japaneseFullText.isEmpty ? "(和訳がありません — 登録し直して翻訳してください)" : page.japaneseFullText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showHint {
                    Text(hintKeywords.joined(separator: " ・ "))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if showAnswer {
                    // 単語を長押しすると和訳を表示(無音。発音はシート内のボタンで再生)
                    FlowLayout(spacing: 6, lineSpacing: 10) {
                        ForEach(WordTokenizer.tokenize(page.englishFullText)) { token in
                            Text(token.display)
                                .font(.title3)
                                .onLongPressGesture {
                                    let word = token.normalized.isEmpty ? token.display : token.normalized
                                    showWord(word, sentenceContext: page.englishFullText)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !speech.fullText.isEmpty || speech.isRecording {
                    Text(speech.fullText.isEmpty ? "..." : speech.fullText)
                        .font(.title3)
                        .lineSpacing(4)
                        .foregroundStyle(speech.isRecording ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = speech.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        // 余白をタップすると答えを表示/非表示
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                showAnswer.toggle()
            }
        }
    }

    private func statusButton(for status: MemorizationStatus, of passage: Passage) -> some View {
        let isSelected = passage.memorizationStatus == status
        return Button {
            // 選択中をもう一度タップすると解除(どちらでもない)に戻る
            passage.memorizationStatus = isSelected ? .normal : status
            try? context.save()
        } label: {
            Image(systemName: status.iconName)
                .font(.system(size: 26))
                .foregroundStyle(isSelected ? status.color : Color(.systemGray3))
                .scaleEffect(isSelected ? 1.15 : 1.0)
        }
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var currentAnswer: String {
        speech.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 現在の文章に合わせて音声認識を設定する
    private func configureSpeech() {
        // 長文ディクテーション: final 後に自動再開してセグメント連結
        speech.autoRestart = true
        // 正解英文の単語を認識バイアスとして渡し、正解に寄せて聞き取る
        let words = WordTokenizer.tokenize(referenceText)
            .map(\.normalized)
            .filter { $0.count >= 2 }
        speech.contextualStrings = Array(Set(words)).sorted()
    }


    /// 冠詞・代名詞・前置詞などの機能語(キーワードにしない語)
    private static let functionWords: Set<String> = [
        "a", "an", "the",
        "i", "you", "he", "she", "it", "we", "they",
        "me", "him", "her", "us", "them",
        "my", "your", "his", "its", "our", "their", "mine", "yours",
        "myself", "yourself", "himself", "herself", "itself", "ourselves", "themselves",
        "this", "that", "these", "those", "there", "here",
        "is", "am", "are", "was", "were", "be", "been", "being",
        "do", "does", "did", "done", "doing",
        "have", "has", "had", "having",
        "will", "would", "can", "could", "should", "shall", "may", "might", "must",
        "and", "or", "but", "so", "because", "if", "when", "while", "as", "than", "then",
        "to", "of", "in", "on", "at", "by", "for", "with", "from", "about",
        "into", "over", "under", "after", "before", "between", "through",
        "out", "up", "down", "off", "not", "no", "nor",
        "who", "whom", "whose", "what", "which", "how", "where", "why", "whether",
        "some", "any", "such", "only", "just", "also", "too", "very",
        "don't", "doesn't", "didn't", "won't", "wouldn't", "can't", "couldn't",
        "shouldn't", "isn't", "aren't", "wasn't", "weren't", "you'll", "i'm", "it's",
    ]

    /// ヒント用キーワード: 機能語を除いた重要単語を、語順を保ったまま最大 5 個選ぶ
    private func buildHintKeywords() -> [String] {
        let candidates = WordTokenizer.tokenize(referenceText).filter { token in
            let word = token.normalized.isEmpty ? token.display.lowercased() : token.normalized
            return !Self.functionWords.contains(word) && word.count >= 2
        }
        let maxCount = 5
        guard candidates.count > maxCount else {
            return candidates.map(keywordDisplay)
        }
        // 文全体にまんべんなく散らばるように等間隔で選ぶ
        let picked = (0..<maxCount).map { index in
            candidates[index * (candidates.count - 1) / (maxCount - 1)]
        }
        return picked.map(keywordDisplay)
    }

    /// キーワードの表示形: 末尾の句読点などを取り除く
    private func keywordDisplay(_ token: WordToken) -> String {
        token.display.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    /// 単語の意味を表示。事前生成済みの「この文中での意味」を最優先し、
    /// なければ APIキー設定時はその場で取得、それ以外は従来手段で解決する
    private func showWord(_ word: String, sentenceContext: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)

        if let cached = WordSenseLookup.cached(word: word, blockText: sentenceContext, modelContext: context) {
            wordMeaning.apply(cached)
            return
        }
        if ClaudeAPIService.isConfigured {
            Task {
                let sense = await WordSenseLookup.fetch(word: word, blockText: sentenceContext, modelContext: context)
                guard selectedWord?.word == word else { return }
                if let sense {
                    wordMeaning.apply(sense)
                } else {
                    legacyLookup(word)
                }
            }
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

    private func confirmAnswer() {
        speech.stop()
        let answer = currentAnswer
        guard !answer.isEmpty else { return }

        let refTokens = WordTokenizer.tokenize(referenceText)
        let hypTokens = WordTokenizer.tokenize(answer)
        let diff = DiffService.diff(
            reference: refTokens.map(\.normalized),
            hypothesis: hypTokens.map(\.normalized)
        )

        let attempt = RecallAttempt(
            recognizedText: answer,
            opsJSON: DiffService.encode(diff),
            accuracy: diff.accuracy
        )
        attempt.passage = passage
        context.insert(attempt)
        try? context.save()

        speech.reset()
        resultAttempt = attempt
        showResult = true
    }
}
