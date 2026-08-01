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

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isRecognizing = false
    /// 複数枚取り込み中の進捗(例: 3/12)
    @State private var recognizeProgress: (done: Int, total: Int)?
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
                // 複数枚を一度に選んでまとめて取り込める
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 0,
                    selectionBehavior: .ordered,
                    matching: .images
                ) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.borderless)
                Spacer()
            }

            // 複数枚取り込み中の進捗表示
            if let progress = recognizeProgress {
                ProgressView(value: Double(progress.done), total: Double(progress.total)) {
                    Text("写真を読み取り中… \(progress.done)/\(progress.total)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding()
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                Task { await recognizeImage(image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoItems) {
            guard !photoItems.isEmpty else { return }
            let items = photoItems
            Task { await recognizeAll(items) }
        }
    }

    /// カメラ 1 枚撮影分を OCR してエディタへ追記する
    private func recognizeImage(_ image: UIImage) async {
        ocrError = nil
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            let recognized = try await TextRecognitionService.recognizeEnglishText(in: image)
            if !recognized.isEmpty {
                text = text.isEmpty ? recognized : text + "\n\n" + recognized
            }
        } catch {
            ocrError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// 選んだ写真を選択順に OCR して、まとめてエディタへ追記する
    private func recognizeAll(_ items: [PhotosPickerItem]) async {
        ocrError = nil
        isRecognizing = true
        recognizeProgress = (0, items.count)
        defer {
            isRecognizing = false
            recognizeProgress = nil
            photoItems = []
        }

        var failedCount = 0
        for (offset, item) in items.enumerated() {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                do {
                    let recognized = try await TextRecognitionService.recognizeEnglishText(in: image)
                    if !recognized.isEmpty {
                        // ページ間は段落境界として空行で区切る
                        text = text.isEmpty ? recognized : text + "\n\n" + recognized
                    }
                } catch {
                    failedCount += 1
                }
            } else {
                failedCount += 1
            }
            recognizeProgress = (offset + 1, items.count)
        }

        if failedCount > 0 {
            ocrError = "\(items.count) 枚中 \(failedCount) 枚を読み取れませんでした。"
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
                        let suspicious = SentenceValidator.misspelledWords(in: sentences[index])
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
                            if !suspicious.isEmpty {
                                Label("英文として不自然な語: \(suspicious.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                        // 不自然な語がある行は背景をオレンジに
                        .listRowBackground(
                            suspicious.isEmpty
                                ? Color(.secondarySystemGroupedBackground)
                                : Color.orange.opacity(0.13)
                        )
                    }
                    .onDelete { offsets in
                        sentences.remove(atOffsets: offsets)
                        editingIndex = nil
                    }
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
