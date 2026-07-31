import SwiftData
import SwiftUI

/// 単語タブ。音声教材から抽出した英語フレーズと和訳のリスト。
/// カードをタップすると和訳を表示/非表示。単語の長押しで意味ポップアップ。
struct VocabListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VocabWord.index) private var words: [VocabWord]

    @State private var expandedIDs: Set<PersistentIdentifier> = []
    @ObservedObject private var player = VocabPlayer.shared

    // 再生パターン(英単語を和訳の前後に何回読むか)
    @State private var showingPattern = false
    @AppStorage("vocabRepeatBefore") private var repeatBefore = 1
    @AppStorage("vocabRepeatAfter") private var repeatAfter = 1

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "単語がまだありません",
                        systemImage: "rectangle.stack"
                    )
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(words) { word in
                                wordRow(word)
                                    .id(word.persistentModelID)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            context.delete(word)
                                            try? context.save()
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        // 再生中の単語が常に見えるように追従スクロール
                        .onChange(of: player.currentID) { _, id in
                            if let id {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .center)
                                }
                            }
                        }
                    }
                }
            }
            .toolbar {
                // 再生パターンの設定
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingPattern = true
                    } label: {
                        Image(systemName: "repeat")
                    }
                }
                // 再生速度(タップで 1×→2×→3× を切り替え)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        player.toggleSpeed()
                    } label: {
                        Text(player.speedLabel)
                            .font(.subheadline.bold())
                    }
                }
                // リストの順に連続再生 / 停止
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if player.isPlaying {
                            player.stop()
                        } else {
                            player.play(words)
                        }
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .foregroundStyle(player.isPlaying ? Color.red : Color.accentColor)
                    }
                }
            }
        }
        .onDisappear {
            player.stop()
        }
        .sheet(isPresented: $showingPattern) {
            VStack(alignment: .leading, spacing: 20) {
                Stepper("和訳の前に英単語 \(repeatBefore) 回", value: $repeatBefore, in: 1...5)
                Stepper("和訳の後に英単語 \(repeatAfter) 回", value: $repeatAfter, in: 0...5)
                Text(patternPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding()
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
        }
    }

    /// 現在の再生パターンのプレビュー(例: 英語 → 和訳 → 英語)
    private var patternPreview: String {
        let before = Array(repeating: "英語", count: repeatBefore)
        let after = Array(repeating: "英語", count: repeatAfter)
        return (before + ["和訳"] + after).joined(separator: " → ")
    }

    private func wordRow(_ word: VocabWord) -> some View {
        let isExpanded = expandedIDs.contains(word.persistentModelID)
        let isCurrent = player.currentID == word.persistentModelID
        return VStack(alignment: .leading, spacing: 8) {
            Text(word.english)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isExpanded {
                Text(word.japanese)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                // 再生中の単語はうっすら青くハイライト
                .fill(isCurrent ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
        )
        .animation(.easeInOut(duration: 0.15), value: isCurrent)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedIDs.remove(word.persistentModelID)
                } else {
                    expandedIDs.insert(word.persistentModelID)
                }
            }
        }
        // 長押しでこの単語から連続再生を開始
        .onLongPressGesture {
            player.play(words, from: word)
        }
    }
}
