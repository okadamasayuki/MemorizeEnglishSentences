import Foundation
import SwiftData

/// 初回起動時にサンプル英文を登録する(削除後に復活しないよう UserDefaults でガード)
enum SampleData {
    private static let seededKey = "didSeedSampleData"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let descriptor = FetchDescriptor<Passage>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard count == 0 else {
            UserDefaults.standard.set(true, forKey: seededKey)
            return
        }

        insert(
            title: "【例】北風と太陽",
            sentences: [
                ("The North Wind and the Sun were disputing which was the stronger, when a traveler came along wrapped in a warm cloak.",
                 "北風と太陽が、どちらが強いかで言い争っていると、暖かい外套を着た旅人がやって来ました。"),
                ("They agreed that the one who first made the traveler take his cloak off should be considered stronger than the other.",
                 "先に旅人に外套を脱がせた方を、より強い者と見なすことで二人は合意しました。"),
                ("Then the North Wind blew as hard as he could, but the more he blew, the more closely the traveler folded his cloak around him.",
                 "そこで北風は力いっぱい吹きつけましたが、吹けば吹くほど、旅人は外套をしっかりと身体に巻きつけました。"),
                ("At last the North Wind gave up the attempt.",
                 "ついに北風はあきらめました。"),
                ("Then the Sun shined out warmly, and immediately the traveler took off his cloak.",
                 "次に太陽が暖かく照りつけると、旅人はすぐに外套を脱ぎました。"),
                ("And so the North Wind had to admit that the Sun was the stronger of the two.",
                 "こうして北風は、太陽の方が強いと認めざるを得ませんでした。"),
            ],
            context: context
        )

        insert(
            title: "【例】自己紹介",
            sentences: [
                ("Hello, my name is Ken, and I'm from Osaka.",
                 "こんにちは、私の名前はケンで、大阪出身です。"),
                ("I have been studying English for two years.",
                 "私は 2 年間英語を勉強しています。"),
                ("My goal is to travel around the world someday.",
                 "私の目標は、いつか世界中を旅することです。"),
                ("Every morning, I read English books for thirty minutes.",
                 "毎朝、30 分間英語の本を読みます。"),
                ("Practice makes perfect.",
                 "継続は力なり。"),
            ],
            context: context
        )

        try? context.save()
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    private static func insert(title: String, sentences: [(String, String)], context: ModelContext) {
        let passage = Passage(title: title)
        context.insert(passage)
        for (index, pair) in sentences.enumerated() {
            let block = Block(index: index, englishText: pair.0, japaneseText: pair.1)
            block.passage = passage
            context.insert(block)
        }
    }
}
