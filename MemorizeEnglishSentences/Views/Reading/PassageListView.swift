import SwiftData
import SwiftUI

/// 音読タブ。一覧を挟まず、いきなり読む画面(ReadingView)を表示する。
/// 文章の切り替えは左上のメニューから。
struct PassageListView: View {
    @Query(sort: \Passage.createdAt, order: .reverse) private var passages: [Passage]
    @State private var showingAdd = false
    @State private var selected: Passage?

    private var currentPassage: Passage? {
        if let selected, !selected.isDeleted, passages.contains(where: { $0 === selected }) {
            return selected
        }
        return passages.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let passage = currentPassage {
                    ReadingView(passage: passage)
                } else {
                    ContentUnavailableView(
                        "英文がまだありません",
                        systemImage: "book",
                        description: Text("右上の + から英文を登録しましょう。音声入力でも写真でも OK です。")
                    )
                }
            }
            .toolbar {
                if passages.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(passages) { passage in
                                Button {
                                    selected = passage
                                } label: {
                                    if passage === currentPassage {
                                        Label(passage.title, systemImage: "checkmark")
                                    } else {
                                        Text(passage.title)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd, onDismiss: {
                // 新しく追加した文章をすぐ表示する
                selected = nil
            }) {
                AddPassageView()
            }
        }
    }
}
