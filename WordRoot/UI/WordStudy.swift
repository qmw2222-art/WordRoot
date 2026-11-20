import SwiftData
import SwiftUI

struct WordPronunciationRow: View {
    let word: Word
    let prefix: String
    let audioID: String
    @State private var hintOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(verbatim: "/\(word.pronunciation ?? "")/")
                    .font(.system(.title3, design: .serif)).foregroundStyle(MapStyle.secondary)
                    .accessibilityIdentifier(prefix + ".ipa")
                SpeechButton(id: audioID, text: word.word, pronunciation: word.pronunciation,
                             label: "听发音", identifier: prefix + ".audio.word")
            }
            if let hint = WordReadingAid.lookup(word.word, ipa: word.pronunciation) {
                Button { hintOpen.toggle() } label: {
                    Label("中文谐音", systemImage: hintOpen ? "chevron.up" : "chevron.down")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                .accessibilityIdentifier(prefix + ".readingAid")
                if hintOpen {
                    Text(hint.sound).font(.headline).accessibilityIdentifier(prefix + ".readingSound")
                    Text(hint.tip).font(.footnote).foregroundStyle(MapStyle.secondary)
                }
            }
        }
    }
}

struct StudyCard<Usage: View>: View {
    @Environment(SpeechPlayer.self) private var speaker
    @AppStorage("wordroot.course.autoGuide") private var autoGuide = true
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var firstWord = FirstWordListen()
    @State private var expanded = false
    @State private var checking = false
    @State private var failed = false
    let word: Word
    let prefix: String
    let soundID: String
    let showsExample: Bool
    let usage: Usage

    init(word: Word, prefix: String, soundID: String, showsExample: Bool = true,
         @ViewBuilder usage: () -> Usage = { EmptyView() }) {
        self.word = word; self.prefix = prefix; self.soundID = soundID
        self.showsExample = showsExample; self.usage = usage()
    }

    private var firstListen: Bool {
        (prefix == "course" || prefix == "family") && firstWord.waiting(automatic: autoGuide, screenReader: voiceOver)
    }

    var body: some View {
        Group {
            if firstListen {
                VStack(alignment: .leading, spacing: 10) {
                    Label("先听一遍完整的词", systemImage: "ear").font(.headline)
                    Button("看拼写和音标") { firstWord.show() }
                        .frame(minHeight: 44).accessibilityIdentifier(prefix + ".showSpelling")
                }
            } else { teaching }
        }
        .onChange(of: firstListen, initial: true) { _, waiting in
            LessonPlaybackTrace.note("card \(soundID) \(word.id) " + (waiting ? "listening" : "visible"))
        }
        .onChange(of: speaker.segmentIndex, initial: true) { _, index in
            firstWord.segmentChanged(isCurrentWord: speaker.activeID == soundID, index: index)
        }
        .onChange(of: speaker.activeID) { old, new in
            if old == soundID, new != soundID { firstWord.show() }
        }
        .task(id: soundID) {
            guard prefix == "course" || prefix == "family", autoGuide else { firstWord.show(); return }
            if speaker.activeID != soundID { failed = !speaker.toggleGuide(id: soundID, lines: word.studyNarration) }
            if failed { firstWord.show() }
        }
    }

    private var teaching: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(word.word).font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(MapStyle.pine).accessibilityIdentifier(prefix + ".word")
            WordPronunciationRow(word: word, prefix: prefix, audioID: soundID + ".word")
            Text(word.meaning).font(.title3.weight(.semibold)).foregroundStyle(MapStyle.pine)
                .accessibilityIdentifier(prefix + ".meaning")
            if !word.id.hasPrefix("basic.") || ["名词", "动词", "介词", "形容词", "副词"].contains(word.partOfSpeech) {
                Text("词性 · \(word.partOfSpeech)").font(.footnote).foregroundStyle(MapStyle.secondary)
            }
            if let parts = word.parts, let combined = word.combined {
                WordPartsView(parts: parts, combined: combined, formation: word.formation, soundID: soundID, prefix: prefix)
            }
            if word.parts == nil && !word.id.hasPrefix("basic.") {
                Text(word.formation).font(.title3.weight(.medium)).foregroundStyle(MapStyle.pine)
                    .accessibilityIdentifier(prefix + ".formation")
            }
            if word.parts == nil {
                Text(word.plainCue ?? word.memoryCue).accessibilityIdentifier(prefix + ".coach.word")
            }
            usage
            Button {
                failed = !speaker.toggleGuide(id: soundID, lines: word.studyNarration)
            } label: {
                Label(speaker.activeID == soundID ? "停止讲解" : "听老师讲记法",
                      systemImage: speaker.activeID == soundID ? "pause.circle.fill" : "play.circle.fill")
                    .font(.headline).frame(minHeight: 44)
            }
            .buttonStyle(.plain).foregroundStyle(MapStyle.pine)
            .accessibilityIdentifier(prefix + ".demo")
            .accessibilityValue(speaker.activeID == soundID ? "带读中" : "可播放")
            if failed { Text("声音暂时无法播放，请再点一次。").font(.footnote) }
            if showsExample {
            VStack(alignment: .leading, spacing: 7) {
                Button { expanded.toggle() } label: {
                    HStack {
                        Text("听听这句怎么说")
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.caption).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                .accessibilityValue(expanded ? "已展开" : "已收起")
                .accessibilityIdentifier(prefix + ".example.disclosure")
                if expanded {
                    Text(word.example).font(.system(.title3, design: .serif)).accessibilityIdentifier(prefix + ".example")
                    Text(word.translation).foregroundStyle(MapStyle.secondary)
                    SpeechButton(id: soundID + ".example", text: word.example, label: "听例句",
                                 identifier: prefix + ".audio.example")
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 4)
            .background(MapStyle.tintSurface, in: RoundedRectangle(cornerRadius: 13))
            }
            Button {
                if let active = speaker.activeID { speaker.stop(id: active) }
                checking = true
            } label: {
                Label("自己读一遍，核对词义", systemImage: "ear").frame(minHeight: 44)
            }
            .accessibilityIdentifier(prefix + ".selfcheck")
        }
        .sheet(isPresented: $checking) { WordSelfCheck(word: word) }
        .onDisappear { if let id = speaker.activeID, id.hasPrefix(soundID) { speaker.stop(id: id) } }
    }
}

