import PhotosUI
import SwiftUI

/// 英文の登録シート(3 ステップ: ① 音声入力/写真/編集 → ② 文分割プレビュー → ③ 翻訳して保存)
struct AddPassageView: View {
    @Environment(\.dismiss) private var dismiss
    /// どちらのタブ用の文章として保存するか(音読と暗記は独立)
    let purpose: PassagePurpose

    private enum Step {
        case input
        case preview
        case translate
    }

    @State private var step: Step = .input
    @State private var title = ""
    @State private var text = ""
    @State private var sentences: [String] = []
    @State private var speech = SpeechRecognitionService()

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isRecognizing = false
    @State private var ocrError: String?

    @State private var editingIndex: Int?
    @FocusState private var focusedIndex: Int?

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .input:
                    inputStep
                case .preview:
                    previewStep
                case .translate:
                    TranslateAndSaveView(title: resolvedTitle, sentences: sentences, purpose: purpose) {
                        dismiss()
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        speech.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
                // 前のステップへ戻る
                if step != .input {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            step = (step == .translate) ? .preview : .input
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    switch step {
                    case .input:
                        Button("次へ") {
                            speech.stop()
                            sentences = TextSplitter.split(text)
                            step = .preview
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    case .preview:
                        Button("翻訳へ") {
                            sentences = sentences
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                            step = .translate
                        }
                        .disabled(sentences.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                    case .translate:
                        EmptyView()
                    }
                }
            }
        }
        .interactiveDismissDisabled(step == .translate)
        .onAppear {
            speech.onFinalSegment = { segment in
                text = text.isEmpty ? segment : text + " " + segment
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .input: ""
        case .preview: "文の分割を確認"
        case .translate: "翻訳して保存"
        }
    }

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstSentence = sentences.first ?? text
        return String(firstSentence.prefix(30))
    }

    // MARK: - ① 音声入力/編集

    private var inputStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $text)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            if speech.isRecording, !speech.partialText.isEmpty {
                Text(speech.partialText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            }

            if isRecognizing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("写真から読み取り中...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = speech.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if let ocrError {
                Text(ocrError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 36) {
                Spacer()
                DictationButton(speech: speech, iconOnly: true)
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.borderless)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await recognize(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) {
            guard let photoItem else { return }
            Task {
                if let data = try? await photoItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await recognize(image)
                } else {
                    ocrError = "写真を読み込めませんでした。"
                }
                self.photoItem = nil
            }
        }
    }

    /// 写真から英文を OCR してエディタへ追記する
    private func recognize(_ image: UIImage) async {
        ocrError = nil
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            let recognized = try await TextRecognitionService.recognizeEnglishText(in: image)
            text = text.isEmpty ? recognized : text + "\n" + recognized
        } catch {
            ocrError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - ② 文分割プレビュー

    private var previewStep: some View {
        VStack(spacing: 0) {
            // 一番上に不自然な語の合計数を表示
            let total = totalSuspiciousCount
            if total > 0 {
                Label("英文として不自然な語が \(total) 個あります", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.bold())
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.12))
            }

            List {
                Section {
                    ForEach(sentences.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if editingIndex == index {
                                    Button("完了") {
                                        editingIndex = nil
                                        focusedIndex = nil
                                    }
                                    .font(.caption)
                                    .buttonStyle(.borderless)
                                } else if index > 0 {
                                    Button {
                                        mergeWithPrevious(index)
                                    } label: {
                                        Label("前と結合", systemImage: "arrow.turn.left.up")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }

                            if editingIndex == index {
                                TextField("英文", text: $sentences[index], axis: .vertical)
                                    .focused($focusedIndex, equals: index)
                            } else {
                                // 不自然な語をオレンジ色でハイライト(タップで編集)
                                Text(highlighted(sentences[index]))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        editingIndex = index
                                        focusedIndex = index
                                    }
                            }

                            // 読み取りミスの可能性がある語を警告(スペルチェック)
                            let suspicious = SentenceValidator.misspelledWords(in: sentences[index])
                            if !suspicious.isEmpty {
                                Label("英文として不自然な語: \(suspicious.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        sentences.remove(atOffsets: offsets)
                        editingIndex = nil
                    }
                } footer: {
                    Text("1 行が 1 ブロックとして保存されます。文をタップすると編集できます。オレンジの語は写真の読み取りミスの可能性があるため、編集または左スワイプで削除してから進んでください。")
                }
            }
        }
    }

    private var totalSuspiciousCount: Int {
        sentences.reduce(0) { $0 + SentenceValidator.misspelledWords(in: $1).count }
    }

    /// 不自然な語をオレンジ色にした表示用テキスト
    private func highlighted(_ sentence: String) -> AttributedString {
        var attributed = AttributedString(sentence)
        for word in Set(SentenceValidator.misspelledWords(in: sentence)) {
            var searchStart = sentence.startIndex
            while let range = sentence.range(of: word, range: searchStart..<sentence.endIndex) {
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].foregroundColor = .orange
                }
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    private func mergeWithPrevious(_ index: Int) {
        guard index > 0, index < sentences.count else { return }
        sentences[index - 1] += " " + sentences[index]
        sentences.remove(at: index)
    }
}
