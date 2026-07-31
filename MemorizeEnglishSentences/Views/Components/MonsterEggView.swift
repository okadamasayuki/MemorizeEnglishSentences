import SwiftUI

/// 勉強時間で孵化・成長する怪獣の卵
struct MonsterEggView: View {
    private struct Stage {
        let threshold: TimeInterval   // この累計勉強時間(秒)以上でこの姿になる
        let emoji: String
        let name: String
        let message: String
        let size: CGFloat
    }

    private static let stages: [Stage] = [
        Stage(threshold: 0, emoji: "🥚", name: "なぞのたまご",
              message: "勉強するとあたたまって、なにかが起こるみたい...", size: 60),
        Stage(threshold: 10 * 60, emoji: "🐣", name: "ヒビが入った!",
              message: "中からコツコツ音がする。もうすぐ生まれそう!", size: 64),
        Stage(threshold: 30 * 60, emoji: "🐲", name: "あかちゃん怪獣",
              message: "生まれた! 勉強すると大きくなるみたい", size: 68),
        Stage(threshold: 2 * 3600, emoji: "🦖", name: "こども怪獣",
              message: "ぐんぐん成長中! 英語もどんどん覚えよう", size: 84),
        Stage(threshold: 5 * 3600, emoji: "🐉", name: "りっぱな怪獣",
              message: "立派に育った! これからも一緒に勉強しよう", size: 100),
    ]

    @State private var wiggle = false

    var body: some View {
        // 1 秒ごとに描画し直して、勉強時間と成長をライブ表示する
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let total = StudyTimeTracker.shared.currentTotalSeconds
            let stageIndex = Self.currentStageIndex(for: total)
            let stage = Self.stages[stageIndex]
            let next = stageIndex + 1 < Self.stages.count ? Self.stages[stageIndex + 1] : nil

            VStack(spacing: 10) {
                Text(stage.emoji)
                    .font(.system(size: stage.size))
                    .rotationEffect(.degrees(wiggle ? 4 : -4))
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: wiggle)

                Text(stage.name)
                    .font(.headline)

                Text(stage.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text("勉強時間: \(StudyTimeTracker.format(total))")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if let next {
                    let span = next.threshold - stage.threshold
                    let progress = span > 0 ? min(max((total - stage.threshold) / span, 0), 1) : 0
                    VStack(spacing: 4) {
                        ProgressView(value: progress)
                            .tint(.orange)
                        Text("つぎの成長まで あと \(StudyTimeTracker.format(max(next.threshold - total, 60)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .onAppear {
            wiggle = true
        }
    }

    private static func currentStageIndex(for total: TimeInterval) -> Int {
        var index = 0
        for (i, stage) in stages.enumerated() where total >= stage.threshold {
            index = i
        }
        return index
    }
}
