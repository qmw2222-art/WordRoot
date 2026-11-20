import SwiftData
import SwiftUI

private enum ListeningAnswer: String, CaseIterable, Identifiable {
    case meaning = "选意思"
    case spelling = "选单词"
    var id: Self { self }
    func label(_ word: Word) -> String { self == .spelling ? word.word : word.meaning }
}

private struct MemoryQuestion: Identifiable {
    let id = UUID()
    let word: Word
    var options: [Word]
    var retryDate: Date?
    var audioID: String { "cards.listen." + id.uuidString }
}

struct MemoryCardsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SpeechPlayer.self) private var speaker
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ListeningAnswer?
    @State private var queue: [MemoryQuestion]
    @State private var index = 0
    @State private var chosen: String?
    @State private var nextDue: Date?
    @State private var heard = false
    @State private var playbackFailed = false
    @State private var missed: Set<String> = []
    @State private var saveFailed = false
    let initialCount: Int

    init(words: [Word], lexicon: Lexicon) {
        var seen: Set<String> = []
        let targets = words.filter { seen.insert($0.id).inserted }
        let all = lexicon.families.flatMap(\.words) + Array(lexicon.basicWords.values)
        let sameSound = Dictionary(grouping: all, by: Self.soundKey)
        let allShuffled = all.shuffled()
        let questions = targets.map { word in
            let neighbors = lexicon.entry(id: word.id)?.family.words ?? []
            let pool = (neighbors + targets).shuffled() + allShuffled
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
            return MemoryQuestion(word: word, options: options.shuffled())
        }
        initialCount = questions.count
        _queue = State(initialValue: questions)
    }

    private static func soundKey(_ word: Word) -> String {
        (word.pronunciation ?? word.word).precomposedStringWithCanonicalMapping
            .filter { !"ˈˌ. ".contains($0) }.replacingOccurrences(of: "ɡ", with: "g")
    }

    private static func aliases(_ word: Word) -> Set<String> {
        let parts = ([word.meaning] + word.acceptedAnswers).flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "；，、/;,")) }
        return Set(parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
    }

    private var question: MemoryQuestion? { queue.indices.contains(index) ? queue[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let q = question {
                    Text("第 \(index + 1) 张 · 共 \(queue.count) 张").font(.subheadline).foregroundStyle(MapStyle.secondary)
                    MapPanel {
                        VStack(alignment: .leading, spacing: 4) {
                            if q.retryDate != nil { Text("刚才那张，再想一次").font(.subheadline).foregroundStyle(MapStyle.secondary) }
                            Text(mode == .spelling ? "听到的是哪个单词？" : mode == .meaning ? "这个词是什么意思？" : "听一听，在心里想一想")
                                .font(.title2.bold()).accessibilityIdentifier("cards.prompt")
                            Button { play(q) } label: {
                                Label("再听一遍", systemImage: "speaker.wave.2.circle.fill").font(.headline).frame(minHeight: 44)
                            }.buttonStyle(.plain).foregroundStyle(MapStyle.pine).accessibilityIdentifier("cards.listen")
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if playbackFailed { Text("这次没播出声音，请点「再听一遍」。").font(.subheadline) }
                    if heard || nextDue != nil {
                        if let mode {
                            ForEach(q.options) { option in choice(option, for: q, mode: mode) }
                        } else if nextDue == nil {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) { answerModes }
                                VStack(alignment: .leading, spacing: 4) { answerModes }
                            }
                        }
                        if let date = nextDue {
                            Text((chosen == q.word.id ? "选对了。 " : "再记一下。 ") + q.word.word + " · " + q.word.meaning)
                                .font(.headline).accessibilityIdentifier("cards.feedback")
                            WordPronunciationRow(word: q.word, prefix: "cards.answer", audioID: "cards.answer." + q.word.id)
                            Text(q.word.combined ?? q.word.plainCue ?? q.word.memoryCue).accessibilityIdentifier("cards.clue")
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
                    Button("完成") { dismiss() }.buttonStyle(.borderedProminent).tint(MapStyle.accent).foregroundStyle(MapStyle.onAccent)
                        .accessibilityIdentifier("cards.close")
                }
            }.frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }
        .id(question?.id)
        .background(MapStyle.page.ignoresSafeArea()).foregroundStyle(MapStyle.ink)
        .navigationTitle("听音卡片").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
        .task(id: question?.id) {
            guard let q = question, nextDue == nil else { return }
            play(q)
        }
        .onChange(of: speaker.lastCompletedID) { _, id in
            if let id, id == question?.audioID { heard = true }
        }
        .onDisappear { stop() }
    }

    @ViewBuilder private var answerModes: some View {
        ForEach(ListeningAnswer.allCases) { option in
            Button(option == .meaning ? "选中文意思" : "选英文单词") { mode = option }
                .buttonStyle(.bordered).frame(minHeight: 44).tint(MapStyle.pine)
                .accessibilityIdentifier(option == .meaning ? "cards.mode.meaning" : "cards.mode.spelling")
        }
    }

    private func choice(_ option: Word, for q: MemoryQuestion, mode: ListeningAnswer) -> some View {
        let correct = nextDue != nil && q.word.id == option.id
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

    private func play(_ q: MemoryQuestion) {
        if speaker.activeID == q.audioID { speaker.stop(id: q.audioID) }
        playbackFailed = !speaker.toggle(id: q.audioID, text: q.word.word, pronunciation: q.word.pronunciation)
    }

    private func submit(_ option: Word?, for q: MemoryQuestion) {
        guard heard, nextDue == nil else { return }
        let correct = option?.id == q.word.id
        let answer = option.flatMap { word in mode.map { $0.label(word) } } ?? "想不起来"
        do {
            let date: Date
            if let original = q.retryDate { date = original }
            else { date = try CourseReview.grade(q.word.id, as: correct ? .good : .again, attemptID: q.id, in: context) }
            let assisted = q.retryDate != nil
            let result = AnswerEvaluation(outcome: correct ? .correct : .incorrect, normalizedAnswer: answer,
                                          usedAssistance: assisted, isIndependentEvidence: false)
            context.insert(LearningAttemptRecord(reviewAttemptID: q.id, senseID: q.word.id, ability: .choiceRecognition,
                                                firstAnswer: answer, evaluation: result, wasShownAnswer: assisted))
            try context.save()
            if !correct && !assisted {
                missed.insert(q.word.id)
                let retry = MemoryQuestion(word: q.word, options: q.options.shuffled(), retryDate: date)
                queue.insert(retry, at: min(queue.count, index + 3))
            }
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
        heard = false; mode = nil; playbackFailed = false; chosen = nil; nextDue = nil; saveFailed = false
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

    var body: some View {
        NavigationStack {
            MemoryCardsView(words: words, lexicon: lexicon)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
