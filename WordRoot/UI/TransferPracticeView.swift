import SwiftUI

/// An English answer entered before a model is heard is distinct from a listening-card choice.
struct TransferEntry: Codable {
    var sawModel = false
    var firstAnswer: String?
    var firstMode: String?
    var laterAnswer: String?
    var completed = false
}

enum TransferJournal {
    static let storageKey = "wordroot.transfer.v1"
    static func key(_ unit: Int, later: Bool) -> String { "\(unit).\(later ? "later" : "lesson")" }
    static func decode(_ data: Data) -> [String: TransferEntry] {
        (try? JSONDecoder().decode([String: TransferEntry].self, from: data)) ?? [:]
    }
}

struct TransferPracticeView: View {
    let day: CourseDay
    let later: Bool
    @Environment(SpeechPlayer.self) private var speaker
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TransferJournal.storageKey) private var saved = Data()
    @State private var draft = ""
    @State private var reveal = false
    @FocusState private var editing: Bool
    private var prompt: TransferPrompt { later ? day.nextTransfer : day.transfer }
    private var key: String { TransferJournal.key(day.unitID, later: later) }
    private var entry: TransferEntry { TransferJournal.decode(saved)[key] ?? TransferEntry() }
    private var sound: String { "transfer." + key }
    private var typedEnglish: Bool { draft.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                Text(prompt.prompt).font(.title2.bold()).foregroundStyle(MapStyle.pine)
                    .accessibilityIdentifier("transfer.prompt")
                Text("先用英语想一句。可以直接说，也可以把自己的说法记下来。").foregroundStyle(MapStyle.secondary)
                if let first = entry.firstAnswer {
                    Text(entry.firstMode == "unaided" ? "你先想到的说法" : "听过示范后写下的说法").font(.headline)
                    Text(first).accessibilityIdentifier("transfer.saved")
                }
                if let after = entry.laterAnswer {
                    Text("后来补充的说法").font(.headline)
                    Text(after)
                }
                TextField("写下自己的英语（可跳过）", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).focused($editing).accessibilityIdentifier("transfer.draft")
                if !draft.isEmpty {
                    Button("保存这句英语", action: saveAnswer).disabled(!typedEnglish)
                        .accessibilityIdentifier("transfer.save")
                }
                Button {
                    editing = false
                    reveal.toggle()
                    if reveal {
                        update { $0.sawModel = true }
                        _ = speaker.toggle(id: sound, text: prompt.answer)
                    } else { speaker.stop(id: sound) }
                } label: {
                    Label(reveal ? "收起示范" : "听一种说法", systemImage: "speaker.wave.2").frame(minHeight: 44)
                }.accessibilityIdentifier("transfer.reveal")
                if reveal {
                    Text(prompt.answer).font(.system(.title3, design: .serif)).accessibilityIdentifier("transfer.model")
                    Text(prompt.translation).foregroundStyle(MapStyle.secondary)
                }
                Button("练完，返回") {
                    if typedEnglish { saveAnswer() }
                    update { $0.completed = true }
                    dismiss()
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("transfer.done")
            }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .background(MapStyle.page.ignoresSafeArea()).navigationTitle(later ? "隔天换个条件" : "换个条件试一句")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onDisappear { speaker.stop(id: sound) }
    }

    private func saveAnswer() {
        guard typedEnglish else { return }
        let answer = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        update { row in
            if row.firstAnswer == nil {
                row.firstAnswer = answer
                row.firstMode = row.sawModel ? "assisted" : "unaided"
            } else { row.laterAnswer = answer }
        }
        draft = ""
        editing = false
    }

    private func update(_ change: (inout TransferEntry) -> Void) {
        var journal = TransferJournal.decode(saved)
        var row = journal[key] ?? TransferEntry()
        change(&row)
        journal[key] = row
        if let data = try? JSONEncoder().encode(journal) { saved = data }
    }
}
