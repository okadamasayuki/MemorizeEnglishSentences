import SwiftData
import SwiftUI
import Translation

/// タイトルを見て英文全文を音声で回答、または「答えを見る」。
/// タイトルはタップで編集でき、習熟ステータス(要復習/どちらでもない/覚えた!)を登録できる。
struct RecallSessionView: View {
    @Environment(\.modelContext) private var context
    @Bindable var passage: Passage

    @State private var speech = SpeechRecognitionService()
    @State private var showAnswer = false
    @State private var resultAttempt: RecallAttempt?
    @State private var showResult = false

    // 単語長押しで和訳+発音
    @State private var selectedWord: SelectedWord?
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?

    private var referenceText: String {
        passage.englishFullText
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 習熟ステータス(アイコンで選択)
                    HStack(spacing: 44) {
                        Spacer()
                        // 「どちらでもない」はアイコンなし = どちらも未選択の状態
                        ForEach([MemorizationStatus.needsReview, .memorized]) { status in
                            statusButton(for: status)
                        }
                        Spacer()
                    }

                    Text(passage.japaneseFullText.isEmpty ? "(和訳がありません — 登録し直して翻訳してください)" : passage.japaneseFullText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showAnswer {
                        // 単語を長押しすると和訳の表示と発音の再生
                        FlowLayout(spacing: 5, lineSpacing: 8) {
                            ForEach(WordTokenizer.tokenize(referenceText)) { token in
                                Text(token.display)
                                    .font(.body)
                                    .onLongPressGesture {
                                        let word = token.normalized.isEmpty ? token.display : token.normalized
                                        SpeechSynthesisService.shared.speak(word)
                                        showWord(word)
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !speech.fullText.isEmpty || speech.isRecording {
                        Text(speech.fullText.isEmpty ? "..." : speech.fullText)
                            .font(.body)
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

            HStack(spacing: 44) {
                Spacer()
                // 言い直し(認識テキストを消して最初から)
                Button {
                    speech.restartClean()
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 38))
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
                        .font(.system(size: 38))
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
            // 長文ディクテーション: final 後に自動再開してセグメント連結
            speech.autoRestart = true
            // 正解英文の単語を認識バイアスとして渡し、正解に寄せて聞き取る
            let words = WordTokenizer.tokenize(referenceText)
                .map(\.normalized)
                .filter { $0.count >= 2 }
            speech.contextualStrings = Array(Set(words)).sorted()
        }
        .onDisappear {
            speech.stop()
            try? context.save()
        }
    }

    private func statusButton(for status: MemorizationStatus) -> some View {
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

    /// 単語の意味を表示: 内蔵辞書 → キャッシュ → Apple 翻訳の順で解決
    private func showWord(_ word: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)

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
