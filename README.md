# MemorizeEnglishSentences — 英文暗記 iOS アプリ 実装プラン

このリポジトリは英文暗記用の iOS アプリを新規開発するためのものです。以下は要件確認済みの実装プランです。

> **Claude Code への指示**: この README のプランに従って iOS アプリを実装してください。要件・技術選定はすべてユーザーと確認済みなので、再確認せずにこのプラン通りに進めて構いません。

## Context

日本語話者・英語学習者が英文を暗記するための iOS 専用アプリ(Web・バックエンドなし)。

確認済み要件:

**共通**
1. 英文をアプリ内にローカル保存し、ブロック(1文)単位で管理
2. 登録フロー: 英文は**音声入力**(編集・ペーストも可)、日本語訳は **Apple 純正 Translation フレームワーク (iOS 18)** で自動生成(無料・API キー不要・言語 DL 後はオフライン動作)

**音読タブ**
3. ブロックをタップ → 上に英文、下に日本語訳を表示
4. 単語をタップ → 意味(日本語)+発音読み上げ (AVSpeechSynthesizer)
5. **文を長押し → SVC/SVO 構文解析を表示**(どこが主語・動詞・補語か)— **Claude API(クラウド LLM)** を使用

**暗記タブ**
6. 日本語訳だけを全文表示 → **音声入力で英文全文を一気に回答**、または「答えを見る」
7. 回答後、正解英文と音声入力の**差分を表示**
8. 差分の履歴を蓄積し、**間違えやすい箇所を分析・表示**

⚠️ 制約: **Translation フレームワークは iOS シミュレータ非対応 → 動作確認は実機 (iOS 18+) 必須**。構文解析のみネット接続+ Anthropic API キー(設定画面で入力)が必要で、それ以外は完全オフラインで動作すること。

## 技術スタック

- iOS 18+ / SwiftUI / SwiftData。外部依存ゼロ(純正: `Translation`, `Speech`, `AVFoundation`, `NaturalLanguage` + Claude API は URLSession 直叩き)
- pbxproj は **Xcode 16 の PBXFileSystemSynchronizedRootGroup 方式 (objectVersion = 77)** — フォルダ同期でファイル毎エントリ不要。`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_KEY_NSMicrophoneUsageDescription` / `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription`(日本語文言)。`SWIFT_VERSION = 5.0`、`TARGETED_DEVICE_FAMILY = 1`(iPhone のみ)、`CODE_SIGN_STYLE = Automatic`
- Claude API: `POST https://api.anthropic.com/v1/messages`、ヘッダ `x-api-key` / `anthropic-version: 2023-06-01` / `content-type: application/json`、モデル `claude-opus-5`、**structured outputs**(`output_config: {format: {type: "json_schema", schema: ...}}`)で解析結果を確実に JSON 取得。`stop_reason` を確認してから content を読む。API キーは Keychain 保存

## ファイル構成

```
MemorizeEnglishSentences.xcodeproj/project.pbxproj
MemorizeEnglishSentences/                            # 同期対象フォルダ
├── MemorizeEnglishSentencesApp.swift                # @main, ModelContainer, TabView
├── Assets.xcassets/
├── Models/Models.swift          # Passage, Block, WordCacheEntry, RecallAttempt, SyntaxCacheEntry
├── Services/
│   ├── SpeechRecognitionService.swift               # SFSpeechRecognizer + AVAudioEngine
│   ├── SpeechSynthesisService.swift                 # AVSpeechSynthesizer wrapper
│   ├── TextSplitter.swift                           # NLTokenizer 文単位分割
│   ├── WordTokenizer.swift                          # タップ可能単語トークン化+正規化
│   ├── DiffService.swift                            # 単語単位アラインメント(暗記の差分)
│   ├── ClaudeAPIService.swift                       # URLSession で構文解析 API 呼び出し
│   └── KeychainHelper.swift                         # API キー保存
├── Views/
│   ├── RootTabView.swift                            # タブ: 音読 / 暗記 / 設定
│   ├── Reading/ (PassageListView, AddPassageView, TranslateAndSaveView,
│   │             ReadingView, BlockCardView, WordPopupView, SyntaxAnalysisView)
│   ├── Recall/ (RecallListView, RecallSessionView, RecallDiffView, MistakeAnalysisView)
│   ├── SettingsView.swift                           # API キー入力・説明
│   └── Components/ (FlowLayout.swift, DictationButton.swift)
└── Support/TranslationAvailability.swift
+ .gitignore
```

