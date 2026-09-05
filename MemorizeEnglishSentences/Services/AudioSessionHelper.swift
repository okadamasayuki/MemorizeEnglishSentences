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

    /// アプリがバックグラウンド(ロック含む)へ移った時に呼ぶ。
    /// どのプレイヤーも実際には鳴っておらず、録音もしていない=完全にアイドルな時だけ
    /// セッションを手放して、アプリが休止(サスペンド)できるようにする(発熱・電池消費対策)。
    /// 前面にいる間は手放さないので、再生ボタンの反応は速いまま保たれる。
    @MainActor
    static func releaseIfBackgroundIdle() {
        if SpeechRecognitionService.isAnyRecording { return }              // 録音継続中は維持
        let seq = AudioSequencePlayer.shared
        if seq.isPlayingSequence && !seq.isPaused { return }               // 音読/暗記の実再生中は維持
        if StudyWordPlayer.shared.isPlaying { return }                     // 単語学習の再生中は維持
        if IdiomPlayer.shared.isPlaying { return }                         // 熟語の再生中は維持
        let tts = SpeechSynthesisService.shared
        if tts.isPlayingSequence && !tts.isPaused { return }               // TTS連続再生中は維持
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
