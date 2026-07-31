import SwiftUI

/// マイクの開始/停止ボタン。録音中は赤く点滅風に表示する。
struct DictationButton: View {
    let speech: SpeechRecognitionService
    var label: String = "音声入力"

    var body: some View {
        Button {
            Task { await speech.toggle() }
        } label: {
            Label(
                speech.isRecording ? "停止" : label,
                systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill"
            )
            .font(.headline)
            .foregroundStyle(speech.isRecording ? Color.red : Color.accentColor)
        }
        .buttonStyle(.bordered)
        .alert("マイクまたは音声認識が許可されていません", isPresented: permissionBinding) {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("設定を開く", destination: url)
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("設定アプリでマイクと音声認識を許可してください。テキスト入力・ペーストは引き続き利用できます。")
        }
    }

    private var permissionBinding: Binding<Bool> {
        Binding(
            get: { speech.permissionDenied },
            set: { speech.permissionDenied = $0 }
        )
    }
}
