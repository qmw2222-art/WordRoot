import SwiftData
import SwiftUI

private enum ListeningAnswer: String, CaseIterable, Identifiable {
    case meaning = "选意思"
    case spelling = "选单词"
    var id: Self { self }
    func label(_ word: Word) -> String { self == .spelling ? word.word : word.meaning }
}

struct MemoryCardsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SpeechPlayer.self) private var speaker
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ListeningAnswer = .meaning
    @State private var queue: [ListeningQuestion]
    @State private var index = 0
    @State private var chosen: String?
    @State private var nextDue: Date?
    @State private var heard = false
    @State private var playbackFailed = false
    @State private var missed: Set<String> = []
    @State private var saveFailed = false
    @State private var ready = false
    @State private var loadFailed = false
    private let familyKey: String?
    private let lexicon: Lexicon
    let initialCount: Int
    private let familyName: String?

    private let finishTitle: String
    private let onFinish: (() -> Void)?

    init(words: [Word], lexicon: Lexicon, family: WordFamily? = nil,
         finishTitle: String = "完成", onFinish: (() -> Void)? = nil) {
        self.finishTitle = finishTitle
        self.onFinish = onFinish
        var seen: Set<String> = []
        let targets = words.filter { seen.insert($0.id).inserted }
        let all = lexicon.families.flatMap(\.words) + Array(lexicon.basicWords.values)
        let sameSound = Dictionary(grouping: all, by: Self.soundKey)
        let allShuffled = all.shuffled()
        let questions = targets.map { word in
            let neighbors = lexicon.entry(id: word.id)?.family.words ?? []
            let pool = family.map { targets.shuffled() + $0.words.shuffled() } ?? ((neighbors + targets).shuffled() + allShuffled)
            let sound = Self.soundKey(word)
            var sounds: Set<String> = [sound]
            var spellings: Set<String> = [word.word.lowercased()]
            var meanings = Set((sameSound[sound] ?? [word]).flatMap { Self.aliases($0) })
            var options = [word]
            for other in pool {
                let spelling = other.word.lowercased()
                let candidateSound = Self.soundKey(other)
                let senses = Self.aliases(other)
                guard !spellings.contains(spelling), !sounds.contains(candidateSound), meanings.isDisjoint(with: senses) else { continue }
                options.append(other)
                spellings.insert(spelling)
                sounds.insert(candidateSound)
                meanings.formUnion(senses)
                if options.count == 4 { break }
            }
            return ListeningQuestion(wordID: word.id, options: options.map(\.id).shuffled())
        }
        self.lexicon = lexicon
        familyKey = family.map { FamilyPracticeProgress.key(familyID: $0.id, targets: targets.map(\.id)) }
        familyName = family?.root
        initialCount = questions.count
        _queue = State(initialValue: questions)
    }

    private static func soundKey(_ word: Word) -> String {
        (word.pronunciation ?? word.word).precomposedStringWithCanonicalMapping
            .filter { !"ˈˌ. ".contains($0) }.replacingOccurrences(of: "ɡ", with: "g")
    }

    private static func aliases(_ word: Word) -> Set<String> {
        let parts = ([word.meaning] + word.acceptedAnswers + (word.otherMeanings ?? [])).flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "；，、/;,")) }
        return Set(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    private var question: ListeningQuestion? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        let automaticQuestion = ready ? question : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !ready {
                    if loadFailed {
                        Text("这轮练习的进度暂时读不出来。")
                        Button("重新读取") { resume() }
                    } else {
                        ProgressView()
                    }
                } else if let q = question, let word = lexicon.word(id: q.wordID) {
                    if let familyName { Text("\(familyName) 词族").font(.headline).accessibilityIdentifier("cards.family") }
                    Text("第 \(index + 1) 张 · 共 \(queue.count) 张").font(.subheadline).foregroundStyle(MapStyle.secondary)
                    MapPanel {
                        VStack(alignment: .leading, spacing: 4) {
                            if q.retryDate != nil { Text("刚才那张，再想一次").font(.subheadline).foregroundStyle(MapStyle.secondary) }
                            Text(mode == .spelling ? "听到的是哪个单词？" : "听到的词是什么意思？")
                                .font(.title2.bold()).accessibilityIdentifier("cards.prompt")
                            Button { play(q) } label: {
                                Label("再听这个词", systemImage: "speaker.wave.2.circle.fill").font(.headline).frame(minHeight: 44)
                            }.buttonStyle(.plain).foregroundStyle(MapStyle.pine).accessibilityIdentifier("cards.listen")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if playbackFailed { Text("这次没播出声音，请点「再听这个词」。").font(.subheadline) }
                    if heard || nextDue != nil {
                        if nextDue == nil {
                            HStack(spacing: 10) { answerModes }
                        }
                        ForEach(q.options.compactMap { lexicon.word(id: $0) }) { option in choice(option, for: q, mode: mode) }
                        if let date = nextDue {
                            Text((chosen == q.wordID ? "选对了。 " : "再记一下。 ") + word.word + " · " + word.meaning)
                                .font(.headline).accessibilityIdentifier("cards.feedback")
                            WordPronunciationRow(word: word, prefix: "cards.answer", audioID: "cards.answer." + q.wordID)
                            Text(word.combined ?? word.plainCue ?? word.memoryCue).accessibilityIdentifier("cards.clue")
                            if let chosen, chosen != q.wordID, let other = lexicon.word(id: chosen) {
                                HStack(spacing: 5) {
                                    Text("刚才选的是 \(other.word) · \(other.meaning)")
                                        .font(.subheadline).accessibilityIdentifier("cards.comparison")
                                    SpeechButton(id: "cards.wrong." + other.id, text: other.word, pronunciation: other.pronunciation,
                                                 label: "听 " + other.word, identifier: "cards.wrongAudio")
                                        .labelStyle(.iconOnly)
                                }
                            }
                            Text("下次复习 · " + nextRecallDescription(date)).font(.subheadline)
                                .foregroundStyle(MapStyle.secondary).accessibilityIdentifier("cards.nextDate")
                            Button(index + 1 == queue.count ? "看本轮小结" : "下一张") { advance() }
                                .buttonStyle(.borderedProminent).tint(MapStyle.accent).foregroundStyle(MapStyle.onAccent)
                                .accessibilityIdentifier("cards.next")
                        } else {
                            Button("想不起来") { submit(nil, for: q) }.frame(minHeight: 44)
                                .accessibilityIdentifier("cards.unknown")
                        }
                        if saveFailed { Text("这次选择还没存好，请再点一次。").foregroundStyle(.red) }
                    }
                } else {
                    Image(systemName: "rectangle.stack.badge.checkmark").font(.largeTitle).foregroundStyle(MapStyle.pine)
                    Text("这一轮练完了").font(.title.bold()).accessibilityIdentifier("cards.done")
                    Text("共练了 \(initialCount) 个用法，第一次就选对了 \(initialCount - missed.count) 个。")
                    Text(missed.isEmpty ? "这些词到期时，会出现在课程首页。" : "有 \(missed.count) 个词还要练，到期时会先在课程首页出现。")
                    Button(finishTitle) {
                        if let onFinish { onFinish() } else { dismiss() }
                    }.buttonStyle(.borderedProminent).tint(MapStyle.accent).foregroundStyle(MapStyle.onAccent)
                        .accessibilityIdentifier("cards.close")
                }
            }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .id(question?.id)
        .background(MapStyle.page.ignoresSafeArea()).foregroundStyle(MapStyle.ink)
        .navigationTitle("听音卡片").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .onAppear { if !ready { resume() } }
        .task(id: automaticQuestion?.id) {
            guard let automaticQuestion, !Task.isCancelled, nextDue == nil else { return }
            play(automaticQuestion)
        }
        .onChange(of: speaker.lastCompletedID) { _, id in
            if let id, id == question?.audioID { heard = true }
        }
        .onDisappear { stop() }
    }

    @ViewBuilder private var answerModes: some View {
        ForEach(ListeningAnswer.allCases) { option in
            Button {
                guard mode != option else { return }
                mode = option
            } label: {
                Label(option == .meaning ? "选中文意思" : "选英文单词",
                      systemImage: mode == option ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline).frame(minHeight: 44)
            }
                .buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                .accessibilityAddTraits(mode == option ? .isSelected : [])
                .accessibilityIdentifier(option == .meaning ? "cards.mode.meaning" : "cards.mode.spelling")
        }
    }

    private func choice(_ option: Word, for q: ListeningQuestion, mode: ListeningAnswer) -> some View {
        let correct = nextDue != nil && q.wordID == option.id
        let wrong = nextDue != nil && chosen == option.id && !correct
        return Button { submit(option, for: q) } label: {
            HStack {
                Text(mode.label(option)).font(.body.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: correct ? "checkmark.circle.fill" : wrong ? "xmark.circle.fill" : "circle").accessibilityHidden(true)
            }
            .foregroundStyle(correct ? MapStyle.pine : MapStyle.ink).padding(.horizontal, 14).frame(minHeight: 47)
            .background(correct ? MapStyle.tintSurface : MapStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(correct || wrong ? MapStyle.pine : MapStyle.line, lineWidth: correct || wrong ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(nextDue != nil)
            .accessibilityLabel(mode.label(option)).accessibilityIdentifier("cards.choice." + option.id)
    }

    private func resume() {
        do {
            if let familyKey, let saved = try FamilyPracticeRecord.fetch(familyKey, in: context),
               let progress = try saved.progress(in: lexicon) {
                queue = progress.questions
                index = progress.nextIndex
                missed = progress.missed
                mode = progress.spelling ? .spelling : .meaning
            }
            loadFailed = false
            ready = true
        } catch { loadFailed = true }
    }

    private func saveProgress(questions: [ListeningQuestion], missed: Set<String>) throws {
        guard let familyKey else { return }
        let saved = try FamilyPracticeRecord.fetch(familyKey, in: context)
        guard index + 1 < questions.count else {
            if let saved { context.delete(saved) }
            return
        }
        let progress = FamilyPracticeProgress(questions: questions, nextIndex: index + 1,
                                              missed: missed, spelling: mode == .spelling)
        let payload = try JSONEncoder().encode(progress)
        if let saved { saved.payload = payload }
        else { context.insert(FamilyPracticeRecord(key: familyKey, payload: payload)) }
    }

    private func play(_ q: ListeningQuestion) {
        guard let word = lexicon.word(id: q.wordID) else { return }
        if speaker.activeID == q.audioID { speaker.stop(id: q.audioID) }
        LessonPlaybackTrace.note("question \(q.audioID) \(q.wordID)")
        playbackFailed = !speaker.toggle(id: q.audioID, text: word.word, pronunciation: word.pronunciation)
    }

    private func submit(_ option: Word?, for q: ListeningQuestion) {
        guard heard, nextDue == nil else { return }
        let correct = option?.id == q.wordID
        let answer = option.map { mode.label($0) } ?? "想不起来"
        do {
            let date: Date
            if let original = q.retryDate { date = original }
            else { date = try CourseReview.grade(q.wordID, as: correct ? .good : .again, attemptID: q.id, in: context) }
            let assisted = q.retryDate != nil
            let result = AnswerEvaluation(outcome: correct ? .correct : .incorrect, normalizedAnswer: answer,
                                          usedAssistance: assisted, isIndependentEvidence: false)
            context.insert(LearningAttemptRecord(reviewAttemptID: q.id, senseID: q.wordID, ability: .choiceRecognition,
                                                firstAnswer: answer, evaluation: result, wasShownAnswer: assisted))
            var updatedQueue = queue
            var updatedMissed = missed
            if !correct && !assisted {
                updatedMissed.insert(q.wordID)
                let retry = ListeningQuestion(wordID: q.wordID, options: q.options.shuffled(), retryDate: date)
                updatedQueue.insert(retry, at: min(updatedQueue.count, index + 3))
            }
            // The answer, FSRS grade and the next unanswered card survive or roll back together.
            try saveProgress(questions: updatedQueue, missed: updatedMissed)
            try context.save()
            queue = updatedQueue
            missed = updatedMissed
            saveFailed = false
            chosen = option?.id
            nextDue = date
        } catch {
            context.rollback()
            saveFailed = true
        }
    }

    private func advance() {
        stop()
        heard = false; playbackFailed = false; chosen = nil; nextDue = nil; saveFailed = false
        index += 1
    }

    private func stop() {
        if let id = speaker.activeID, id.hasPrefix("cards.") { speaker.stop(id: id) }
    }
}

struct MemoryCardsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let words: [Word]
    let lexicon: Lexicon
    var family: WordFamily? = nil

    var body: some View {
        NavigationStack {
            MemoryCardsView(words: words, lexicon: lexicon, family: family, onFinish: { dismiss() })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.accessibilityIdentifier("cards.dismiss") } }
        }
    }
}
