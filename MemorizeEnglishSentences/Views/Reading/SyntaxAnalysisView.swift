import CryptoKit
import SwiftData
import SwiftUI

/// 文の長押しで表示する SVC/SVO 構文解析シート(Claude API 使用・結果はキャッシュ)
struct SyntaxAnalysisView: View {
    @Environment(\.modelContext) private var context
    let sentence: String

    @State private var analysis: SyntaxAnalysis?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
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
                }
            }
            .navigationTitle("構文解析")
            .navigationBarTitleDisplayMode(.inline)
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
            VStack(alignment: .leading, spacing: 16) {
                Text(analysis.patternLabelJa)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))

                // 文を要素ごとに色分け表示(要素チップ+役割ラベル)
                FlowLayout(spacing: 6, lineSpacing: 8) {
                    ForEach(Array(analysis.elements.enumerated()), id: \.offset) { _, element in
                        VStack(spacing: 2) {
                            Text(element.text)
                                .font(.body.bold())
                            Text(roleLabel(element.role))
                                .font(.caption2)
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

                // 各要素の説明
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(analysis.elements.enumerated()), id: \.offset) { _, element in
                        HStack(alignment: .top, spacing: 8) {
                            Text(element.role)
                                .font(.caption.bold())
                                .frame(width: 32)
                                .foregroundStyle(roleColor(element.role))
                            Text("\(element.text) — \(element.noteJa)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                Text(analysis.explanationJa)
                    .font(.subheadline)

                legend
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 8, lineSpacing: 6) {
            legendItem("S", "主語")
            legendItem("V", "動詞")
            legendItem("O", "目的語")
            legendItem("C", "補語")
            legendItem("Aux", "助動詞")
            legendItem("M", "修飾語")
        }
        .padding(.top, 4)
    }

    private func legendItem(_ role: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(roleColor(role))
                .frame(width: 8, height: 8)
            Text("\(role): \(label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "S": "主語"
        case "V": "動詞"
        case "O": "目的語"
        case "C": "補語"
        case "Aux": "助動詞"
        default: "修飾"
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