## データモデル (SwiftData)

- `Passage { title, createdAt, blocks: [Block] (cascade delete) }` — 順序は `Block.index` で管理(SwiftData は配列順序を保持しない)
- `Block { index, englishText, japaneseText?, passage }` — `nil` = 未翻訳(閲覧時に遅延リトライ)
- `WordCacheEntry { word (unique・正規化済), japanese, updatedAt }` — 単語訳キャッシュ(オフライン・即時表示)
- `RecallAttempt { passage, date, recognizedText, opsJSON }` — opsJSON は単語アラインメント結果(match/sub/del/ins と正解側単語位置)を JSON 文字列で保存 → 間違い分析の元データ
- `SyntaxCacheEntry { sentenceHash (unique), sentence, resultJSON, updatedAt }` — 構文解析キャッシュ(同じ文の再解析で課金しない)

## 画面フロー

**RootTabView**: 「音読」「暗記」「設定」の 3 タブ。

### 音読タブ
1. **PassageListView**: `@Query` 一覧・スワイプ削除・`+` で登録シート
2. **AddPassageView**(シート内 3 ステップ):
   - ① 音声入力/編集: TextEditor(編集・ペースト可)+マイクボタン。部分認識結果をライブ表示、確定テキストをエディタに追記
   - ② 文分割プレビュー: `TextSplitter.split()` の結果をカード一覧表示。前ブロックとの結合・個別編集可
   - ③ 翻訳して保存 (`TranslateAndSaveView`): 一括翻訳の進捗をライブ表示 → 保存。失敗時は「翻訳せずに保存」を提示
3. **ReadingView**: ブロックカードをタップで展開(**上に英文・下に和訳**)、再タップで閉じる。「すべて表示/隠す」ボタン、ブロック読み上げボタン。未翻訳ブロックは表示時に再翻訳
4. 単語タップ → **WordPopupView**(bottom sheet, `presentationDetents([.height(220)])`): 単語・日本語訳(キャッシュ→なければ翻訳して保存)・発音ボタン(通常速+ゆっくり rate 0.3)
5. **ブロック(文)を長押し → SyntaxAnalysisView(シート)**: Claude API で解析 →
   - 文型ラベル(例: 第3文型 SVO)
   - 文を要素ごとに色分け表示: S=青 / V=赤 / O=緑 / C=オレンジ / 修飾語=グレー(FlowLayout 再利用、要素チップ+役割ラベル)
   - 日本語での構造解説
   - JSON スキーマ: `{pattern: "SV|SVC|SVO|SVOO|SVOC", elements: [{text, role: "S|V|O|C|M|Aux", note_ja}], explanation_ja}`
   - キャッシュヒット時は即表示。API キー未設定/オフライン時は設定タブへの誘導メッセージ

### 暗記タブ
1. **RecallListView**: 文章一覧(各文章の直近正答率も表示)
2. **RecallSessionView**: **日本語訳を全文表示**。下部に「🎤 音声で回答」「答えを見る」
   - 音声で回答: 英語 (en-US) で全文を一気にディクテーション。認識テキストをライブ表示。オンデバイス認識優先+認識タスクが final になったら自動再開して長文対応(セグメント連結)。停止ボタンで確定。キーボード入力(TextField)でも回答可
   - 答えを見る: 正解英文を表示(記録は閲覧のみ)
3. **RecallDiffView**(回答確定後): 正解英文を基準に差分ハイライト
   - 一致=緑 / 言えなかった(欠落・誤り)=赤 / 余分に言った語=取り消し線オレンジで挿入表示
   - 正答率 %(一致語数 ÷ 正解語数)、認識テキスト全文も下に表示
   - `DiffService` の ops を `RecallAttempt` に保存
4. **MistakeAnalysisView**: 蓄積した RecallAttempt を集計
   - 正解英文をヒートマップ表示: 間違え頻度が高い単語ほど濃い赤背景
   - 「間違えやすい箇所 TOP」リスト(単語、ミス回数/挑戦回数)
   - 試行履歴(日付・正答率の推移)

### 設定タブ
- Anthropic API キー入力(Keychain 保存)、構文解析の説明(従量課金・ネット必要)、翻訳言語データの案内

## 実装の要点(API の落とし穴)

