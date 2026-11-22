import SwiftData
import SwiftUI

struct CourseLessonView: View {
    @Environment(\.modelContext) private var context
    @Environment(SpeechPlayer.self) private var speaker
    @Query private var records: [CourseDayRecord]
    @AppStorage("wordroot.course.autoGuide") private var autoGuide = true
    @State private var step: Int?
    @State private var entered = false
    @State private var showingCards = false
    @State private var showingFamilyRecap = false
    @State private var failed = false
    @State private var audioFailed = false
    @State private var retry: PendingSave?
    let day: CourseDay
    let fromBeginning: Bool
    let nextFamily: WordFamily?
    let family: WordFamily
    let lexicon: Lexicon
    let openWord: (String) -> Void
    let returnToCourse: () -> Void
    let nextDay: () -> Void

    private struct PendingSave {
        let target: Int
        let add: String?
        let complete: Bool
        var reviewFamily = false
        var returnHome = false
    }

    init(day: CourseDay, fromBeginning: Bool, nextFamily: WordFamily?, family: WordFamily,
         lexicon: Lexicon, openWord: @escaping (String) -> Void,
         returnToCourse: @escaping () -> Void, nextDay: @escaping () -> Void) {
        self.day = day; self.fromBeginning = fromBeginning; self.nextFamily = nextFamily
        self.family = family; self.lexicon = lexicon
        self.openWord = openWord; self.returnToCourse = returnToCourse; self.nextDay = nextDay
        let id = day.recordID
        _records = Query(filter: #Predicate<CourseDayRecord> { $0.day == id })
    }

    private var record: CourseDayRecord? { records.first }
    private var position: Int { step ?? (fromBeginning ? 0 : record?.position(in: day) ?? 0) }
    private var teachingPosition: Int { day.teachingPosition(for: position) }
    private var finished: Bool { record?.isFinished(in: day) == true }
    private var learned: Set<String> { record?.credited(in: day) ?? [] }
    private var words: [Word] { day.words(in: lexicon) }
    private var studiedWords: [Word] { words.filter { learned.contains($0.id) } }
    private var studiedFamilyWords: [Word] {
        let familyIDs = Set(family.words.map(\.id))
        return studiedWords.filter { familyIDs.contains($0.id) }
    }
    private var missingFamilyIDs: [String] { day.taughtFamilyIDs.filter { !learned.contains($0) } }
    private var supplementTitle: String { "补学 " + family.root + " 剩下的 " + String(missingFamilyIDs.count) + " 个词" }
    private var word: Word? { (1...words.count).contains(position) ? words[position - 1] : nil }
    private var returnFromPracticeTitle: String {
        word.map { "继续学 \($0.studyLabel)" } ?? "回到本课小结"
    }
    private var sound: String { "course.\(day.id).\(position)" }

    var body: some View {
        VStack(spacing: 0) {
            if word != nil { LessonRootReminder(family: family, prefix: "course", soundID: sound + ".reminder") }
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if position == 0 { opening }
                    else if let word {
                        if !family.words.contains(where: { $0.id == word.id }) {
                            if learned.isSuperset(of: day.wordIDs), !missingFamilyIDs.isEmpty {
                                Button(supplementTitle, action: openRemainingFamily)
                                    .accessibilityIdentifier("course.supplementFamily")
                            }
                            Text("在句子里用这个词").font(.headline).foregroundStyle(MapStyle.pine)
                        }
                        if let group = day.studyGroup(at: teachingPosition) {
                            Text("这组 \(teachingPosition - group.lowerBound + 1) / \(group.count) · 本课 \(teachingPosition) / \(words.count)")
                                .font(.subheadline).foregroundStyle(MapStyle.secondary)
                                .accessibilityIdentifier("course.group")
                        }
                        if !showingFamilyRecap { StudyCard(word: word, prefix: "course", soundID: sound, showsExample: false) {
                            sentence(for: word)
                        }.id(word.id) }
                        if day.dailyStart == true, day.id > DailyCourse.freeDays.upperBound,
                           let focus = day.starterExamples?.first,
                           focus.ids.first(where: { day.studyBasicIDs.contains($0) }) == word.id {
                            talkLink
                        }
                        if lexicon.entry(id: word.id) != nil {
                            Button { openWord(word.id) } label: {
                                Label("沿 \(word.word) 看关联词", systemImage: "point.3.connected.trianglepath.dotted")
                                    .frame(minHeight: 44)
                            }.accessibilityIdentifier("course.related.\(word.id)")
                        }
                    } else { recap }
                }
                .padding(.horizontal, word == nil ? 16 : 20)
                .padding(.top, word == nil ? 8 : 20).padding(.bottom, 20)
                .frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }
            .id(position)
            controls
        }
        .background(MapStyle.page.ignoresSafeArea()).foregroundStyle(MapStyle.ink)
        .toolbar(.visible, for: .navigationBar).toolbarBackground(MapStyle.page, for: .navigationBar)
        .navigationTitle("第 \(day.id) 天").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    autoGuide.toggle()
                    if autoGuide { playGuide() } else { stopAudio() }
                } label: { Image(systemName: autoGuide ? "speaker.wave.2" : "speaker.slash") }
                .accessibilityLabel(autoGuide ? "关闭自动讲解" : "开启自动讲解")
                .accessibilityIdentifier("course.lessonAutoVoice")
            }
        }
        .onAppear {
            guard !entered else { return }
            entered = true
            if records.isEmpty || fromBeginning { save(PendingSave(target: 0, add: nil, complete: false)) }
            if autoGuide && position == 0 { playGuide() }
        }
        .onChange(of: position) { _, next in if entered && autoGuide && next == 0 { playGuide() } }
        .onDisappear { stopAudio() }
        .sheet(isPresented: $showingCards) { MemoryCardsSheet(words: studiedFamilyWords, lexicon: lexicon, family: family) }
        .sheet(isPresented: $showingFamilyRecap) {
            NavigationStack {
                ScrollView {
                    StudiedWordsList(words: studiedFamilyWords, prefix: "course.familyRecap").padding()
                }
                .navigationTitle("\(family.root) · \(studiedFamilyWords.count) 个词")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    NavigationLink {
                        MemoryCardsView(words: studiedFamilyWords, lexicon: lexicon, family: family,
                                        finishTitle: returnFromPracticeTitle, onFinish: { showingFamilyRecap = false })
                    } label: {
                        Label("练 \(family.root) 词族听音卡", systemImage: "speaker.wave.2")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(MapStyle.accent).padding(.horizontal)
                    .accessibilityIdentifier("course.familyRecap.cards")
                }
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    Button(returnFromPracticeTitle) { showingFamilyRecap = false }.accessibilityIdentifier("course.familyRecap.close")
                } }
            }
        }
        .alert("学习位置暂时没有保存", isPresented: $failed) {
            Button("重试") { if let retry { save(retry) } }
            Button("知道了", role: .cancel) {}
        }
    }

    private var familyLink: some View {
        NavigationLink { FamilyStudyView(family: family, lexicon: lexicon) } label: {
            Label("学完整个 \(family.root) 词族 · \(family.words.count) 个用法", systemImage: "point.3.connected.trianglepath.dotted")
                .frame(minHeight: 44)
        }.accessibilityIdentifier("course.family.all")
    }

    private var talkLink: some View {
        NavigationLink { DailySpeakingView(day: day) } label: {
            Label("用今天的词开口", systemImage: "bubble.left.and.bubble.right").frame(minHeight: 44)
        }.accessibilityIdentifier("course.talk")
    }

    private var opening: some View {
        VStack(alignment: .leading, spacing: words.count > 18 ? 6 : 10) {
            Text(day.title).font(.headline).foregroundStyle(MapStyle.pine)
            HStack(spacing: 8) {
                Text(family.root).font(.system(.title, design: .serif, weight: .bold))
                    .accessibilityIdentifier("course.root")
                Text("\(family.rootKind) · \(family.meaning)").font(.headline)
                Spacer(minLength: 0)
                RootPronunciationRow(family: family, prefix: "course", soundID: sound + ".root", ink: MapStyle.onAccent)
            }
            .foregroundStyle(MapStyle.onAccent).padding(.horizontal, 12)
            .background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 13))
            Text(day.firstBoundRoot ? WordFamily.firstIntroduction : family.rootIntro).font(.subheadline)
            WordOverviewGrid(words: words, prefix: "course.branch.", learned: learned) { word in
                if let index = day.lessonIDs.firstIndex(of: word.id) { go(index + 1) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(day.guide).accessibilityIdentifier("course.guide")
                Button {
                    if speaker.activeID == sound { stopAudio() } else { playGuide() }
                } label: {
                    Label(speaker.activeID == sound ? "停止讲解" : "听老师讲记法", systemImage: "play.circle.fill")
                        .font(.headline).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("course.demo")
                    .accessibilityValue(speaker.activeID == sound ? "带读中" : "可播放")
                if audioFailed { Text("声音暂时无法播放，请再点一次。").font(.footnote) }
            }
            .foregroundStyle(MapStyle.onAccent).frame(maxWidth: .infinity, alignment: .leading)
            .padding(15).background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 17))
            familyLink
            if let first = (day.starterExamples?.first?.ids.first ?? day.studyBasicIDs.first).flatMap({ lexicon.word(id: $0) }) {
                Text("今天用得上的一句").font(.headline).foregroundStyle(MapStyle.pine)
                sentence(for: first, overview: true)
            }
        }
    }

    /// An authored example is shared only by senses explicitly taught with that same sentence.
    @ViewBuilder private func sentence(for word: Word, overview: Bool = false) -> some View {
        let everyday = day.studyBasicIDs.compactMap { lexicon.word(id: $0) }
        if day.unitID == 1 && word.id == "sense.portable.easy-carry" {
            VStack(alignment: .leading, spacing: 5) {
                SentenceInStudy(text: day.dialogue[0].text, translation: day.dialogue[0].translation,
                    neighbors: [], current: word.id, soundID: sound + ".question", open: openContextWord)
                SentenceInStudy(text: day.dialogue[1].text, translation: day.dialogue[1].translation,
                    neighbors: everyday.filter { $0.id == "basic.bag" }, current: word.id, soundID: sound + ".reply", open: openContextWord)
            }
        } else if let example = day.starterExample(for: word.id) {
            SentenceInStudy(text: example.text, translation: example.translation,
                            neighbors: example.ids.compactMap { lexicon.word(id: $0) },
                            current: overview ? nil : word.id, soundID: sound + ".use",
                            open: openContextWord, pieces: example.pieces)
        } else if word.id == day.bridge.familyID, let neighbor = lexicon.word(id: day.bridge.basicID) {
            SentenceInStudy(text: day.bridge.text, translation: day.bridge.translation, neighbors: [neighbor],
                            current: word.id, soundID: sound + ".use", open: openContextWord)
        } else {
            SentenceInStudy(text: word.example, translation: word.translation,
                            neighbors: everyday.filter { $0.example == word.example && $0.translation == word.translation },
                            current: overview ? nil : word.id, soundID: sound + ".use", open: openContextWord)
        }
    }

    private func openContextWord(_ id: String) {
        guard let index = day.lessonIDs.firstIndex(of: id) else { return }
        go(index + 1)
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(finished ? "第 \(day.id) 天学完了" : "第 \(day.id) 天小结")
                .font(.largeTitle.bold()).foregroundStyle(MapStyle.pine).accessibilityIdentifier("course.done")
            Text("本课学过的 \(studiedWords.count) 个用法").font(.headline)
            StudiedWordsList(words: studiedWords, prefix: "course.recap")
            if finished && !studiedFamilyWords.isEmpty {
                Button("复习 \(family.root) 词族听音卡") {
                    stopAudio()
                    showingCards = true
                }.frame(minHeight: 44).accessibilityIdentifier("course.recapCards")
            }
            talkLink
            NavigationLink { TransferPracticeView(day: day, later: false) } label: {
                Label("换个条件试一句", systemImage: "bubble.left.and.text.bubble.right").frame(minHeight: 44)
            }.accessibilityIdentifier("course.transfer")
            if let nextFamily { Text("下次从 \(nextFamily.root)（\(nextFamily.meaning)）开始。").accessibilityIdentifier("course.tomorrow") }
            Button("今天先到这里", action: returnToCourse).buttonStyle(.bordered).accessibilityIdentifier("course.rest")
            familyLink
        }
    }

    private var canPauseAfterWord: Bool {
        guard let group = day.studyGroup(at: teachingPosition), teachingPosition == group.upperBound,
              !finished, !justLearnedFamily, nextPosition < day.lastStep else { return false }
        return group.dropLast().allSatisfy { learned.contains(day.teachingOrder[$0 - 1]) }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if position > 0 {
                Button { go(day.previousPosition(from: position)) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 46) }
                    .accessibilityLabel("上一步").accessibilityIdentifier("course.previous")
            }
            if canPauseAfterWord, let word {
                Button("先学到这里") {
                    stopAudio()
                    save(PendingSave(target: nextPosition, add: word.id, complete: false, returnHome: true))
                }
                .font(.subheadline).frame(minHeight: 44)
                .accessibilityIdentifier("course.pause")
                .accessibilityHint("保存进度，回到首页")
            }
            Button {
                if position == day.lastStep && !missingFamilyIDs.isEmpty {
                    openRemainingFamily()
                } else { advance() }
            } label: {
                Text(controlsTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 47)
                    .background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(MapStyle.onAccent)
            }.accessibilityIdentifier(controlsID)
        }.buttonStyle(.plain).foregroundStyle(MapStyle.pine).padding(.horizontal, 20).padding(.vertical, 8).background(MapStyle.page)
    }

    private var controlsTitle: String {
        guard position == day.lastStep else { return nextTitle }
        if !missingFamilyIDs.isEmpty { return supplementTitle }
        return nextTitle
    }

    private var controlsID: String {
        guard position == day.lastStep else { return "course.next" }
        if !missingFamilyIDs.isEmpty { return "course.supplementFamily" }
        return finished ? "course.followingDay" : "course.next"
    }

    private func openRemainingFamily() {
        if let first = missingFamilyIDs.first, let offset = day.lessonIDs.firstIndex(of: first) {
            go(offset + 1)
        }
    }

    private var nextMissing: Int? {
        var covered = learned
        if let word { covered.insert(word.id) }
        return day.lessonIDs.firstIndex { !covered.contains($0) }.map { $0 + 1 }
    }

    private var nextPosition: Int {
        if position == 0 {
            return day.teachingOrder.first.flatMap { day.lessonIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? 1
        }
        if finished {
            if let word, missingFamilyIDs.contains(word.id) {
                guard let next = missingFamilyIDs.first(where: { $0 != word.id }),
                      let offset = day.lessonIDs.firstIndex(of: next) else { return day.lastStep }
                return offset + 1
            }
            let next = teachingPosition
            guard next < day.teachingOrder.count, let index = day.lessonIDs.firstIndex(of: day.teachingOrder[next]) else { return day.lastStep }
            return index + 1
        }
        if day.dailyStart == true && day.id > DailyCourse.freeDays.upperBound {
            let covered = learned.union(word.map { [$0.id] } ?? [])
            return day.teachingOrder.first { !covered.contains($0) }
                .flatMap { day.lessonIDs.firstIndex(of: $0) }.map { $0 + 1 } ?? day.lastStep
        }
        let after = day.lessonIDs.dropFirst(position).firstIndex { !learned.contains($0) }
        return after.map { $0 + 1 } ?? nextMissing ?? day.lastStep
    }

    private var justLearnedFamily: Bool {
        guard let word, day.taughtFamilyIDs.contains(word.id), !learned.contains(word.id) else { return false }
        return Set(day.taughtFamilyIDs).isSubset(of: learned.union([word.id]))
    }

    private var nextTitle: String {
        if justLearnedFamily { return "看 \(family.root) 词表，练听音卡" }
        if position == day.lastStep && finished {
            guard let nextFamily else { return "回到课程路线" }
            return "开始第 \(day.id + 1) 天 · \(nextFamily.root)（\(nextFamily.meaning)）"
        }
        let next = nextPosition
        if next == day.lastStep { return "学完第 \(day.id) 天" }
        let upcoming = words[next - 1]
        let action = learned.contains(upcoming.id) ? "重温" : "学"
        return "\(action) \(upcoming.studyLabel)"
    }

    private func advance() {
        if position == day.lastStep && finished { nextDay(); return }
        let next = nextPosition
        stopAudio()
        save(PendingSave(target: next, add: word?.id, complete: next == day.lastStep, reviewFamily: justLearnedFamily))
    }

    private func playGuide() {
        let lines: [GuideSpeech]
        if position == 0 { lines = family.openingSpeech(firstDay: day.firstBoundRoot, mnemonic: day.guide) }
        else if let word { lines = word.studyNarration }
        else { return }
        if speaker.activeID != sound { audioFailed = !speaker.toggleGuide(id: sound, lines: lines) }
    }

    private func stopAudio() {
        if let id = speaker.activeID, (id.hasPrefix("course.\(day.id).") || id.hasPrefix("course.recap.")) { speaker.stop(id: id) }
    }
    private func go(_ next: Int) { stopAudio(); save(PendingSave(target: next, add: nil, complete: false)) }

    private func save(_ pending: PendingSave) {
        let row = record ?? CourseDayRecord(day: day.recordID)
        let alreadyFinished = row.isFinished(in: day)
        var covered = row.credited(in: day)
        if let add = pending.add { covered.insert(add) }
        if row.modelContext == nil { context.insert(row) }
        row.studiedIDs = day.lessonIDs.filter(covered.contains)
        row.step = day.storedStep(for: pending.target)
        row.updatedAt = .now
        if pending.complete && covered.isSuperset(of: day.lessonIDs) { row.completedAt = row.completedAt ?? .now }
        else if !alreadyFinished { row.completedAt = nil }
        do {
            if let id = pending.add { _ = try CourseReview.seed(id, in: context) }
            try context.save()
            step = pending.target
            if pending.reviewFamily { stopAudio(); showingFamilyRecap = true }
            retry = nil
            if pending.returnHome { returnToCourse() }
        }
        catch { context.rollback(); retry = pending; failed = true }
    }
}
