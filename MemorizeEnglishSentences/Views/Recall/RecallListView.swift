import Combine
import SwiftData
import SwiftUI

struct RecallListView: View {
    @Environment(\.modelContext) private var context
    private static let sortOrder: [SortDescriptor<Passage>] = [
        SortDescriptor(\Passage.sortIndex),
        SortDescriptor(\Passage.createdAt, order: .reverse),
    ]
    @Query(
        filter: #Predicate<Passage> { $0.purposeRaw == "recall" },
        sort: sortOrder
    ) private var passages: [Passage]
    @State private var path: [Passage] = []
    /// 覚えた!を一覧から隠す(アプリを閉じても記憶する)
    @AppStorage("hideMemorized") private var hideMemorized = false
    /// 連続再生の状態。@ObservedObject にすると再生中の状態更新のたびに
    /// 一覧全体が再描画されて重くなるため、必要な変化だけ onReceive で拾う
    private var speech: SpeechSynthesisService { .shared }
    /// 連続再生中か(ツールバーの表示切り替え用)
    @State private var isPlayingSequence = false
    /// いま鳴っているのが暗記タブの音声か(音読の音声とは区別する)
    @State private var recallActive = false
    /// 連続再生プレイヤーの表示
    @State private var showPlayer = false
    /// 事前生成音声プレイヤーの表示
    @State private var showAudioPlayer = false
    /// 連続再生中の英文・和訳
    @State private var playerItems: [PlaybackItem] = []
    /// 連続再生の速度倍率(1.0=標準。アプリを閉じても記憶する)
    @AppStorage("listenSpeed") private var listenSpeed = 1.0
    /// 連続再生のボイス識別子(空=既定。アプリを閉じても記憶する)
    @AppStorage("listenVoiceID") private var listenVoiceID = ""
    /// 各英文を2回ずつ読むか(アプリを閉じても記憶する)
    @AppStorage("repeatEachSentence") private var repeatEach = false

    private var visiblePassages: [Passage] {
        hideMemorized ? passages.filter { $0.memorizationStatus != .memorized } : passages
    }

    /// 連続再生の対象になる文章(表示中で英文が空でないもの)
    private var playbackPassages: [Passage] {
        visiblePassages.filter { !$0.englishFullText.isEmpty }
    }

    /// いま一覧に表示されている英文・和訳(覚えた!を表示中なら覚えたも含む)
    private var visibleItems: [PlaybackItem] {
        playbackPassages.map { PlaybackItem(english: $0.englishFullText, japanese: $0.japaneseFullText) }
    }

