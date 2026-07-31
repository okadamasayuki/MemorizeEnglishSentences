import Foundation

enum DiffOpKind: String, Codable {
    case match
    case sub
    case del
    case ins
}

/// 正解側 (reference) と認識側 (hypothesis) の単語アラインメント 1 件
struct DiffOp: Codable, Hashable {
    let kind: DiffOpKind
    let refIndex: Int?
    let hypIndex: Int?
}

struct DiffResult: Codable {
    let ops: [DiffOp]
    let refCount: Int
    let matchCount: Int

    var accuracy: Double {
        refCount == 0 ? 0 : Double(matchCount) / Double(refCount)
    }
}

/// Wagner-Fischer(編集距離)による単語単位アラインメント
enum DiffService {
    static func diff(reference: [String], hypothesis: [String]) -> DiffResult {
        let n = reference.count
        let m = hypothesis.count

        // dp[i][j] = reference[0..<i] と hypothesis[0..<j] の編集距離
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    if reference[i - 1] == hypothesis[j - 1] {
                        dp[i][j] = dp[i - 1][j - 1]
                    } else {
                        dp[i][j] = 1 + min(dp[i - 1][j - 1], dp[i - 1][j], dp[i][j - 1])
                    }
                }
            }
        }

        // バックトレースで ops を復元
        var ops: [DiffOp] = []
        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, reference[i - 1] == hypothesis[j - 1], dp[i][j] == dp[i - 1][j - 1] {
                ops.append(DiffOp(kind: .match, refIndex: i - 1, hypIndex: j - 1))
                i -= 1; j -= 1
            } else if i > 0, j > 0, dp[i][j] == dp[i - 1][j - 1] + 1 {
                ops.append(DiffOp(kind: .sub, refIndex: i - 1, hypIndex: j - 1))
                i -= 1; j -= 1
            } else if i > 0, dp[i][j] == dp[i - 1][j] + 1 {
                ops.append(DiffOp(kind: .del, refIndex: i - 1, hypIndex: nil))
                i -= 1
            } else {
                ops.append(DiffOp(kind: .ins, refIndex: nil, hypIndex: j - 1))
                j -= 1
            }
        }
        ops.reverse()

        let matchCount = ops.filter { $0.kind == .match }.count
        return DiffResult(ops: ops, refCount: n, matchCount: matchCount)
    }

    static func encode(_ result: DiffResult) -> String {
        guard let data = try? JSONEncoder().encode(result) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ json: String) -> DiffResult? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DiffResult.self, from: data)
    }
}
