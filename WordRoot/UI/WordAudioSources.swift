import SwiftUI

struct WordAudioSources: View {
    var body: some View {
        Form {
            LabeledContent("英文朗读", value: "Heart · 美式女声")
            LabeledContent("中文讲解", value: "晓晓 · 普通话女声")
            Text("课程录音由 Kokoro 生成，保存在手机上，离线也能听。")
                .font(.footnote)
        }
        .navigationTitle("朗读声音")
    }
}
