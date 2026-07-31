import CryptoKit
import SwiftData
import SwiftUI

/// 文の長押しで表示する構文解析シート(Claude API 使用・結果はキャッシュ)。
/// 文を要素ごとに色分けし、S/V/O/C/M/Aux のラベルだけを表示する。
struct SyntaxAnalysisView: View {
    @Environment(\.modelContext) private var context
    let sentence: String

    @State private var analysis: SyntaxAnalysis?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let analysis {
                resultView(analysis)
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("構文を解析中...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                    Button("再試行") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                ProgressView()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await load()
        }
    }

    // MARK: - 表示

    private func resultView(_ analysis: SyntaxAnalysis) -> some View {
        ScrollView {
            FlowLayout(spacing: 6, lineSpacing: 10) {
                ForEach(Array(analysis.elements.enumerated()), id: \.offset) { _, element in
                    VStack(spacing: 2) {
                        Text(element.text)
                            .font(.body.bold())
                        Text(element.role)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(roleColor(element.role).opacity(0.18))
                    )
                    .foregroundStyle(roleColor(element.role))
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "S": .blue
        case "V": .red
        case "O": .green
        case "C": .orange
        case "Aux": .purple
        default: .gray
        }
    }

    // MARK: - 読み込み(キャッシュ → API)

    private func load() async {
        errorMessage = nil
        let hash = Self.hash(of: sentence)

        // 同じ文の再解析で課金しないためのキャッシュ
        let descriptor = FetchDescriptor<SyntaxCacheEntry>(
            predicate: #Predicate { $0.sentenceHash == hash }
        )
        if let cached = try? context.fetch(descriptor).first,
           let data = cached.resultJSON.data(using: .utf8),
           let cachedAnalysis = try? JSONDecoder().decode(SyntaxAnalysis.self, from: data) {
            analysis = cachedAnalysis
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await ClaudeAPIService.analyzeSyntax(sentence: sentence)
            analysis = result
            if let data = try? JSONEncoder().encode(result),
               let json = String(data: data, encoding: .utf8) {
                context.insert(SyntaxCacheEntry(sentenceHash: hash, sentence: sentence, resultJSON: json))
                try? context.save()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func hash(of sentence: String) -> String {
        let normalized = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
