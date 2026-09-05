import PhotosUI
import SwiftUI
import UIKit

/// アプリ自体の改善点を書き留めておくタブ(music-3x と同じ仕組み)。
///
/// 出先で思いついたことを声や文字で放り込んでおき、家に帰って Mac が点いているときに
/// 項目を左から右へスワイプすると、Mac 側で Claude Code が立ち上がって
/// その要望の実装を始める。
struct ImprovementListView: View {
    @ObservedObject private var store = ImprovementStore.shared
    @ObservedObject private var resultStore = ImprovementResultStore.shared
    /// 全文表示する対応結果
    @State private var resultDetail: ImprovementResult?
    /// 「対応済み」を一括削除する前の確認
    @State private var showClearResultsConfirm = false
    /// 日本語の書き取り(長い口述でも切れないよう自動再開する)
    @State private var dictation = SpeechRecognitionService(locale: Locale(identifier: "ja-JP"))

    /// 送り先(Mac のホスト名:ポート)。変えたくなったら設定できるよう端末に記憶する
    @AppStorage("improveHost") private var improveHost = MacLink.defaultHost
    /// 入力欄の下書き。アプリが途中で落ちても書きかけが消えないよう端末に置く
    @AppStorage("improveDraft") private var draft = ""
    /// 書き取りを始めたときに入力欄へすでにあった文。聞き取りはこの後ろへ足す
    @State private var dictationBase = ""
    /// いま Mac へ送っている最中の項目。行に回転を出して二度押しを防ぐ
    @State private var sendingIDs: Set<UUID> = []
    /// 一括送信の実行中(ボタンの二度押しを防ぐ)
    @State private var batchSending = false
    /// 選択モード(複数選んでまとめて送るための状態)
    @State private var selectMode = false
    /// 選択された項目。押した順を保つため配列で持つ(1番→2番…の順に送る)
    @State private var selectedOrder: [UUID] = []
    /// 送れなかったときの説明
    @State private var errorMessage: String?
    /// 編集中の項目
    @State private var editTarget: Improvement?
    @State private var editText = ""
    /// Mac の受け口に届くか。nil はまだ一度も調べていない
    @State private var reachable: Bool?
    /// 再接続の矢印の回転角。押すたびに一回転させ、押せたことを見せる
    @State private var spinAngle = 0.0

    /// 下書きに付ける添付(保存済みファイル名)
    @State private var draftAttachments: [String] = []
    /// フォトピッカーの選択
    @State private var pickedItems: [PhotosPickerItem] = []

