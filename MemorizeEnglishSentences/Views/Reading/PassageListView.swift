import Combine
import SwiftData
import SwiftUI
import Translation

/// 音読タブ。文章の分類はせず、登録したすべての英文ブロックを 1 画面に連続表示する。
struct PassageListView: View {
    /// 音読タブが再タップされるたびに増える値。iOS 標準の「一番上へスクロール」を
    /// 打ち消して前回位置に戻すために使う。
    var reselectSignal: Int = 0

    @Environment(\.modelContext) private var context
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "reading" },
        sort: \Passage.createdAt, order: .reverse
    ) private var passages: [Passage]

    @State private var expandedBlockIDs: Set<PersistentIdentifier> = []
    @State private var selectedWord: SelectedWord?
    @StateObject private var wordMeaning = WordMeaningModel()
    @State private var wordBroker = WordTranslationBroker()
    @State private var warmupRetryCount = 0
    @State private var wordConfiguration: TranslationSession.Configuration?
    @State private var retryConfiguration: TranslationSession.Configuration?
    @State private var scrollProxy: ScrollViewProxy?
    /// 表示中の元スクショ(nil = 非表示)
    @State private var sourceImage: IdentifiableImage?
    /// 画面中央付近にあるブロック(現在位置の表示・しおりの自動更新に使う)
    @State private var currentBlockID: PersistentIdentifier?
    /// 起動後に一度だけしおり位置へ合わせたか
    @State private var didInitialScroll = false
    /// 起動時の位置復元が完了したか(完了までは自動しおり保存を止める)
    @State private var restoreDone = false
    /// アプリの利用期限のお知らせを表示中か
    @State private var showExpiryInfo = false
    /// 単語学習ハブを表示中か
    @State private var showStudyHub = false
    /// 連続再生の状態。@ObservedObject にすると再生中の状態更新のたびに
    /// 一覧全体が再描画されて重くなるため、必要な変化だけ onReceive で拾う
    private var speech: SpeechSynthesisService { .shared }
    /// 教材音声プレイヤーの状態(同上)
    private var audioPlayer: AudioSequencePlayer { .shared }
    /// どちらかのプレイヤーが連続再生中か(ツールバーの表示切り替え用)
    @State private var isAnyPlaying = false
    /// 教材音声プレイヤー(ミニプレイヤー)が動いているか
    @State private var audioActive = false
    /// 連続再生プレイヤーの表示(TTS)
    @State private var showPlayer = false
    /// 教材音声プレイヤーの表示
    @State private var showAudioPlayer = false
    /// 連続再生中の英文・和訳
    @State private var playerItems: [PlaybackItem] = []
    /// 連続再生の速度・ボイス・繰り返し(暗記タブと共有)
    @AppStorage("listenSpeed") private var listenSpeed = 1.0
    @AppStorage("listenVoiceID") private var listenVoiceID = ""
    @AppStorage("repeatEachSentence") private var repeatEach = false
    /// 音声再生用しおり(最後に聴いていた英文の先頭部分)。音読用しおりとは別に記憶する
    @AppStorage("audioPlaybackBookmark") private var audioBookmark = ""
    /// 再生セッション中の各項目→英文キー(再生位置をしおりへ保存するための対応表)
    @State private var playerKeys: [String] = []

    private var blocks: [Block] {
        passages.flatMap { $0.orderedBlocks }
    }

    /// 連続再生の対象(英文が空でないブロック)
    private var playbackBlocks: [Block] {
        blocks.filter { !$0.englishText.isEmpty }
    }

    /// 音声再生用しおりのキー(英文の先頭で識別)
    private func playbackKey(for block: Block) -> String {
        String(block.englishText.prefix(80))
    }

    /// 音声再生用しおり(最後に聴いていた英文)から、または最初から連続再生を始める。
    /// 画面スクロール用のしおり(音読用)とは独立して動く。
    private func startPlayback(fromBeginning: Bool) {
        startPlaybackCore(startKey: fromBeginning ? nil : audioBookmark)
    }

    /// 指定した英文から連続再生を始める(一覧の右スワイプ▶)
    private func startPlayback(from block: Block) {
        startPlaybackCore(startKey: playbackKey(for: block))
    }

    /// 連続再生の本体。startKey に一致する英文から(見つからなければ先頭から)始める。
    /// 教材音声(block_audio)があるブロックは実音声+単語タイミングで再生し、
    /// 無い場合(後から追加した英文のみ等)はTTSで読む。
    private func startPlaybackCore(startKey: String?) {
        let targets = playbackBlocks
        guard !targets.isEmpty else { return }

        // 教材音声モード: 音声があるブロックだけを対象にする
        let audioTargets = targets.filter { BlockAudioStore.hasAudio(forBlockText: $0.englishText) }
        if !audioTargets.isEmpty {
            let items: [AudioPlaybackItem] = audioTargets.compactMap { blk in
                guard let a = BlockAudioStore.item(forBlockText: blk.englishText) else { return nil }
                // 文ごとの英↔和ペアがあれば「英文1文→和訳→…」の交互表示と文単位再生用に位置を解決する
                let segments = SentencePairLookup.cached(blockText: blk.englishText, modelContext: context)
                    .flatMap { pairs in
                        AudioPlaybackItem.buildSegments(english: blk.englishText,
                                                        pairs: pairs.map { ($0.en, $0.ja) },
                                                        words: a.words)
                    }
                // 保存済みの文ごと再生回数(×0=スキップ、×2以上=繰り返し)を反映する
                let counts = SentenceRepeatStore.counts(forBlockText: blk.englishText,
                                                        sentenceCount: segments?.count ?? 0)
                return AudioPlaybackItem(english: blk.englishText, japanese: blk.japaneseText ?? "",
                                         url: a.url, words: a.words, segments: segments,
                                         repeatCounts: counts, silences: a.silences,
                                         blockRepeat: SentenceRepeatStore.globalBlockCount)
            }
            guard !items.isEmpty else { return }
            let keys = audioTargets.map { playbackKey(for: $0) }
            let startIndex = startKey.flatMap { keys.firstIndex(of: $0) } ?? 0
            playerKeys = keys
            // 音読タブは最後のブロックまで再生したら先頭へ戻って連続再生する
            audioPlayer.start(items: items, startAt: startIndex, speed: listenSpeed, source: .reading, loop: true)
            showAudioPlayer = true
            return
        }

        // TTSモード(教材音声が1つも無い場合のフォールバック)
        let keys = targets.map { playbackKey(for: $0) }
        let startIndex = startKey.flatMap { keys.firstIndex(of: $0) } ?? 0
        playerKeys = keys
        playerItems = targets.map { PlaybackItem(english: $0.englishText, japanese: $0.japaneseText ?? "") }
        speech.repeatSentence = repeatEach
        speech.speakSequence(playerItems.map(\.english), speed: listenSpeed,
                             voiceID: listenVoiceID.isEmpty ? nil : listenVoiceID,
                             startAt: startIndex)
        showPlayer = true
    }

    /// 残りわずかなら赤、少なめなら橙、余裕があれば通常色
    private var expiryTintColor: Color {
        guard let days = AppExpiry.daysRemaining else { return .secondary }
        if days <= 1 { return .red }
        if days <= 3 { return .orange }
        return .secondary
    }

    /// 期限アラートの本文
    private var expiryMessage: String {
        guard let dateText = AppExpiry.expirationText else {
            return "利用期限を取得できませんでした。"
        }
        return "\(dateText) まで使えます"
    }

    var body: some View {
        NavigationStack {
            Group {
                if blocks.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "book",
                        description: Text("Mac(Claude Code)から英文を取り込むと、ここに表示されます。")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(blocks) { block in
                                blockRow(block)
                                    .id(block.persistentModelID)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    // 各行の画面上の位置を報告(中央に一番近い行を現在位置とする)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: BlockCenterKey.self,
                                                value: [block.persistentModelID: geo.frame(in: .global).midY]
                                            )
                                        }
                                    )
                                    // 右スワイプでこの英文から連続再生(途中から再生)
                                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                        Button {
                                            startPlayback(from: block)
                                        } label: {
                                            Image(systemName: "play.fill")
                                        }
                                        .tint(.blue)
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            delete(block)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        // タブ再タップ時の「トップへスクロール」を無効化(空白なしで前回位置のまま)
                        .background(DisableScrollToTop())
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemBackground))
                        // 中央に最も近い行を現在位置として更新する
                        .onPreferenceChange(BlockCenterKey.self) { positions in
                            updateCurrentBlock(from: positions)
                        }
                        .onAppear {
                            scrollProxy = proxy
                            // 起動後の初回だけ、しおり位置へアニメーションなしで即ジャンプする
                            // (スルスル動くのではなく一瞬で位置が決まる)
                            if !didInitialScroll {
                                didInitialScroll = true
                                if let marked = blocks.first(where: { $0.isMarked }) {
                                    proxy.scrollTo(marked.persistentModelID, anchor: .center)
                                }
                                // 復元が落ち着いてから自動しおり保存を再開する
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(0.6))
                                    restoreDone = true
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                // アプリの利用期限(タップで日付を表示)。残りわずかなら赤くする
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showExpiryInfo = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(expiryTintColor)
                    }
                }
                // 単語学習(チェックした英文→単語を選ぶ→シス単風に再生)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showStudyHub = true
                    } label: {
                        Image(systemName: "checklist")
                    }
                }
                if !blocks.isEmpty {
                    // 現在位置(240件中 N件目)
                    ToolbarItem(placement: .principal) {
                        Text("\(blocks.count)件中 \(currentPositionText)件目")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // 連続再生: 続きから(▶ 音声再生用しおり)。
                    // 教材音声プレイヤーが動いている間(ミニプレイヤー中)は、右上を
                    // 停止ではなく「全画面プレイヤーを開く」に。停止はミニプレイヤーのスワイプで行う
                    ToolbarItem(placement: .primaryAction) {
                        // いま鳴っているのが「音読タブの音声」なら全画面を開いて続きから。
                        // 何も鳴っていない or 暗記タブの音声が鳴っている時は、音読タブの音声を新しく再生する
                        // (暗記→ミニプレイヤー→音読タブで再生ボタンを押したら音読が鳴るように)
                        if audioActive, audioPlayer.source == .reading {
                            Button {
                                if audioPlayer.isPaused { audioPlayer.resume() }
                                showAudioPlayer = true
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        } else {
                            Button {
                                startPlayback(fromBeginning: false)
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            // 再生位置を音声再生用しおりに保存し続ける(音読のしおりとは独立)
            .onReceive(AudioSequencePlayer.shared.$sequenceIndex) { idx in
                if let idx, playerKeys.indices.contains(idx) { audioBookmark = playerKeys[idx] }
            }
            .onReceive(SpeechSynthesisService.shared.$sequenceIndex) { idx in
                if let idx, showPlayer, playerKeys.indices.contains(idx) { audioBookmark = playerKeys[idx] }
            }
            // 再生中かどうかだけを監視する(プレイヤー全体を @ObservedObject にしない)
            .onReceive(AudioSequencePlayer.shared.$isPlayingSequence
                .combineLatest(SpeechSynthesisService.shared.$isPlayingSequence)) { audio, tts in
                let playing = audio || tts
                if isAnyPlaying != playing { isAnyPlaying = playing }
                if audioActive != audio { audioActive = audio }
            }
            .fullScreenCover(isPresented: $showPlayer) {
                SentencePlayerView(items: playerItems)
            }
            // sheetにすることで「下スワイプで閉じる=再生は続けてミニプレイヤーへ」ができる
            .sheet(isPresented: $showAudioPlayer) {
                AudioPlayerView()
            }
            .sheet(isPresented: $showStudyHub) {
                StudyHubView(context: context)
            }
            .sheet(item: $selectedWord) { selected in
                WordPopupView(word: selected.word, meaning: wordMeaning)
            }
            .sheet(item: $sourceImage) { item in
                SourceImageView(image: item.image)
            }
            .alert("アプリの利用期限", isPresented: $showExpiryInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(expiryMessage)
            }
            // スクロールが落ち着いたら現在位置のブロックにしおりを保存する(書き込み過多を防ぐ)
            // ※和訳の自動クローズは一度入れたが「閉じた瞬間に上の項目が縮んで
            //   読んでいる位置がズレる」ため取りやめた(2026-08-19)
            .task(id: currentBlockID) {
                try? await Task.sleep(for: .seconds(0.35))
                guard !Task.isCancelled else { return }
                persistBookmark()
            }
            // 単語の翻訳(常駐セッション 1 本に、タップされた単語をストリームで流し込む)
            .translationTask(wordConfiguration) { session in
                // ダミー翻訳でセッションの生存確認。
                // 起動直後は言語カタログの読み込みが間に合わず
                // unsupportedSourceLanguage で壊れたセッションになることがあるため、
                // その場合は少し待ってセッションを作り直す。
                do {
                    let r = try await translate(session, "hello", timeoutSeconds: 3)
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
            // 未翻訳ブロックは表示時に再翻訳を試みる
            .translationTask(retryConfiguration) { session in
                await retryTranslations(with: session)
            }
            .onAppear {
                startRetryTranslationIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func blockRow(_ block: Block) -> some View {
        BlockCardView(
            block: block,
            isExpanded: expandedBlockIDs.contains(block.persistentModelID),
            onToggle: { toggle(block) },
            onWordTap: { word, occurrence in
                showWord(word, occurrence: occurrence, sentenceContext: block.englishText)
            },
            sentencePairs: SentencePairLookup.cached(blockText: block.englishText, modelContext: context),
            onShowSource: PageImageStore.hasImage(forBlockText: block.englishText)
                ? { sourceImage = PageImageStore.image(forBlockText: block.englishText).map(IdentifiableImage.init) }
                : nil
        )
        .equatable()
    }

    /// 単語の意味を表示。Claude Code が事前生成した「その文中での意味」を最優先し、
    /// キャッシュにない単語は内蔵辞書 → キャッシュ → Apple 翻訳で解決する
    private func showWord(_ word: String, occurrence: Int, sentenceContext: String) {
        wordMeaning.reset()
        selectedWord = SelectedWord(word: word)

        // 事前生成済みの「この文中での意味」があれば最優先(無料・オフライン)
        if let cached = WordSenseLookup.cached(word: word, occurrence: occurrence, blockText: sentenceContext, modelContext: context) {
            wordMeaning.apply(cached)
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
        // ここで初めて Apple 翻訳が必要になる。セッションを遅延で用意する
        // (起動時に前もって作ると「翻訳」の言語ダウンロード画面が出てしまうため)
        if wordConfiguration == nil {
            wordConfiguration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
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

    /// どこまで読んだかの目印。全体で 1 か所だけ(付け直すと移動、同じ場所なら解除)
    /// 現在位置の表示に使う番号(1始まり)。未確定のときは 1
    private var currentPositionText: String {
        guard let id = currentBlockID,
              let index = blocks.firstIndex(where: { $0.persistentModelID == id }) else { return "1" }
        return "\(index + 1)"
    }

    /// スクロール中の位置更新を間引くための入れ物(毎フレーム状態を書き換えない)
    private final class CurrentBlockThrottle {
        var last = Date.distantPast
        var pending: [PersistentIdentifier: CGFloat]?
        var scheduled = false
    }
    @State private var blockThrottle = CurrentBlockThrottle()

    /// 各行の中央 Y から、画面中央に一番近い行を現在位置として選ぶ。
    /// スクロール中は毎フレーム届くので 0.15 秒に1回へ間引き、最後の1回は必ず反映する
    /// (毎フレーム @State を書くと一覧全体の再評価が走ってカクつく)。
    private func updateCurrentBlock(from positions: [PersistentIdentifier: CGFloat]) {
        guard !positions.isEmpty else { return }
        let now = Date()
        if now.timeIntervalSince(blockThrottle.last) >= 0.15 {
            blockThrottle.last = now
            applyCurrentBlock(from: positions)
        } else {
            blockThrottle.pending = positions
            if !blockThrottle.scheduled {
                blockThrottle.scheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    blockThrottle.scheduled = false
                    if let pending = blockThrottle.pending {
                        blockThrottle.pending = nil
                        blockThrottle.last = Date()
                        applyCurrentBlock(from: pending)
                    }
                }
            }
        }
    }

    private func applyCurrentBlock(from positions: [PersistentIdentifier: CGFloat]) {
        let screenCenter = UIScreen.main.bounds.height / 2
        let nearest = positions.min { abs($0.value - screenCenter) < abs($1.value - screenCenter) }
        if let id = nearest?.key, id != currentBlockID {
            currentBlockID = id
        }
    }

    /// 現在位置のブロックにしおりを自動で付け替える(1か所だけ)
    private func persistBookmark() {
        // 起動時の位置復元が終わるまでは保存しない。
        // (復元前はリストがトップに出ているので、保存するとしおりがトップに上書きされてしまう)
        guard restoreDone else { return }
        guard let id = currentBlockID,
              let target = blocks.first(where: { $0.persistentModelID == id }) else { return }
        var changed = false
        for block in blocks where block.isMarked && block.persistentModelID != id {
            block.isMarked = false
            changed = true
        }
        if !target.isMarked {
            target.isMarked = true
            changed = true
        }
        if changed { try? context.save() }
    }

    private func delete(_ block: Block) {
        let passage = block.passage
        context.delete(block)
        // ブロックがなくなった文章は本体ごと削除する
        if let passage, passage.blocks.filter({ $0.persistentModelID != block.persistentModelID }).isEmpty {
            context.delete(passage)
        }
        try? context.save()
    }

    private func toggle(_ block: Block) {
        if expandedBlockIDs.contains(block.persistentModelID) {
            expandedBlockIDs.remove(block.persistentModelID)
        } else {
            expandedBlockIDs.insert(block.persistentModelID)
        }
    }

    private func startRetryTranslationIfNeeded() {
        guard blocks.contains(where: { $0.japaneseText == nil }) else { return }
        if retryConfiguration == nil {
            retryConfiguration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
        } else {
            retryConfiguration?.invalidate()
        }
    }

    private func retryTranslations(with session: TranslationSession) async {
        let untranslated = blocks.filter { $0.japaneseText == nil }
        guard !untranslated.isEmpty else { return }
        do {
            try await session.prepareTranslation()
            let requests = untranslated.enumerated().map { index, block in
                TranslationSession.Request(sourceText: block.englishText, clientIdentifier: "\(index)")
            }
            for try await response in session.translate(batch: requests) {
                if let identifier = response.clientIdentifier,
                   let index = Int(identifier),
                   index < untranslated.count {
                    untranslated[index].japaneseText = response.targetText
                }
            }
            try? context.save()
        } catch {
            // オフライン・言語データ未ダウンロード時は静かに諦める(次回表示時に再試行)
        }
    }
}

/// 各ブロックの画面上の中央 Y を集める PreferenceKey(現在位置の判定に使う)
private struct BlockCenterKey: PreferenceKey {
    static let defaultValue: [PersistentIdentifier: CGFloat] = [:]
    static func reduce(value: inout [PersistentIdentifier: CGFloat], nextValue: () -> [PersistentIdentifier: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
