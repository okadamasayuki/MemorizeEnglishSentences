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
                    Button("キャンセル") {
                        speech.stop()
                        dismiss()
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
        case .input: "英文を入力"
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
            // タイトルは暗記用の登録でだけ使う(音読は一覧がないため不要)
            if purpose == .recall {
                TextField("タイトル(省略可)", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            TextEditor(text: $text)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty, !speech.isRecording {
                        Text("英文を音声入力するか、ここに入力・ペーストしてください")
                            .foregroundStyle(.tertiary)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }

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

            HStack(spacing: 10) {
                Spacer()
                DictationButton(speech: speech, label: "音声")
                Button {
                    showCamera = true
                } label: {
                    Label("カメラ", systemImage: "camera.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("写真", systemImage: "photo.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
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
        List {
            Section {
                ForEach(sentences.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            if index > 0 {
                                Button {
                                    mergeWithPrevious(index)
                                } label: {
                                    Label("前と結合", systemImage: "arrow.turn.left.up")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        TextField("英文", text: $sentences[index], axis: .vertical)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { offsets in
                    sentences.remove(atOffsets: offsets)
                }
            } footer: {
                Text("1 行が 1 ブロック(1 文)として保存されます。編集・削除・前の文との結合ができます。")
            }
        }
    }

    private func mergeWithPrevious(_ index: Int) {
        guard index > 0, index < sentences.count else { return }
        sentences[index - 1] += " " + sentences[index]
        sentences.remove(at: index)
    }
}
