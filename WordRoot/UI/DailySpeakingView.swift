import SwiftUI

struct DailySpeakingView: View {
    @Environment(SpeechPlayer.self) private var speaker
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var saved: Data
    @State private var index = 0
    @State private var draft = ""
    @State private var reveal = false
    @State private var translation = false
    @FocusState private var editing: Bool
    let day: CourseDay

    init(day: CourseDay) {
        self.day = day
        _saved = AppStorage(wrappedValue: Data(), "wordroot.talk.\(day.unitID)")
    }

    private var turn: SpeakingMission.Turn { day.speakingMission.turns[index] }
    private var replies: [String: String] { (try? JSONDecoder().decode([String: String].self, from: saved)) ?? [:] }
    private var key: String { day.speakingRevision.map { "v\($0).\(index)" } ?? String(index) }
    private var conversation: [CourseDay.Line] {
        day.speakingMission.turns.flatMap { [.init(text: $0.partner, translation: $0.partnerZH), .init(text: $0.reply, translation: $0.replyZH)] }
    }
    private var sound: String { "talk.\(day.id).\(index)" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text(day.speakingMission.goal).font(.title2.bold()).foregroundStyle(MapStyle.pine).accessibilityIdentifier("talk.goal")
                Text("第 \(index + 1) / \(day.speakingMission.turns.count) 句").font(.caption).foregroundStyle(MapStyle.secondary)
                Text(turn.partner).font(.system(.title2, design: .serif))
                SpeechButton(id: sound, text: turn.partner, label: "听对方说", identifier: "talk.listen")
                DisclosureGroup("看这句话的中文", isExpanded: $translation) { Text(turn.partnerZH).frame(maxWidth: .infinity, alignment: .leading) }
                Divider()
                Text("换你了，按自己的情况回一句。").font(.headline)
                if let reply = replies[key] {
                    Text(reply).foregroundStyle(MapStyle.pine).accessibilityIdentifier("talk.myReply")
                }
                if day.speakingRevision != nil, let earlier = replies[String(index)] {
                    DisclosureGroup("查看上版练习里记下的回答") { Text(earlier) }
                }
                answerControls
                Button(reveal ? "收起示例" : "听一种说法") {
                    reveal.toggle()
                    if reveal { _ = speaker.toggle(id: sound + ".model", text: turn.reply) }
                }.frame(minHeight: 44).accessibilityIdentifier("talk.reveal")
                if reveal {
                    Text(turn.reply).font(.system(.title3, design: .serif)).accessibilityIdentifier("talk.model")
                    Text(turn.replyZH).foregroundStyle(MapStyle.secondary)
                }
                if index == 0 {
                    Button("听对方接着说") { setTurn(1) }.buttonStyle(.borderedProminent).accessibilityIdentifier("talk.follow")
                } else {
                    Button("回到第一句") { setTurn(0) }
                    Button("回到学习") { dismiss() }.buttonStyle(.borderedProminent)
                }
                DisclosureGroup("听这课的完整对话") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(conversation.indices, id: \.self) { index in
                            Text(conversation[index].text).font(.system(.body, design: .serif))
                            Text(conversation[index].translation).foregroundStyle(MapStyle.secondary)
                        }
                        SpeechButton(id: "talk.\(day.id).dialogue", dialogue: conversation.map(\.text),
                                     label: "听整段对话", identifier: "talk.dialogue")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.top, 6)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .background(MapStyle.page.ignoresSafeArea()).navigationTitle("用今天的词开口")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onDisappear { stopAudio() }
    }

    private var answerControls: some View {
        Group {
                Button("记为已口头尝试") { store("我已自己开口回答") }.accessibilityIdentifier("talk.spoken")
                HStack {
                    TextField("也可以记下自己的回答", text: $draft).textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.sentences).focused($editing).submitLabel(.done)
                        .onSubmit { if !draft.isEmpty { store(draft) } }.accessibilityIdentifier("talk.reply")
                    Button("记下") { store(draft) }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("talk.save")
                }
        }
    }

    private func store(_ reply: String) {
        var updated = replies
        updated[key] = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = try? JSONEncoder().encode(updated) { saved = data; draft = ""; editing = false }
    }
    private func setTurn(_ next: Int) {
        stopAudio(); index = next; reveal = false; translation = false; draft = ""; editing = false
    }
    private func stopAudio() {
        if let id = speaker.activeID, id.hasPrefix("talk.\(day.id).") { speaker.stop(id: id) }
    }
}