struct WordSelfCheck: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(SpeechPlayer.self) private var speaker
    @FocusState private var editing: Bool
    @State private var phase = 0
    @State private var answer = ""
    @State private var heard = false
    @State private var compared = false
    @State private var meaningCorrect = false
    @State private var matched = false
    @State private var failure: String?
    let word: Word
    private let event = UUID()
    private var soundID: String { "mastery." + word.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if phase == 0 {
                        Text("这次由你自己核对读音。想练听音选择卡，可以在词族学完后或首页到期时开始。").font(.subheadline).foregroundStyle(MapStyle.secondary)
                        Text("听这个词，写下本课学过的一个中文意思。").font(.title2.bold())
                        Button { heard = play() || heard } label: { Label("听单词", systemImage: "speaker.wave.2") }
                            .accessibilityIdentifier("mastery.listen")
                        TextField("写下你记得的中文意思", text: $answer)
                            .textFieldStyle(.roundedBorder).focused($editing)
                            .submitLabel(.done).onSubmit { editing = false }
                            .accessibilityIdentifier("mastery.answer")
                        Button("核对词义") { submitMeaning(false) }
                            .disabled(!heard || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("mastery.submit")
                        Button("暂时想不起来") { submitMeaning(true) }.accessibilityIdentifier("mastery.unknown")
                    } else if phase == 1 {
                        Text(meaningCorrect ? "词义记住了" : "这个意思再看一眼").font(.title2.bold())
                        Text(word.meaning)
                        if !meaningCorrect { Text(word.memoryCue).foregroundStyle(MapStyle.secondary) }
                        Button("自己读一遍") { phase = 2 }.accessibilityIdentifier("mastery.pronunciation")
                    } else if phase == 2 {
                        Text("先读出这个词，再点喇叭对照。").font(.title2.bold())
                        Text(word.word).font(.system(.largeTitle, design: .serif, weight: .bold))
                        HStack(spacing: 7) {
                            Text(verbatim: "/\(word.pronunciation ?? "")/").font(.system(.title3, design: .serif))
                            Button { compared = play() || compared } label: {
                                Image(systemName: "speaker.wave.2.circle.fill").font(.title2).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("听这个词作对照").accessibilityIdentifier("mastery.compare")
                        }
                        Text("听听重音和结尾，按自己的判断选。").foregroundStyle(MapStyle.secondary)
                        Button("我的读音对得上") { saveSound(true) }.disabled(!compared).accessibilityIdentifier("mastery.match")
                        Button("还需要练") { saveSound(false) }.accessibilityIdentifier("mastery.again")
                    } else {
                        Text(meaningCorrect && matched ? "这次词义和发音都对上了。" : "下次再听听这个词。").font(.title2.bold())
                        Text("\(word.word) · \(word.meaning)")
                        Button("回到学习") { dismiss() }.accessibilityIdentifier("mastery.close")
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            }
            .background(MapStyle.page.ignoresSafeArea())
            .buttonStyle(.bordered).tint(MapStyle.pine)
            .navigationTitle("自己读，自己核对").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }.onDisappear { speaker.stop(id: soundID) }
    }

    private func play() -> Bool {
        if speaker.activeID == soundID { speaker.stop(id: soundID) }
        let ok = speaker.toggle(id: soundID, text: word.word, pronunciation: word.pronunciation)
        if !ok { failure = "暂时无法播放，点发音键再试一次。" }
        return ok
    }

    private func submitMeaning(_ unknown: Bool) {
        let aliases = word.meaning.components(separatedBy: CharacterSet(charactersIn: "；，、/"))
        let evaluation = AnswerEvaluator.evaluate(answer: unknown ? "" : answer,
            acceptedAnswers: Set(word.acceptedAnswers + aliases), usedAssistance: unknown, wasShownAnswer: false)
        if save(ability: .audioMeaning, text: unknown ? "暂时想不起来" : answer, evaluation: evaluation) {
            editing = false
            meaningCorrect = evaluation.isIndependentEvidence
            phase = 1
        }
    }

    private func saveSound(_ match: Bool) {
        let value = match ? "自己对照读音后确认一致" : "发音还要练"
        let result = AnswerEvaluation(outcome: match ? .correct : .needsReview, normalizedAnswer: value,
                                      usedAssistance: false, isIndependentEvidence: false)
        if save(ability: .pronunciationSelfCheck, text: value, evaluation: result) { matched = match; phase = 3 }
    }

    private func save(ability: LearningAbility, text: String, evaluation: AnswerEvaluation) -> Bool {
        context.insert(LearningAttemptRecord(reviewAttemptID: event, senseID: word.id, ability: ability,
                       firstAnswer: text, evaluation: evaluation, wasShownAnswer: false))
        do {
            if ability == .audioMeaning {
                try CourseReview.grade(word.id, as: AnswerEvaluator.grade(for: evaluation), attemptID: event, in: context)
            }
            try context.save()
            failure = nil
            return true
        }
        catch { context.rollback(); failure = "这次自查暂时没存好，请再点一次。"; return false }
    }
}

