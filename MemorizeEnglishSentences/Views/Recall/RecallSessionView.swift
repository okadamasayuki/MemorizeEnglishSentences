import SwiftData
import SwiftUI

/// 日本語訳だけを全文表示 → 音声入力で英文全文を一気に回答、または「答えを見る」
struct RecallSessionView: View {
    @Environment(\.modelContext) private var context
    let passage: Passage

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
                    Text("日本語訳")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(passage.japaneseFullText.isEmpty ? "(和訳がありません — 音読タブで翻訳してください)" : passage.japaneseFullText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showAnswer {
                        Divider()
                        Text("正解英文")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(referenceText)
                            .font(.body)
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !speech.fullText.isEmpty || speech.isRecording {
                        Divider()
                        Text("認識中のテキスト")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    DictationButton(speech: speech, label: "音声で回答")

                    Button {
                        showAnswer.toggle()
                    } label: {
                        Label(showAnswer ? "答えを隠す" : "答えを見る", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    confirmAnswer()
                } label: {
                    Text("回答を確定して採点")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentAnswer.isEmpty)
            }
            .padding()
        }
        .navigationTitle(passage.title)
        .navigationBarTitleDisplayMode(.inline)
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
        }
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