    @FocusState private var editFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                inputSection
                if !store.items.isEmpty { pendingSection }
                if !resultStore.results.isEmpty { resultsSection }
            }
            .refreshable { resultStore.reload() }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("改善")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    connectionStatus
                }
            }
            .onAppear {
                checkReachability()
                resultStore.reload()
            }
            // 動作検証用: memoeng://improve/mic で書き取りを開始/終了できる
            // (シミュレーターで音声入力の消失を自動再現するのに使う)
            .onOpenURL { url in
                if url.host() == "improve", url.lastPathComponent == "mic" {
                    toggleDictation()
                }
            }
            // 聞き取りの途中経過を入力欄へ流し込む(手で書いた分の後ろに足す)
            .onChange(of: dictation.fullText) { _, text in
                guard dictation.isRecording, !text.isEmpty else { return }
                draft = dictationBase.isEmpty ? text : dictationBase + "\n" + text
                PerfLog.log("draft len=\(draft.count) [\(draft.suffix(24))]")
            }
            .alert("送れませんでした", isPresented: showErrorBinding) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            // 対応済みの一括全消去(確認してから)。alertにして常に画面中央に出す
            // (confirmationDialogだと環境によって変な位置のポップオーバーになるため)
            .alert("対応済みをすべて消去しますか?", isPresented: $showClearResultsConfirm) {
                Button("キャンセル", role: .cancel) {}
                Button("すべて消去", role: .destructive) { resultStore.removeAll() }
            } message: {
                Text("対応済み\(resultStore.results.count)件をまとめて消します。")
            }
            // 声で入れたメモは数行になりがちで、アラートの1行欄では直しづらい。
            // 全体を見渡しながら書き直せる広い欄をシートで出す。
            .sheet(item: $editTarget) { _ in
                editSheet
            }
            // 対応結果の全文表示
            .sheet(item: $resultDetail) { result in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.summary)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                    .navigationTitle("対応内容")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { resultDetail = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - 入力

    private var inputSection: some View {
        Section {
            // 入力欄はひとつだけ置き、聞き取り中はその上へ読み専用の眺めを重ねる
            TextField("", text: $draft, axis: .vertical)
                .lineLimit(3...8)
                .disabled(dictation.isRecording)
                .opacity(dictation.isRecording ? 0 : 1)
                .overlay {
                    if dictation.isRecording {
                        // 聞き取り中は流れが見えることが何より大事。常に最新の行が見えるようにする
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                Text(draft)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id("dictationTail")
                            }
                            .onChange(of: draft) { _, _ in
                                proxy.scrollTo("dictationTail", anchor: .bottom)
                            }
                            .onAppear { proxy.scrollTo("dictationTail", anchor: .bottom) }
                        }
                    }
                }

            HStack(spacing: 12) {
                // マイクの絵だけの小さなボタン(説明の文字は要らない)
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 20)
                }
                .buttonStyle(.borderedProminent)
                .tint(dictation.isRecording ? .red : Color.accentColor)

                // 写真・動画の添付(スクショでの報告用)
                PhotosPicker(selection: $pickedItems, maxSelectionCount: 100,
                             matching: .any(of: [.images, .videos])) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 30, minHeight: 20)
                }
                .buttonStyle(.bordered)
                .onChange(of: pickedItems) { _, items in
                    Task { await importPicked(items) }
                }

                if !draftAttachments.isEmpty {
                    Text("📎\(draftAttachments.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 言い直したくなったときに、書きかけを一息で捨てる
                if !draft.isEmpty {
                    Button(action: clearDraft) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 30, minHeight: 28)
                    }
                    .buttonStyle(.plain)
                }

                Button("追加", action: addDraft)
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 28)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              && draftAttachments.isEmpty)
            }

            if let problem = dictation.errorMessage {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if dictation.permissionDenied {
                Text("設定アプリでマイクと音声認識を許可してください。")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Mac に届くかどうかの表示。家に帰って Mac を点けたらここが緑になる。
    /// 押せばそのまま再接続になる。
    private var connectionStatus: some View {
        Button {
            withAnimation(.linear(duration: 0.7)) { spinAngle += 360 }
            checkReachability()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(reachable == true ? Color.green : reachable == false ? Color.orange : Color.gray)
                    .frame(width: 8, height: 8)
                Text(connectionLabel)
                    .font(.footnote)
                Image(systemName: "arrow.clockwise")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(spinAngle))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    private var connectionLabel: String {
        switch reachable {
        case true: return "接続済み"
        case false: return "未接続"
        default: return "確認中…"
        }
    }

    // MARK: - まだ送っていない項目

    private var pendingSection: some View {
        Section {
            // 上ほど古く、下ほど新しく並べる(古い順=送る順と一致)
            ForEach(store.items.sorted { $0.createdAt < $1.createdAt }) { item in
                pendingRow(item)
            }
        } header: {
            // 見出しの右端に一括送信の操作。ワンクリックで古い順に全部送れる。
            // 「選択」を押すと複数選んでまとめて送るモードに入る。
            HStack {
                Text("これから\(store.items.count > 0 ? "(\(store.items.count))" : "")")
                Spacer()
                if selectMode {
                    Button(selectedOrder.isEmpty ? "送信" : "\(selectedOrder.count)件を送信") {
                        sendSelected()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .disabled(selectedOrder.isEmpty || batchSending)
                    .textCase(nil)
                    Button("やめる") { selectMode = false; selectedOrder = [] }
                        .font(.caption)
                        .textCase(nil)
                } else {
                    Button("全て送信") { sendAll() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .disabled(batchSending)
                        .textCase(nil)
                    Button("選択") { selectMode = true }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }

    private func pendingRow(_ item: Improvement) -> some View {
        HStack(spacing: 10) {
            // 選択モードのときだけ、行の左に「押した順の番号」を出す。
            // 未選択は空の丸。選択済みは 1・2・3… の番号バッジ(この順に送る)
            if selectMode {
                if let idx = selectedOrder.firstIndex(of: item.id) {
                    Text("\(idx + 1)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor))
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                HStack(spacing: 6) {
                    Text(item.createdAt, format: .dateTime.month().day().hour().minute())
                    if let n = item.attachments?.count, n > 0 {
                        Text("📎\(n)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if sendingIDs.contains(item.id) {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
        // 選択モード中はタップで選択の入り切り。ふだんはタップで書き直し
        .onTapGesture {
            if selectMode {
                // もう一度押したら選択を外して、残りの番号を繰り上げる
                if let idx = selectedOrder.firstIndex(of: item.id) {
                    selectedOrder.remove(at: idx)
                } else {
                    selectedOrder.append(item.id)
                }
            } else {
                editText = item.text
                editTarget = item
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                send(item)
            } label: {
                Label("実装", systemImage: "hammer.fill")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                store.remove(item.id)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    // MARK: - 対応済み(Claude Codeからの結果報告)

    private var resultsSection: some View {
        Section {
            // 対応済みも上ほど古く、下ほど新しく並べる
            ForEach(resultStore.results.sorted { $0.completedAt < $1.completedAt }) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.title)
                        .font(.subheadline.weight(.semibold))
                    Text(result.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text(result.completedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { resultDetail = result }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        resultStore.remove(result.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        } header: {
            // 見出しの右端に「全消去」。誤操作を防ぐため確認してから消す
            HStack {
                Text("対応済み")
                Spacer()
                Button("全消去") { showClearResultsConfirm = true }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .textCase(nil)
            }
        }
    }

    // MARK: - 編集

    private var editSheet: some View {
        NavigationStack {
            TextEditor(text: $editText)
                .focused($editFocused)
                .padding(.horizontal, 12)
                .navigationTitle("内容を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { editTarget = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            if let target = editTarget { store.update(target.id, text: editText) }
                            editTarget = nil
                        }
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear {
                    // 開いたらすぐ書き直せるようにする。出た直後は焦点が入らないことがあるので一拍置く
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { editFocused = true }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 操作

    /// 書き取りのために一時停止したか(終わったら自動で再開する)
    @State private var pausedPlayerForDictation = false

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
            syncDraftFromDictation()
            resumePlayerIfNeeded()
        } else {
            // マイクは一つ。再生中の音声は「停止」ではなく「一時停止」にして、
            // ミニプレイヤーを残す(書き取りが終わったら自動で再開)
            SpeechSynthesisService.shared.stop()
            let audio = AudioSequencePlayer.shared
            if audio.isPlayingSequence, !audio.isPaused {
                audio.pause()
                pausedPlayerForDictation = true
            }
            dictationBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.reset()
            dictation.autoRestart = true
            Task { await dictation.start() }
        }
    }

    private func resumePlayerIfNeeded() {
        if pausedPlayerForDictation {
            pausedPlayerForDictation = false
            AudioSequencePlayer.shared.resume()
        }
    }

    /// 書きかけを全部捨てる。聞き取りの最中なら、聞き取りは続けたまま
    /// 文だけを空にして、言い直しにすぐ入れるようにする。
    private func clearDraft() {
        draft = ""
        dictationBase = ""
        for name in draftAttachments {
            try? FileManager.default.removeItem(at: ImprovementStore.mediaDir.appendingPathComponent(name))
        }
        draftAttachments = []
        if dictation.isRecording { dictation.restartClean() }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// 聞き取れている全文を下書きへ写す
    private func syncDraftFromDictation() {
        let text = dictation.fullText
        guard !text.isEmpty else { return }
        draft = dictationBase.isEmpty ? text : dictationBase + "\n" + text
    }

    private func addDraft() {
        if dictation.isRecording {
            dictation.stop()
            syncDraftFromDictation()
            resumePlayerIfNeeded()
        }
        store.add(draft, attachments: draftAttachments.isEmpty ? nil : draftAttachments)
        draft = ""
        dictationBase = ""
        draftAttachments = []
        pickedItems = []
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// フォトピッカーの選択を Documents/improve_media へ取り込む
    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard data.count < 120_000_000 else { continue }  // 極端に大きい動画は避ける
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
            let name = "\(UUID().uuidString).\(ext)"
            try? data.write(to: ImprovementStore.mediaDir.appendingPathComponent(name))
            draftAttachments.append(name)
        }
        pickedItems = []
        if !draftAttachments.isEmpty {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func send(_ item: Improvement) {
        guard !sendingIDs.contains(item.id) else { return }
        sendingIDs.insert(item.id)
        let host = improveHost
        Task { @MainActor in
            do {
                try await MacLink.send(item, host: host)
                // 送れた項目はその場で消す(控えは Mac 側の受信箱にある)
                store.remove(item.id)
                reachable = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = error.localizedDescription
                reachable = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            sendingIDs.remove(item.id)
        }
    }

    /// これからの項目を「古い順」にすべて送る(ワンクリック一括)
    private func sendAll() {
        sendBatch(store.items.sorted { $0.createdAt < $1.createdAt })
    }

    /// 選択した項目を「押した順(1番→2番…)」にまとめて送る
    private func sendSelected() {
        let ordered = selectedOrder.compactMap { id in store.items.first { $0.id == id } }
        sendBatch(ordered)
        selectMode = false
        selectedOrder = []
    }

    /// 渡された順に一つずつ Mac へ送る。送れたものはその場で消し、
    /// 一件でも届かなければ(Mac が点いていない等)そこで止める。
    private func sendBatch(_ items: [Improvement]) {
        guard !items.isEmpty, !batchSending else { return }
        batchSending = true
        let host = improveHost
        Task { @MainActor in
            var sentAny = false
            for item in items {
                // 途中で消えた・すでに送信中の項目は飛ばす
                guard store.items.contains(where: { $0.id == item.id }),
                      !sendingIDs.contains(item.id) else { continue }
                sendingIDs.insert(item.id)
                do {
                    try await MacLink.send(item, host: host)
                    store.remove(item.id)
                    reachable = true
                    sentAny = true
                } catch {
                    errorMessage = error.localizedDescription
                    reachable = false
                    sendingIDs.remove(item.id)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    batchSending = false
                    return
                }
                sendingIDs.remove(item.id)
            }
            batchSending = false
            if sentAny { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        }
    }

    private func checkReachability() {
        let host = improveHost
        Task { @MainActor in
            reachable = await MacLink.ping(host: host)
        }
    }

    // MARK: - アラートの開閉

    private var showErrorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
