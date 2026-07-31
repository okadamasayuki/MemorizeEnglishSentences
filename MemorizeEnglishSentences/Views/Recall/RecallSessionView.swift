import SwiftData
import SwiftUI

/// タイトルを見て英文全文を音声で回答、または「答えを見る」。
/// タイトルはタップで編集でき、習熟ステータス(要復習/普通/覚えた!)を登録できる。
struct RecallSessionView: View {
    @Environment(\.modelContext) private var context
    @Bindable var passage: Passage

    @State private var speech = SpeechRecognitionService()
    @State private var showAnswer = false
    @State private var resultAttempt: RecallAttempt?
    @State private var showResult = false

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
                        ForEach(MemorizationStatus.allCases) { status in
                            statusButton(for: status)
                        }
                        Spacer()
                    }

                    Text(passage.japaneseFullText.isEmpty ? "(和訳がありません — 登録し直して翻訳してください)" : passage.japaneseFullText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showAnswer {
                        Text(referenceText)
                            .font(.body)
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
                // 音声で回答
                DictationButton(speech: speech, iconOnly: true)
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
        // ステータスに合わせて背景色をうっすら変える
        .background(passage.memorizationStatus.color.opacity(0.06).ignoresSafeArea())
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
        .onAppear {
            // 長文ディクテーション: final 後に自動再開してセグメント連結
            speech.autoRestart = true
        }
        .onDisappear {
            speech.stop()
            try? context.save()
        }
    }

    private func statusButton(for status: MemorizationStatus) -> some View {
        let isSelected = passage.memorizationStatus == status
        return Button {
            passage.memorizationStatus = status
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
