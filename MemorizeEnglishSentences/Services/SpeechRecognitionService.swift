import AVFoundation
import Foundation
import Observation
import Speech

/// SFSpeechRecognizer + AVAudioEngine による英語 (en-US) 音声入力。
/// autoRestart = true のとき、認識タスクが final になったら自動再開して長文に対応する(暗記モード)。
@MainActor
@Observable
final class SpeechRecognitionService {
    var isRecording = false
    /// final になった確定テキスト(セグメント連結)
    var confirmedText = ""
    /// 部分認識結果(ライブ表示用)
    var partialText = ""
    var errorMessage: String?
    var permissionDenied = false

    /// 暗記モード: final 後に自動で認識を再開して約 1 分制限を回避する
    var autoRestart = false

    /// final セグメント確定ごとに呼ばれるコールバック(登録画面でエディタへ追記する用)
    var onFinalSegment: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var fullText: String {
        [confirmedText, partialText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toggle() async {
        if isRecording {
            stop()
        } else {
            await start()
        }
    }

    func reset() {
        confirmedText = ""
        partialText = ""
        errorMessage = nil
    }

    /// 言い直し用: 認識済みテキストを消して、録音中なら認識をクリーンに再開する。
    /// (表示だけ消しても認識器内部に前の発話が残るため、タスクごと作り直す)
    func restartClean() {
        confirmedText = ""
        partialText = ""
        errorMessage = nil
        if isRecording {
            restartRecognition()
        }
    }

    func start() async {
        errorMessage = nil
        guard await requestPermissions() else {
            permissionDenied = true
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "音声認識を利用できません。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try beginRecognition()
            isRecording = true
        } catch {
            errorMessage = "録音を開始できませんでした: \(error.localizedDescription)"
            cleanup()
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        request?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Private

    private func beginRecognition() throws {
        guard let recognizer else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        // 再開時はタップ除去必須
        inputNode.removeTap(onBus: 0)
        // フォーマットのハードコード禁止 — inputNode の実フォーマットを使う
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handle(result: result, error: error, from: request)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?, from source: SFSpeechAudioBufferRecognitionRequest) {
        // 再開後に届く古いタスクのコールバックは無視する(テキストが巻き戻るのを防ぐ)
        guard source === request else { return }
        if let result {
            if result.isFinal {
                // final が直前の部分認識より短いことがあるため、長い方を採用して消失を防ぐ
                let finalText = result.bestTranscription.formattedString
                let chosen = finalText.count >= partialText.count ? finalText : partialText
                appendConfirmed(chosen)
                partialText = ""
                if isRecording, autoRestart {
                    restartRecognition()
                } else if isRecording {
                    stop()
                    cleanup()
                } else {
                    cleanup()
                }
                return
            } else {
                updatePartial(result.bestTranscription.formattedString)
            }
        }
        if error != nil {
            // final が届かないままエラーで終わることがある(約 1 分制限など)。
            // 認識途中のテキストを確定分に退避してから再開し、回答が消えないようにする。
            salvagePartial()
            if isRecording, autoRestart {
                restartRecognition()
            } else {
                if isRecording { stop() }
                cleanup()
            }
        }
    }

    /// 未確定の部分認識テキストを確定テキストへ退避する
    private func salvagePartial() {
        guard !partialText.isEmpty else { return }
        appendConfirmed(partialText)
        partialText = ""
    }

    /// 部分認識の更新。認識器の内部リセットで大幅に短くなったときは
    /// それまでの内容を確定分へ退避してから置き換える(表示が消えるのを防ぐ)
    private func updatePartial(_ newText: String) {
        if partialText.count > 20, newText.count < partialText.count / 2 {
            salvagePartial()
        }
        partialText = newText
    }

    private func appendConfirmed(_ segment: String) {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        confirmedText = confirmedText.isEmpty ? trimmed : confirmedText + " " + trimmed
        onFinalSegment?(trimmed)
    }

    private func restartRecognition() {
        task?.cancel()
        task = nil
        request = nil
        do {
            try beginRecognition()
        } catch {
            errorMessage = "音声認識を再開できませんでした: \(error.localizedDescription)"
            stop()
            cleanup()
        }
    }

    private func cleanup() {
        task?.cancel()
        task = nil
        request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
