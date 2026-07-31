import Foundation
import SwiftData

/// 初回起動時にサンプル英文を登録する(削除後に復活しないよう UserDefaults でガード)
enum SampleData {
    private static let seededKey = "didSeedSampleData_v2"

    private static let samples: [(title: String, sentences: [(String, String)])] = [
        (
            "【例】北風と太陽",
            [
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
            ]
        ),
        (
            "【例】自己紹介",
            [
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
            ]
        ),
        (
            "【例】空港での会話",
            [
                ("Excuse me, could you tell me where the boarding gate is?",
                 "すみません、搭乗ゲートがどこか教えていただけますか。"),
                ("I'd like a window seat, if possible.",
                 "できれば窓側の席をお願いします。"),
                ("How long does the flight take?",
                 "フライトはどのくらいかかりますか。"),
                ("My suitcase didn't come out, so where should I report it?",
                 "スーツケースが出てこなかったのですが、どこに届け出ればいいですか。"),
                ("Thank you so much for your help.",
                 "助けていただき本当にありがとうございます。"),
            ]
        ),
        (
            "【例】英語の名言",
            [
                ("The best way to predict the future is to invent it.",
                 "未来を予測する最善の方法は、自らそれを創り出すことだ。"),
                ("It always seems impossible until it is done.",
                 "何事も、成し遂げるまでは不可能に思えるものだ。"),
                ("If you can dream it, you can do it.",
                 "夢見ることができれば、それは実現できる。"),
                ("Success is not final, and failure is not fatal; it is the courage to continue that counts.",
                 "成功は終わりではなく、失敗は致命的ではない。大切なのは続ける勇気だ。"),
                ("Stay hungry, stay foolish.",
                 "ハングリーであれ、愚か者であれ。"),
            ]
        ),
    ]

    /// ステータス機能導入時に「要復習」で入った既存データを一度だけ「普通」に揃える
    static func applyDefaultStatusIfNeeded(context: ModelContext) {
        let key = "didDefaultStatusToNormal"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let descriptor = FetchDescriptor<Passage>()
        if let passages = try? context.fetch(descriptor) {
            for passage in passages where passage.memorizationStatus == .needsReview {
                passage.memorizationStatus = .normal
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// 音読と暗記のデータを独立させたときの一度きりの移行処理。
    /// それまで両タブで共有していた文章を暗記側にも複製し、暗記の記録は暗記側へ移す。
    static func splitReadingAndRecallIfNeeded(context: ModelContext) {
        let key = "didSplitReadingRecallData"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<Passage>()
        if let passages = try? context.fetch(descriptor) {
            for passage in passages where passage.purpose == .reading {
                let copy = Passage(title: passage.title, createdAt: passage.createdAt)
                copy.purpose = .recall
                copy.memorizationStatus = passage.memorizationStatus
                context.insert(copy)
                for block in passage.orderedBlocks {
                    let blockCopy = Block(
                        index: block.index,
                        englishText: block.englishText,
                        japaneseText: block.japaneseText
                    )
                    blockCopy.passage = copy
                    context.insert(blockCopy)
                }
                // 暗記の挑戦記録は暗記側の文章に付け替える
                for attempt in passage.attempts {
                    attempt.passage = copy
                }
            }
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        // 同じタイトルの文章がなければ追加する(既存インストールにも新しい例を配布できる)
        let descriptor = FetchDescriptor<Passage>()
        let existingTitles = Set((try? context.fetch(descriptor))?.map(\.title) ?? [])

        for sample in samples where !existingTitles.contains(sample.title) {
            insert(title: sample.title, sentences: sample.sentences, context: context)
        }

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