    /// 指定の文章から(なければ先頭から)連続再生を始める。
    /// 事前生成した音声(自然な女性ボイス)がある項目はそちらを再生し、
    /// 無い項目だけ従来のTTSで読む(音読タブの教材音声と同じ仕組み)。
    private func startPlayback(from passage: Passage?) {
        let targets = playbackPassages
        guard !targets.isEmpty else { return }

        let audioTargets = targets.filter { BlockAudioStore.hasAudio(forBlockText: $0.englishFullText) }
        if !audioTargets.isEmpty {
            let items: [AudioPlaybackItem] = audioTargets.compactMap { p in
                guard let a = BlockAudioStore.item(forBlockText: p.englishFullText) else { return nil }
                let segments = SentencePairLookup.cached(blockText: p.englishFullText, modelContext: context)
                    .flatMap { pairs in
                        AudioPlaybackItem.buildSegments(english: p.englishFullText,
                                                        pairs: pairs.map { ($0.en, $0.ja) },
                                                        words: a.words)
                    }
                let counts = SentenceRepeatStore.counts(forBlockText: p.englishFullText,
                                                        sentenceCount: segments?.count ?? 0)
                return AudioPlaybackItem(english: p.englishFullText, japanese: p.japaneseFullText,
                                         url: a.url, words: a.words, segments: segments,
                                         repeatCounts: counts, silences: a.silences,
                                         blockRepeat: SentenceRepeatStore.globalBlockCount)
            }
            if !items.isEmpty {
                let startIndex = passage
                    .flatMap { p in audioTargets.firstIndex { $0.persistentModelID == p.persistentModelID } } ?? 0
                AudioSequencePlayer.shared.start(items: items, startAt: startIndex, speed: listenSpeed, source: .recall)
                showAudioPlayer = true
                return
            }
        }

        // 事前生成音声がまだ無い場合のTTSフォールバック
        let items = visibleItems
        let startIndex = passage
            .flatMap { p in playbackPassages.firstIndex { $0.persistentModelID == p.persistentModelID } } ?? 0
        playerItems = items
        speech.repeatSentence = repeatEach
        speech.speakSequence(items.map(\.english), speed: listenSpeed,
                             voiceID: listenVoiceID.isEmpty ? nil : listenVoiceID,
                             startAt: startIndex)
        showPlayer = true
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if passages.isEmpty {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "brain",
                        description: Text("Mac(Claude Code)から英文を取り込むと、ここに表示されます。")
                    )
                } else {
                    let visible = visiblePassages
                    List {
                        // 行ごとに一覧を検索し直さないよう、番号は enumerated で受け取る
                        ForEach(Array(visible.enumerated()), id: \.element.persistentModelID) { index, passage in
                            HStack(spacing: 8) {
                                statusBadge(passage.memorizationStatus)
                                Text(rowText(for: passage))
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                // 何件目か(●/100)。覚えた!を隠していても番号は全体基準
                                Text("\(index + 1)/\(visible.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            // 見えない NavigationLink でシェブロンなしのカード遷移にする
                            .background(
                                NavigationLink(value: passage) { EmptyView() }
                                    .opacity(0)
                            )
                            // 長押しドラッグ時はグレーのカード部分だけを持ち上げる
                            .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            // 右スワイプでこの英文から連続再生(途中から再生)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    startPlayback(from: passage)
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .tint(.blue)
                            }
                            // 「削除」の文字なし、ゴミ箱アイコンだけのスワイプ削除
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(passage)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationDestination(for: Passage.self) { passage in
                RecallSessionView(passage: passage)
            }
            .toolbar {
                // 表示中の英文を連続再生 / 停止(アメリカ英語で1文ずつ滑らかに)
                ToolbarItem(placement: .topBarLeading) {
                    // いま鳴っているのが暗記の音声なら停止。そうでなければ(何も鳴っていない or
                    // 音読の音声がミニプレイヤーで鳴っている)ワンクリックで暗記を再生開始する
                    Button {
                        if recallActive {
                            speech.stop()
                            AudioSequencePlayer.shared.stop()
                        } else {
                            startPlayback(from: nil)
                        }
                    } label: {
                        Image(systemName: recallActive ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundStyle(recallActive ? .red : Color.accentColor)
                    }
                    .disabled(!recallActive && visibleItems.isEmpty)
                }
                // 覚えた!の表示/非表示(緑=表示中、グレー=非表示中)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hideMemorized.toggle()
                        }
                    } label: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(hideMemorized ? Color(.systemGray3) : Color.green)
                    }
                }
            }
            // 連続再生中は、今読んでいる英文を開いて表示するプレイヤーを出す
            .fullScreenCover(isPresented: $showPlayer) {
                SentencePlayerView(items: playerItems)
            }
            // 事前生成音声のプレイヤー(音読タブと同じ画面)。
            // sheetにすることで「下スワイプで閉じる=再生は続けてミニプレイヤーへ」ができる
            .sheet(isPresented: $showAudioPlayer) {
                AudioPlayerView()
            }
            // 暗記セッションに入る時などは連続再生を止める
            .onChange(of: path) { _, newPath in
                if !newPath.isEmpty {
                    speech.stop()
                    AudioSequencePlayer.shared.stop()
                }
            }
            // 再生中かどうかだけを監視する(プレイヤー全体を @ObservedObject にしない)
            .onReceive(SpeechSynthesisService.shared.$isPlayingSequence
                .combineLatest(AudioSequencePlayer.shared.$isPlayingSequence)) { tts, audio in
                let playing = tts || audio
                if isPlayingSequence != playing { isPlayingSequence = playing }
            }
            // 暗記の音声が鳴っているか(音読の音声を鳴らしている時は false → 暗記ボタンは再生開始になる)
            .onReceive(AudioSequencePlayer.shared.$isPlayingSequence
                .combineLatest(AudioSequencePlayer.shared.$source)) { playing, src in
                let active = playing && src == .recall
                if recallActive != active { recallActive = active }
            }
        }
        // 詳細画面(階層あり)ではタブバーを隠す。
        // iOS 18 では画面側の指定が効かないことがあるため、タブのルートで出し分ける
        .toolbar(path.isEmpty ? .visible : .hidden, for: .tabBar)
        .animation(.easeInOut(duration: 0.2), value: path.isEmpty)
    }

    /// 一覧には日本語訳の先頭部分を表示する(和訳がなければタイトル)
    private func rowText(for passage: Passage) -> String {
        let japanese = passage.japaneseFullText.replacingOccurrences(of: "\n", with: " ")
        return japanese.isEmpty ? passage.title : japanese
    }

    /// 長押しドラッグでの並べ替え。覚えた!を非表示中でも、
    /// 隠れている項目の位置は保ったまま表示中の項目だけ並べ替える
    private func move(from source: IndexSet, to destination: Int) {
        var visible = visiblePassages
        visible.move(fromOffsets: source, toOffset: destination)

        var all = passages
        if hideMemorized {
            var it = visible.makeIterator()
            for i in all.indices where all[i].memorizationStatus != .memorized {
                if let next = it.next() { all[i] = next }
            }
        } else {
            all = visible
        }
        for (index, passage) in all.enumerated() {
            passage.sortIndex = index
        }
        try? context.save()
    }

    private func delete(_ passage: Passage) {
        context.delete(passage)
        try? context.save()
    }

    @ViewBuilder
    private func statusBadge(_ status: MemorizationStatus) -> some View {
        // 「どちらでもない」はアイコンなし
        if status != .normal {
            Image(systemName: status.iconName)
                .font(.footnote)
                .foregroundStyle(status.color)
        }
    }
}

extension MemorizationStatus {
    var color: Color {
        switch self {
        case .needsReview: .red
        case .normal: .orange
        case .memorized: .green
        }
    }
}