struct StudiedWordsList: View {
    let words: [Word]
    let prefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(words) { word in
                VStack(alignment: .leading, spacing: 2) {
                    Text(word.word).font(.system(.title3, design: .serif, weight: .semibold))
                        .foregroundStyle(MapStyle.pine)
                        .accessibilityIdentifier(prefix + ".word." + word.id)
                    Text(word.meaning).font(.body)
                        .accessibilityIdentifier(prefix + ".meaning." + word.id)
                    WordPronunciationRow(word: word, prefix: prefix + "." + word.id, audioID: prefix + ".listen." + word.id)
                }
                .padding(.vertical, 6)
                if word.id != words.last?.id { Divider() }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FamilyStudyView: View {
    @Environment(SpeechPlayer.self) private var speaker
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var cursor: String
    @State private var cardsOpen = false
    @State private var saveFailed = false
    let family: WordFamily
    let lexicon: Lexicon

    init(family: WordFamily, lexicon: Lexicon) {
        self.family = family
        self.lexicon = lexicon
        _cursor = AppStorage(wrappedValue: "", "wordroot.familyStudy." + family.id)
    }

    private var done: Bool { cursor == "finished" }
    private var index: Int { family.words.firstIndex { $0.id == cursor } ?? 0 }
    private var word: Word { family.words[index] }
    private var soundID: String { "family.study." + word.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if done {
                    Text("\(family.root) 词族学完了").font(.title.bold()).accessibilityIdentifier("family.done")
                    Text("这一组学过的 \(family.words.count) 个用法").font(.headline)
                    StudiedWordsList(words: family.words, prefix: "family.recap")
                    Button("从第一个词再看") { cursor = family.words[0].id }
                    Button("回到上一页") { dismiss() }
                } else {
                    Text("第 \(index + 1) / \(family.words.count) 个用法").font(.headline)
                        .foregroundStyle(MapStyle.secondary).accessibilityIdentifier("family.position")
                    StudyCard(word: word, prefix: "family", soundID: soundID)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }
        .id(cursor)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !done { LessonRootReminder(family: family, prefix: "family", soundID: soundID + ".reminder") }
        }
        .background(MapStyle.page.ignoresSafeArea()).navigationTitle("学完整个词族")
        .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if done {
                Button {
                    stopFamilyAudio()
                    cardsOpen = true
                } label: {
                    Label("练 \(family.root) 词族听音卡", systemImage: "ear").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 46)
                }.buttonStyle(.borderedProminent).tint(MapStyle.accent).foregroundStyle(MapStyle.onAccent)
                    .padding(.horizontal).padding(.vertical, 5).background(MapStyle.page)
                    .accessibilityIdentifier("family.recapCards")
            } else {
                HStack {
                    if index > 0 { Button("上一词") { cursor = family.words[index - 1].id } }
                    Button(index + 1 < family.words.count ? "下一词 · \(family.words[index + 1].word)" : "学完整组") {
                        do {
                            _ = try CourseReview.seed(word.id, in: context)
                            try context.save()
                            cursor = index + 1 < family.words.count ? family.words[index + 1].id : "finished"
                        } catch {
                            context.rollback()
                            saveFailed = true
                        }
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("family.next")
                }.frame(maxWidth: .infinity).padding(8).background(MapStyle.page)
            }
        }
        .sheet(isPresented: $cardsOpen) { MemoryCardsSheet(words: family.words, lexicon: lexicon, family: family) }
        .alert("这个词的学习记录还没保存", isPresented: $saveFailed) {
            Button("知道了", role: .cancel) {}
        }
        .onDisappear { stopFamilyAudio() }
    }

    private func stopFamilyAudio() {
        if let id = speaker.activeID, id.hasPrefix("family.") { speaker.stop(id: id) }
    }
}
