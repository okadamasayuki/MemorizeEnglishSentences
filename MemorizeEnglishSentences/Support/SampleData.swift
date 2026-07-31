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

    /// ユーザーが撮影した書籍ページから読み取った暗記用の例文(英文, 和訳)
    private static let bookPhotoSentences: [(String, String)] = [
        ("Tom finally realized his dream of becoming an astronaut, but at the expense of many other things.",
         "トムはついに宇宙飛行士になるという夢を実現したが、他の多くのことを犠牲にした。"),
        ("If city life gives you stress and fatigue, it is best to relax in the mountains or on beaches in order to relieve them.",
         "都会の生活でストレスや疲れがたまったら、それを解消するために山の中や海辺でのんびりするのが一番だ。"),
        ("In Japan, women have difficulty getting promoted or returning to their jobs after giving birth and raising their children.",
         "日本では、女性は出産して子供を育てたあとに昇進したり職場に復帰したりするのが難しい。"),
        ("In the U.S., parents drive their children everywhere until they are old enough to get a driver's license.",
         "アメリカでは、子供が運転免許を取れる年齢になるまで、親がどこへ行くにも車で送っていく。"),
        ("\"Excuse me. Could you tell me how to get to the post office?\" \"Go straight for two blocks, then turn left. You'll find it on your right.\"",
         "「すみません、郵便局への行き方を教えていただけますか。」「2筋まっすぐ行って、左に曲がってください。右側にありますよ。」"),
        ("\"What do you think of our new teacher?\" \"There is something about her that attracts me.\"",
         "「新しい先生のことをどう思う?」「彼女にはどこか惹かれるところがあるんだ。」"),
        ("People who do not feel guilty about occupying two seats on a crowded train really make me angry.",
         "混んだ電車で2人分の席を占領して平気な人には、本当に腹が立つ。"),
        ("When I left the office for lunch, I ran into an old friend from high school.",
         "昼食をとりに会社を出たとき、高校時代の旧友にばったり出会った。"),
        ("This music is worth listening to over and over again. I recommend it.",
         "この音楽は何度も繰り返し聴く価値がある。ぜひ聴いてみたらいい。"),
        ("Bear in mind that if you have enthusiasm, you can succeed in anything.",
         "熱意があればどんなことでも成功できるということを、心に留めておきなさい。"),
        ("Everyone is born with a talent. The question is whether they can find it or not.",
         "人は誰でも生まれながらに才能を持っている。問題は、それを見つけられるかどうかだ。"),
        ("Teeth play an important role in your health. If you want to stay healthy, you should brush your teeth after every meal.",
         "歯は健康に重要な役割を果たしている。健康でいたいなら、毎食後に歯を磨くべきだ。"),
    ]

    /// ユーザーが撮影した書籍ページ(第2弾・88枚)から読み取った例文。掲載ページ順。
    private static let bookPhotoSentences2: [(String, String)] = [
        ("It would be dangerous to drink two bottles of whiskey and drive a car.",
         "ウイスキーをボトル2本も空けて車を運転するのは危険だろう。"),
        ("It is very dangerous to cross a busy street before the light turns green.",
         "信号が青に変わる前に交通量の多い通りを渡るのはとても危険だ。"),
        ("It is really pleasant to take a walk early in the morning, listening to birds sing.",
         "早朝に鳥のさえずりを聴きながら散歩するのは実に気持ちがいい。"),
        ("Most Japanese high school students go to a cram school to prepare for college entrance exams.",
         "日本の高校生の大半は、大学入試に備えて塾に通っている。"),
        ("When waiting for the elevator to come or the traffic light to change, most Japanese people become irritated in only thirty seconds.",
         "エレベーターや信号を待つとき、たいていの日本人はわずか30秒でイライラしてくる。"),
        ("An elderly woman sitting next to me on the train asked me where I was going.",
         "列車で隣に座っていたおばあさんが、私にどこへ行くのかと尋ねた。"),
        ("Tom told us that we should rent a car to get around the city because the public transportation was inconvenient.",
         "公共交通機関が不便だから、街を動きまわるにはレンタカーを借りるべきだとトムは私たちに言った。"),
        ("Everyone should be free to decide when to get married and whether to have children.",
         "いつ結婚するか、子供を持つかどうかは、誰もが自由に決められるべきだ。"),
        ("It is impossible to predict where and when there will be a major earthquake.",
         "大地震がいつどこで起こるかを予測することは不可能だ。"),
        ("Tom insisted that everything would be all right, but I could not help feeling worried.",
         "トムは万事うまくいくと言い張ったが、私は心配せずにはいられなかった。"),
        ("It never occurred to me that my remark might hurt her feelings.",
         "僕の発言が彼女を傷つけるかもしれないとは、まったく思いもしなかった。"),
        ("\"Tom, dinner is ready.\" \"OK, Mom. I'm coming.\"",
         "「トム、夕食の準備ができたわよ。」「わかった、母さん。今行くよ。」"),
        ("I will call you when I get to Narita Airport.",
         "成田空港に着いたら電話するよ。"),
        ("If you take the train to Tokyo Disneyland from here, you have to change three times.",
         "ここから東京ディズニーランドまで電車で行くなら、3回乗り換えなければならない。"),
        ("I have decided to look for a job abroad when I graduate from college.",
         "大学を卒業したら海外で仕事を探すことに決めた。"),
        ("This dryer doesn't work. Something seems to be wrong with it.",
         "このドライヤーは動かない。どこかがおかしいようだ。"),
        ("The best thing about my stay with an American family was that the parents treated me just like their daughter.",
         "アメリカでのホームステイで一番よかったのは、両親が私を実の娘のように扱ってくれたことだ。"),
        ("I lived in Canada for three years when I was in my teens because my father was transferred there.",
         "父がカナダに転勤になったので、私は10代の頃3年間カナダに住んでいた。"),
        ("The Internet is widely used, so sales of personal computers have been rapidly increasing over the last few years.",
         "インターネットが広く使われているので、ここ数年パソコンの売り上げが急速に伸びている。"),
        ("I have often heard Tom boast that he is very good at swimming, but I have never actually seen him swim.",
         "トムが水泳が得意だと自慢するのは何度も聞いたことがあるが、実際に泳ぐのを見たことは一度もない。"),
        ("It has been only a week since I began a part-time job at a convenience store, but I am already used to it.",
         "コンビニでアルバイトを始めてまだ1週間しか経っていないが、もう慣れてしまった。"),
        ("When I got on the train this morning, I could not find an empty seat.",
         "今朝電車に乗ったら、空いている席が見つからなかった。"),
        ("I am not wearing glasses now, so I cannot make out what the sign says.",
         "今めがねをかけていないので、看板に何と書いてあるのか判別できない。"),
        ("Less than twenty-four hours after I return to my hometown, without realizing it, I start to talk in the local dialect.",
         "故郷に帰って24時間も経たないうちに、知らず知らず地元の方言で話し始める。"),
        ("Humans learn to express what they think by the age of five or six.",
         "人間は5、6歳までに、考えていることを表現できるようになる。"),
        ("Thanks to the map you drew me the other day, I managed to get here without getting lost.",
         "先日あなたが描いてくれた地図のおかげで、道に迷わずにここまで来られた。"),
        ("Last summer I took two weeks off, and went on a trip to Europe with my wife.",
         "昨年の夏、2週間の休みを取って妻とヨーロッパ旅行に行った。"),
        ("Bob had changed a lot, so when I saw him at a class reunion, I did not recognize him.",
         "ボブはすっかり変わっていたので、クラス会で見かけたとき、彼だとわからなかった。"),
        ("When I visited my hometown for the first time in twenty years, I found that it was no longer what it used to be.",
         "20年ぶりに故郷を訪れたら、そこはもはや昔の姿ではなくなっていた。"),
        ("I stayed up till four last night preparing for the math lesson, so I feel very sleepy.",
         "昨夜は数学の予習で4時まで起きていたので、とても眠い。"),
        ("I have finished reading the novel I borrowed from the library yesterday, so now I have nothing to do.",
         "昨日図書館から借りた小説を読み終えてしまったので、今は何もすることがない。"),
        ("If you had taken this medicine and stayed in bed, you would probably have got well in two or three days.",
         "この薬を飲んで寝ていれば、2、3日でおそらくよくなっていただろうに。"),
        ("The teacher says that we should wait here for a while because if we left now, we might get caught in a thunderstorm on the way.",
         "今出発したら途中で雷雨に見舞われるかもしれないから、しばらくここで待つべきだと先生は言っている。"),
        ("People wish they could live forever and never become older. However, if this wish came true, there would be too many people on the earth.",
         "人はいつまでも年をとらずに生きられたらいいのにと思う。しかし、もしこの願いが実現したら、地球上は人であふれてしまうだろう。"),
        ("Ann looks happy. Something good must have happened to her.",
         "アンはうれしそうだ。何かいいことがあったに違いない。"),
        ("If you have been to old European cities, you must have been impressed by the beautiful streets.",
         "ヨーロッパの古い都市に行ったことがあるなら、その美しい町並みに感動したに違いない。"),
        ("Without fossil fuels such as oil and coal, the history of the 20th century would have been completely different.",
         "石油や石炭といった化石燃料がなかったら、20世紀の歴史はまったく違ったものになっていただろう。"),
        ("Some students coming to the library act as if they are in a café.",
         "図書館に来る学生の中には、まるでカフェにいるかのように振る舞う者がいる。"),
        ("When I was a child, I often wished my house were a little larger.",
         "子供の頃、家がもう少し広ければいいのにとよく思ったものだ。"),
        ("I would like to work as a volunteer helping victims of natural disasters, such as floods or earthquakes.",
         "洪水や地震などの自然災害の被災者を助けるボランティアとして働きたい。"),
        ("Tom has nice drums, and he never lets anyone else play them.",
         "トムはいいドラムを持っているが、決して他人には使わせない。"),
        ("At first I thought Tom was joking, but later I realized he was serious.",
         "最初トムは冗談を言っているのだと思ったが、あとで本気だとわかった。"),
        ("Last Sunday I tried making some Italian food for the first time, and it was delicious.",
         "この前の日曜日に初めてイタリア料理を作ってみたら、とてもおいしかった。"),
        ("Some people say that they do not like summer because it is so hot that they do not feel like doing anything. However, I like the heat of summer because I can swim in the sea.",
         "夏は暑すぎて何もする気になれないから嫌いだと言う人もいる。しかし、私は海で泳げるから夏の暑さが好きだ。"),
        ("James came to Japan eight years ago not only because he wanted to visit temples, but also because he had a Japanese girlfriend.",
         "ジェームズが8年前に日本に来たのは、寺を見たかったからだけでなく、日本人の恋人がいたからでもある。"),
        ("I am against human cloning. That is because it could cause duplication of dictators.",
         "私はヒトのクローン化に反対だ。なぜなら、独裁者の複製を生み出しかねないからだ。"),
        ("The graph shows that in Japan the birth rate has been decreasing since 1985. This decrease is partly because it costs a lot of money to raise children.",
         "グラフによると、日本では1985年から出生率が下がり続けている。この減少の理由の1つは、子育てに多額のお金がかかることだ。"),
        ("I apologized to Ann for being late, but she did not forgive me.",
         "遅刻したことをアンに謝ったが、彼女は許してくれなかった。"),
        ("During the math class, my cell phone began to ring, and the teacher severely scolded me. I regretted that I had not turned it off.",
         "数学の授業中に携帯電話が鳴り出して、先生にひどく叱られた。電源を切っておかなかったことを後悔した。"),
        ("I am so busy doing the housework every day that I have no time to see a movie.",
         "毎日家事で忙しくて、映画を見る時間もない。"),
        ("This wooden desk is too heavy for me to carry upstairs alone.",
         "この木の机は重すぎて、私1人では2階まで運べない。"),
        ("While traveling in Europe, I was disappointed that wherever I went, there were many Japanese tourists.",
         "ヨーロッパを旅行中、どこへ行っても日本人観光客が大勢いるのにがっかりした。"),
        ("I was very happy when I saw my mother going to work wearing the earrings I had bought her.",
         "私が買ってあげたイヤリングを着けて母が仕事に出かけるのを見たとき、とてもうれしかった。"),
        ("If you expect that schools only teach academic subjects, then this proves that you do not understand what schools are for.",
         "学校が勉強だけを教える場所だと思っているなら、それは学校が何のためにあるのかわかっていない証拠だ。"),
        ("Most Japanese people spend most of their time working to live.",
         "たいていの日本人は、時間の大半を生きるために働くことに使っている。"),
        ("Japanese people usually express their feelings as indirectly as possible so that they will not offend others.",
         "日本人はふつう、他人の気持ちを傷つけないように、できるだけ間接的に感情を表現する。"),
        ("Whether a college is good or bad depends not only on how many books its library has and how good they are. It also depends on how intelligent its teachers and students are.",
         "大学の良し悪しは、図書館の蔵書の数と質だけで決まるのではない。教師と学生にどれだけ知性があるかにもよる。"),
        ("The increase in the amount of CO2 in the atmosphere is closely connected with global warming.",
         "大気中の二酸化炭素の量の増加は、地球温暖化と密接に関係している。"),
        ("The more modern civilization advances, the longer we are forced to stay up at night, and the less sleep we get.",
         "現代文明が進歩すればするほど、私たちは夜遅くまで起きていることを強いられ、睡眠時間は少なくなる。"),
        ("Doctors and teachers are alike in that both of them deal not with things but with people.",
         "医師と教師は、どちらも物ではなく人を相手にするという点で似ている。"),
        ("Professional baseball is far more exciting at a stadium than on TV.",
         "プロ野球はテレビで見るより球場で見る方がはるかに面白い。"),
        ("This motorbike is about twice as expensive in the U.K. as in Japan.",
         "このバイクは、イギリスでは日本の約2倍の値段だ。"),
        ("Just because young people today read less than they used to, it does not always follow that they are less eager to learn.",
         "今の若者が昔より本を読まなくなったからといって、学ぶ意欲が落ちたとは必ずしも言えない。"),
        ("Frankly speaking, the entrance exams I took yesterday were far more difficult than I had expected.",
         "率直に言って、昨日受けた入学試験は思っていたよりはるかに難しかった。"),
        ("A lot of people have personal computers, but very few of them know how to use them effectively.",
         "パソコンを持っている人は多いが、効果的な使い方を知っている人はごくわずかだ。"),
        ("A lot of housewives complain that prices are too high.",
         "多くの主婦が、物価が高すぎると不平を言っている。"),
        ("In some countries people have too much food, while in others tens of thousands of children are starving.",
         "食糧が有り余っている国もあれば、何万人もの子供が飢えている国もある。"),
        ("Don't forget to turn off the air conditioner before you go to bed, or you'll catch a cold.",
         "寝る前にエアコンを消すのを忘れないで。さもないと風邪をひくよ。"),
        ("There is a saying that a cold can cause a variety of diseases. Take care not to catch a cold.",
         "風邪は万病のもとと言われている。風邪をひかないように気をつけなさい。"),
        ("On the Internet, you can exchange thoughts and ideas with people all over the world, regardless of their age, sex, or nationality.",
         "インターネットでは、年齢や性別や国籍の違いを超えて、世界中の人と意見を交換できる。"),
        ("However much exercise you get, you won't lose weight unless you count your calories.",
         "どんなに運動しても、カロリー計算をしなければ痩せられない。"),
        ("Although you believe you know a word, you may learn something new if you look it up in the dictionary.",
         "ある単語を知っていると思っていても、辞書で引いてみると新たな発見があるかもしれない。"),
        ("Some Japanese tourists lack common sense and carry a lot of cash in their backpockets.",
         "日本人観光客の中には、非常識にも多額の現金を尻ポケットに入れて持ち歩く人がいる。"),
        ("In order to stay healthy, you should have a balanced diet and get regular exercise.",
         "健康でいるためには、バランスのとれた食事をとり、定期的に運動すべきだ。"),
        ("If you live in a developing country for a while, you have an opportunity to look at Japan from a different point of view.",
         "発展途上国でしばらく暮らせば、日本を違った角度から見る機会が得られる。"),
        ("It is not until you go abroad that you realize how many neon lights there are in big Japanese cities.",
         "外国に行って初めて、日本の大都市にどれほど多くのネオンがあるかに気づく。"),
        ("It is a pity that many Japanese people mistakenly believe that they have only to speak English to be internationally-minded.",
         "多くの日本人が、英語を話しさえすれば国際感覚が身につくと勘違いしているのは残念だ。"),
        ("It is surprising that many Americans do not care how you pronounce English as long as they can understand what you are trying to say.",
         "多くのアメリカ人は、言いたいことが伝わる限り英語の発音を気にしないというのは驚きだ。"),
        ("The best things you can do to protect nature are to reduce garbage and to use environmentally friendly products.",
         "自然を守るためにできる最善のことは、ゴミを減らすことと、環境にやさしい製品を使うことだ。"),
        ("It is said that seven out of ten young Japanese people do not believe in religion.",
         "日本の若者の10人に7人は宗教を信じていないと言われている。"),
        ("Ways of greeting vary from country to country. In Japan, bowing is more common than shaking hands.",
         "あいさつの仕方は国によって異なる。日本では握手よりお辞儀の方が一般的だ。"),
        ("Hamamatsu is located east of Lake Hamana, which is famous for its beautiful scenery and delicious seafood.",
         "浜松は浜名湖の東に位置している。浜名湖は美しい景色とおいしい海の幸で有名だ。"),
        ("Quite a few elderly women look down on their husbands, who cannot do anything by themselves and ask too much of them.",
         "年配の女性の中には、1人では何もできず妻に頼りすぎる夫を見下す人も少なくない。"),
        ("The movie theater is about twenty minutes' walk from here, but it takes only five minutes to get there by subway.",
         "その映画館はここから歩いておよそ20分だが、地下鉄なら5分で着く。"),
        ("It cost ten thousand yen to have this bike repaired.",
         "この自転車を修理してもらうのに1万円かかった。"),
        ("There are four people in my family. Our apartment is on the fifth floor of this building.",
         "私の家族は4人家族です。私たちのアパートはこのビルの5階にあります。"),
        ("The tendency for young people to believe everything that is printed is nothing new.",
         "若者が活字になっているものを何でも信じてしまう傾向は、今に始まったことではない。"),
        ("When I was studying in Paris, a famous painter bought me a meal at a first-class restaurant.",
         "パリで学んでいたとき、ある有名な画家が一流レストランで食事をごちそうしてくれた。"),
    ]

    /// 書籍ページ写真から読み取った例文を暗記タブへ一度だけ投入する。
    /// 既に同じ英文が登録されている場合は重複させない。
    static func seedBookPhotosIfNeeded(context: ModelContext) {
        seedRecallSentences(bookPhotoSentences, key: "didSeedBookPhotos_v1", context: context)
        seedRecallSentences(bookPhotoSentences2, key: "didSeedBookPhotos_v2", context: context)
    }

    private static func seedRecallSentences(_ sentences: [(String, String)], key: String, context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let descriptor = FetchDescriptor<Passage>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingEnglish = Set(
            existing.filter { $0.purpose == .recall }.map { $0.englishFullText }
        )

        // createdAt をずらして、一覧に書籍と同じ順で上から並ぶようにする
        let base = Date.now
        for (offset, pair) in sentences.enumerated() where !existingEnglish.contains(pair.0) {
            let passage = Passage(title: pair.1, createdAt: base.addingTimeInterval(-Double(offset)))
            passage.purpose = .recall
            context.insert(passage)
            let block = Block(index: 0, englishText: pair.0, japaneseText: pair.1)
            block.passage = passage
            context.insert(block)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }

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
