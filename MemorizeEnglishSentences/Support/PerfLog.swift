import Foundation

/// 重さの原因調査用の軽量ログ。Documents/perf_log.txt に追記し、Mac から回収して分析する。
/// - 各所からの `log()` でイベントを記録
/// - `startWatchdog()` はメインスレッドの詰まり(0.4秒以上)を検出して記録する
/// 調査が終わったら呼び出しごと外してよい。
enum PerfLog {
    private static let start = Date()
    private static let queue = DispatchQueue(label: "perflog", qos: .utility)

    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("perf_log.txt")
    }

    static func log(_ message: String) {
        let line = String(format: "[+%7.2fs] %@\n", Date().timeIntervalSince(start), message)
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }

    /// 処理時間を測って記録する
    @discardableResult
    static func measure<T>(_ label: String, _ body: () -> T) -> T {
        let t0 = CFAbsoluteTimeGetCurrent()
        let result = body()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        log(String(format: "%@ %.1fms", label, ms))
        return result
    }

    /// メインスレッドが 0.4 秒以上詰まったら記録する見張り。
    /// 「どの時刻に固まったか」をイベントログと突き合わせて原因を絞る。
    static func startWatchdog() {
        log("=== launch (watchdog on) ===")
        Thread.detachNewThread {
            while true {
                let t0 = CFAbsoluteTimeGetCurrent()
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    let dt = CFAbsoluteTimeGetCurrent() - t0
                    if dt > 0.4 {
                        log(String(format: "⚠️ main blocked %.0fms", dt * 1000))
                    }
                    done.signal()
                }
                done.wait()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }
}
