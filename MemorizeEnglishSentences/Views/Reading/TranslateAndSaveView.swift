import SwiftData
import SwiftUI
import Translation

/// ③ 一括翻訳の進捗をライブ表示 → 保存。失敗時は「翻訳せずに保存」を提示。
struct TranslateAndSaveView: View {
    @Environment(\.modelContext) private var context

    let title: String
    let sentences: [String]
    let purpose: PassagePurpose
    let onDone: () -> Void

    @State private var configuration: TranslationSession.Configuration?
    @State private var translations: [Int: String] = [:]
    @State private var isTranslating = false
    @State private var finished = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(sentences.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sentences[index])
                            .font(.subheadline)
                        if let translation = translations[index] {
                            Text(translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else if isTranslating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("未翻訳")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isTranslating {
                    ProgressView("翻訳中... (\(translations.count)/\(sentences.count))")
                        .frame(maxWidth: .infinity)
                } else if finished {
                    Button {
                        save(withTranslations: true)
                    } label: {
                        Text("保存")
                            .padding(.horizontal, 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        startTranslation()
                    } label: {
                        Text(errorMessage == nil ? "翻訳を開始" : "翻訳を再試行")
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
        .translationTask(configuration) { session in
            await translateAll(with: session)
        }
        .onAppear {
            startTranslation()
        }
    }

    private func startTranslation() {
        errorMessage = nil
        if configuration == nil {
            configuration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
        } else {
            // 再実行は invalidate() で新しいセッションを要求する
            configuration?.invalidate()
        }
    }

    private func translateAll(with session: TranslationSession) async {
        isTranslating = true
        defer { isTranslating = false }
        do {
            // 言語データ未ダウンロードならダウンロード確認を表示
            try await session.prepareTranslation()

            // 一括翻訳は順序不定 → clientIdentifier にブロック index を入れて対応付け
            let requests = sentences.enumerated().map { index, sentence in
                TranslationSession.Request(sourceText: sentence, clientIdentifier: "\(index)")
            }
            for try await response in session.translate(batch: requests) {
                if let identifier = response.clientIdentifier, let index = Int(identifier) {
                    translations[index] = response.targetText
                }
            }
            finished = true
        } catch {
            errorMessage = "翻訳に失敗しました。言語データのダウンロード状況やシミュレータでないことを確認してください。(\(error.localizedDescription))"
        }
    }

    private func save(withTranslations: Bool) {
        let passage = Passage(title: title)
        passage.purpose = purpose
        context.insert(passage)
        for (index, sentence) in sentences.enumerated() {
            let block = Block(
                index: index,
                englishText: sentence,
                japaneseText: withTranslations ? translations[index] : nil
            )
            block.passage = passage
            context.insert(block)
        }
        try? context.save()
        onDone()
    }
}
