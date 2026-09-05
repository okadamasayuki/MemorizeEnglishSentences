import AVFoundation

/// オーディオセッションの後始末をまとめる。
///
/// このアプリはバックグラウンド再生に対応(Info.plist の UIBackgroundModes: audio)しているため、
/// 再生を終えたのにセッションを有効(setActive true)のまま残すと、アプリが休止(サスペンド)
/// されず、オーディオ回路が起動したままになって発熱・電池消費の原因になる。
/// 各プレイヤーは再生を止めたら releaseIfIdle() を呼んでセッションを手放す。
enum AudioSessionHelper {
    /// 再生を終えた各プレイヤーが停止時に呼ぶ。録音中は録音セッションを壊さないよう触らない。
    static func releaseIfIdle() {
        guard !SpeechRecognitionService.isAnyRecording else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
