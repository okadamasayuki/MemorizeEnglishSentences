import SwiftUI

/// 蓄積した RecallAttempt を集計して間違えやすい箇所を分析・表示
struct MistakeAnalysisView: View {
    let passage: Passage

    private struct WordStat: Identifiable {
        let id: Int          // reference token index
        let display: String
        let missCount: Int
        let totalCount: Int

        var missRate: Double {
            totalCount == 0 ? 0 : Double(missCount) / Double(totalCount)
        }
    }

    private var attempts: [RecallAttempt] {
        passage.attempts.sorted { $0.date > $1.date }
    }

    private var refTokens: [WordToken] {
        WordTokenizer.tokenize(passage.englishFullText)
    }

    /// 正解側トークンごとのミス回数を集計
    private var wordStats: [WordStat] {
        var miss = [Int: Int]()
        var total = [Int: Int]()
        for attempt in attempts {
            guard let diff = DiffService.decode(attempt.opsJSON) else { continue }
            for op in diff.ops {
                guard let refIndex = op.refIndex else { continue }
                total[refIndex, default: 0] += 1
                if op.kind == .sub || op.kind == .del {
                    miss[refIndex, default: 0] += 1
                }
            }
        }
        return refTokens.map { token in
            WordStat(
                id: token.id,
                display: token.display,
                missCount: miss[token.id] ?? 0,
                totalCount: total[token.id] ?? 0
            )
        }
    }

    var body: some View {
        Group {
            if attempts.isEmpty {
                ContentUnavailableView(
                    "まだ記録がありません",
                    systemImage: "chart.bar",
                    description: Text("暗記に挑戦すると、間違えやすい箇所がここに表示されます。")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heatmapSection
                        topMistakesSection
                        historySection
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("間違い分析")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - ヒートマップ(間違え頻度が高い単語ほど濃い赤背景)

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("間違いヒートマップ")
                .font(.headline)
            Text("赤が濃い単語ほど間違えやすい箇所です(挑戦 \(attempts.count) 回)")
                .font(.caption)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 4, lineSpacing: 8) {
                ForEach(wordStats) { stat in
                    Text(stat.display)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red.opacity(stat.missRate * 0.75))
                        )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
    }

    // MARK: - 間違えやすい箇所 TOP

    private var topMistakesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("間違えやすい箇所 TOP")
                .font(.headline)

            let top = wordStats
                .filter { $0.missCount > 0 }
                .sorted { ($0.missCount, $1.id) > ($1.missCount, $0.id) }
                .prefix(10)

            if top.isEmpty {
                Text("間違えた単語はありません 🎉")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(top)) { stat in
                        HStack {
                            Text(stat.display)
                                .font(.subheadline.bold())
                            Spacer()
                            Text("ミス \(stat.missCount) 回 / 挑戦 \(stat.totalCount) 回")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                }
            }
        }
    }

    // MARK: - 試行履歴(日付・正答率の推移)

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("試行履歴")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(attempts) { attempt in
                    NavigationLink {
                        RecallDiffView(attempt: attempt)
                    } label: {
                        HStack {
                            Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(attempt.accuracy * 100))%")
                                .font(.subheadline.bold())
                                .foregroundStyle(accuracyColor(attempt.accuracy))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 0.8...: .green
        case 0.5..<0.8: .orange
        default: .red
        }
    }
}