- **Translation**: `TranslationSession` は直接生成不可 — SwiftUI の `.translationTask(configuration)` 経由のみ。`source: en / target: ja` を明示(自動判定は短文で誤る)。`session.prepareTranslation()` で言語 DL プロンプト表示。一括は `session.translate(batch:)`(AsyncSequence・順序不定 → `clientIdentifier` にブロック index)。再実行は `configuration?.invalidate()`。事前チェックは `LanguageAvailability().status(from:to:)`
- **FlowLayout**: カスタム `Layout` で単語/チップを折り返し配置(単語タップと構文解析表示で共用)。トークン配列は body 内で再計算しない。`WordTokenizer` は `NLTokenizer(unit: .word)` で単語範囲を取得し、表示用は句読点を保持、翻訳/照合用は小文字化・句読点除去
- **SFSpeechRecognizer**: en-US、`addsPunctuation = true`(文分割の要)、可能なら `requiresOnDeviceRecognition`。`inputNode.outputFormat(forBus: 0)` を使用(フォーマットのハードコード禁止)。再開時はタップ除去必須。暗記モードは final 後の自動 restart で約 1 分制限を回避。コールバックは MainActor へホップ
- **AVSpeechSynthesizer**: synthesizer はシングルトンで長寿命保持(ローカル変数だと解放されて無音になる)。AudioSession は録音時 `.playAndRecord`・再生時 `.playback` に切替、録音中の読み上げは UI で禁止
- **TextSplitter**: `NLTokenizer(unit: .sentence)` で 1 文 = 1 ブロック。3 語未満の断片は前ブロックへ結合。空行があれば先に段落分割。句読点が全く無い場合は約 25 語毎のチャンク分割にフォールバック
- **DiffService**: 正規化(小文字化・句読点除去)した単語列で Wagner-Fischer(編集距離)アラインメント。表示は正解側の表示トークンにマッピング。短縮形 ("I'm" vs "I am") はまず別語扱いのままで OK
- **ClaudeAPIService**: URLSession + async/await。`max_tokens: 2000` 非ストリーミング。structured outputs で JSON 保証。エラー時(401=キー不正 / 429 / `stop_reason: "refusal"` / オフライン)は日本語メッセージ表示。SyntaxCacheEntry でキャッシュし再課金を防ぐ

## 実装順序

1. `.gitignore` + `project.pbxproj` + Assets + App/RootTabView(最初にビルド可能な空アプリを作る)
2. `Models.swift` + PassageListView
3. TextSplitter / WordTokenizer / FlowLayout / DiffService(純ロジック)
4. SpeechRecognitionService + AddPassageView
5. TranslateAndSaveView + TranslationAvailability
6. ReadingView + BlockCardView + SpeechSynthesisService + WordPopupView
7. KeychainHelper + ClaudeAPIService + SyntaxAnalysisView + SettingsView
8. RecallListView + RecallSessionView + RecallDiffView + MistakeAnalysisView

各段階でビルドが通ることを確認しながら進めること。

## 動作確認手順(実機)

1. Xcode 16+ で開く → Signing & Capabilities で自分の Team を選択・Bundle ID を一意なものに変更
2. **実機 iPhone (iOS 18+) でビルド&実行**(翻訳はシミュレータでは動かない)
3. 初回: マイク・音声認識の許可 → 初回翻訳時に英日翻訳言語データの DL を承認(設定 → アプリ → 翻訳 から事前 DL も可)
4. 構文解析を使う場合: console.anthropic.com で API キーを取得 → 設定タブに入力
5. スモークテスト: 音声入力で 2〜3 文登録 → 分割確認 → 翻訳 → 音読タブ(ブロックタップで英+訳、単語タップで意味+発音、長押しで構文解析)→ 暗記タブ(和訳を見て音声で全文回答 → 差分表示 → 数回繰り返して間違い分析)→ アプリ再起動で永続化確認 → 機内モードで翻訳・音声入力が動くこと(構文解析以外)

## リスク対応

- 翻訳不可(シミュレータ/言語 DL 拒否): 事前チェック+「翻訳せずに保存」+閲覧時の遅延リトライ
- マイク許可拒否: 設定アプリへの誘導ビュー。テキスト入力・ペーストは常に代替手段
- 長文ディクテーションの認識打ち切り: オンデバイス認識優先+自動 restart+手動停止まで継続
- API キー未設定/オフラインの構文解析: 機能単位で無効化+設定誘導(アプリ本体は全機能オフライン動作)
- 構文解析コスト: SyntaxCacheEntry でキャッシュ、同一文の再解析は課金なし
