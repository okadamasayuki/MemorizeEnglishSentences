import SwiftUI

/// 回答確定後: 正解英文を基準に差分ハイライト表示
/// 一致=緑 / 言えなかった(欠落・誤り)=赤 / 余分に言った語=取り消し線オレンジ
struct RecallDiffView: View {
    let attempt: RecallAttempt

    private var diff: DiffResult? {
        DiffService.decode(attempt.opsJSON)
    }

    private var refTokens: [WordToken] {
        WordTokenizer.tokenize(attempt.passage?.englishFullText ?? "")
    }

    private var hypTokens: [WordToken] {
        WordTokenizer.tokenize(attempt.recognizedText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let diff {
                    accuracyHeader(diff)

                    FlowLayout(spacing: 4, lineSpacing: 8) {
                        ForEach(Array(diff.ops.enumerated()), id: \.offset) { _, op in
                            tokenView(for: op)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                } else {
                    Text("差分データを読み込めませんでした")
                        .foregroundStyle(.secondary)
                }

            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("採点結果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func accuracyHeader(_ diff: DiffResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Int(diff.accuracy * 100))%")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(accuracyColor(diff.accuracy))
            Spacer()
            Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func tokenView(for op: DiffOp) -> some View {
        switch op.kind {
        case .match:
            if let refIndex = op.refIndex, refIndex < refTokens.count {
                Text(refTokens[refIndex].display)
                    .foregroundStyle(.green)
            }
        case .sub, .del:
            if let refIndex = op.refIndex, refIndex < refTokens.count {
                Text(refTokens[refIndex].display)
                    .bold()
                    .foregroundStyle(.red)
            }
        case .ins:
            if let hypIndex = op.hypIndex, hypIndex < hypTokens.count {
                Text(hypTokens[hypIndex].display)
                    .strikethrough()
                    .foregroundStyle(.orange)
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
