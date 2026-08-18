import SwiftUI

/// 熟語の意味+発音の bottom sheet。
/// 例文中の熟語部分を長押しした時に、この文での形(活用形)と意味を表示する。
struct IdiomPopupView: View {
    let idiom: Idiom
    /// 例文中に現れた形(例: "threw in the towel")。見出しと同じなら空でよい
    let surfaceForm: String

    /// 読み上げる形: 例文中の形を最優先、無ければ見出しからプレースホルダを除いたもの
    private var speakText: String {
        surfaceForm.isEmpty ? phraseBase : surfaceForm
    }

    /// 見出しから ~ / A / B などを除いた読み上げ用の形
    private var phraseBase: String {
        idiom.phrase
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
            .split(separator: " ")
            .filter { !["A", "B"].contains(String($0)) }
            .joined(separator: " ")
    }

    /// 例文中の形が見出しの形と実質同じなら表示を省く
    private var showsSurface: Bool {
        !surfaceForm.isEmpty && surfaceForm.lowercased() != phraseBase.lowercased()
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(idiom.phrase)
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)
                if showsSurface {
                    Text("文中では: \(surfaceForm)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(idiom.meaning)
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                SpeechSynthesisService.shared.speak(speakText)
            } label: {
                Label("発音", systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }
}
