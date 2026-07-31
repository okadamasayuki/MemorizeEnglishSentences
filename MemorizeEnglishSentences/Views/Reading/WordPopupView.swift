import SwiftData
import SwiftUI
import Translation

/// 単語の意味(日本語)+発音読み上げの bottom sheet
struct WordPopupView: View {
    @Environment(\.modelContext) private var context
    let word: String

    @State private var japanese: String?
    @State private var configuration: TranslationSession.Configuration?
    @State private var failed = false

    var body: some View {
        VStack(spacing: 12) {
            Text(word)
                .font(.title2.bold())

            // 音声が聞けない場面用の読み方の目安
            let pronunciation = KatakanaPronunciation.katakana(for: word)
            if !pronunciation.isEmpty {
                Text("読み方の目安: \(pronunciation)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Group {
                if let japanese {
                    Text(japanese)
                        .font(.title3)
                } else if failed {
                    Text("翻訳できませんでした")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .frame(minHeight: 32)

            HStack(spacing: 12) {
                Button {
                    SpeechSynthesisService.shared.speak(word)
                } label: {
                    Label("発音", systemImage: "speaker.wave.2.fill")
                }
                Button {
                    SpeechSynthesisService.shared.speak(word, slow: true)
                } label: {
                    Label("ゆっくり", systemImage: "tortoise.fill")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
        .task {
            loadFromCacheOrTranslate()
        }
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(word)
                japanese = response.targetText
                saveCache(response.targetText)
            } catch {
                failed = true
            }
        }
    }

    /// キャッシュ → なければ翻訳して保存(オフライン・即時表示)
    private func loadFromCacheOrTranslate() {
        let target = word
        let descriptor = FetchDescriptor<WordCacheEntry>(
            predicate: #Predicate { $0.word == target }
        )
        if let cached = try? context.fetch(descriptor).first {
            japanese = cached.japanese
        } else {
            configuration = TranslationSession.Configuration(
                source: TranslationAvailability.english,
                target: TranslationAvailability.japanese
            )
        }
    }

    private func saveCache(_ translation: String) {
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
}
