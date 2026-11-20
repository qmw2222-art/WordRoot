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
    private var finished: Bool { record?.isFinished(in: day) == true }
    private var learned: Set<String> { record?.credited(in: day) ?? [] }
    private var words: [Word] { day.words(in: lexicon) }
    private var studiedWords: [Word] { words.filter { learned.contains($0.id) } }
    private var word: Word? { (1...words.count).contains(position) ? words[position - 1] : nil }
    private var sound: String { "course.\(day.id).\(position)" }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if position == 0 { opening }
                    else if let word {
                        Text("第 \(position) / \(words.count) 个用法")
                            .font(.subheadline).foregroundStyle(MapStyle.secondary)
                        StudyCard(word: word, prefix: "course", soundID: sound, showsExample: false) {
                            sentence(for: word)
                        }.id(word.id)
                        if lexicon.entry(id: word.id) != nil {
                            Button { openWord(word.id) } label: {
                                Label("沿 \(word.word) 看关联词", systemImage: "point.3.connected.trianglepath.dotted")
                                    .frame(minHeight: 44)
                            }.accessibilityIdentifier("course.related.\(word.id)")
                        }
                    } else { recap }
                }
                .padding(20).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
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
        .sheet(isPresented: $showingCards) { MemoryCardsSheet(words: studiedWords, lexicon: lexicon) }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(day.title).font(.headline).foregroundStyle(MapStyle.pine)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(family.root).font(.system(size: 39, weight: .bold, design: .serif)).accessibilityIdentifier("course.root")
                    Text(family.meaning).font(.headline)
                }
                RootPronunciationRow(family: family, prefix: "course", soundID: sound + ".root", ink: MapStyle.onAccent)
                Text(day.id == 1 ? WordFamily.firstIntroduction : family.rootIntro).font(.subheadline)
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
            ForEach(Array(words.prefix(day.wordIDs.count).enumerated()), id: \.element.id) { index, w in
                branch(w, index: index)
            }
            familyLink
            if let first = day.basicIDs.first.flatMap({ lexicon.word(id: $0) }) {
                Text("学过这组词，再听一句").font(.headline).foregroundStyle(MapStyle.pine)
                sentence(for: first, overview: true)
            }
        }
    }

    /// An authored example is shared only by senses explicitly taught with that same sentence.
    @ViewBuilder private func sentence(for word: Word, overview: Bool = false) -> some View {
        let everyday = day.basicIDs.compactMap { lexicon.word(id: $0) }
        if day.id == 1 && word.id == "sense.portable.easy-carry" {
            VStack(alignment: .leading, spacing: 5) {
                SentenceInStudy(text: day.dialogue[0].text, translation: day.dialogue[0].translation,
                    neighbors: [], current: word.id, soundID: sound + ".question", open: openContextWord)
                SentenceInStudy(text: day.dialogue[1].text, translation: day.dialogue[1].translation,
                    neighbors: everyday.filter { $0.id == "basic.bag" }, current: word.id, soundID: sound + ".reply", open: openContextWord)
            }
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

    private func branch(_ w: Word, index: Int) -> some View {
        Button { go(index + 1) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(w.word).font(.system(.title3, design: .serif, weight: .semibold))
                    Text(w.id.hasPrefix("basic.") ? w.meaning : w.formation).font(.callout)
                }
                Spacer()
                Image(systemName: learned.contains(w.id) ? "checkmark" : "chevron.right").font(.caption)
            }.foregroundStyle(MapStyle.pine).padding(.horizontal, 13).padding(.vertical, 8)
                .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("course.branch.\(w.id)")
    }

    private var recap: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(finished ? "第 \(day.id) 天学完了" : "第 \(day.id) 天小结")
                .font(.largeTitle.bold()).foregroundStyle(MapStyle.pine).accessibilityIdentifier("course.done")
            Text("今天学过的 \(studiedWords.count) 个用法").font(.headline)
            StudiedWordsList(words: studiedWords, prefix: "course.recap")
            if finished && day.id < 100 {
                Button("接着学第 \(day.id + 1) 天", action: nextDay)
                    .frame(minHeight: 44).accessibilityIdentifier("course.followingDay")
            } else if finished {
                Button("回到课程路线", action: nextDay).frame(minHeight: 44).accessibilityIdentifier("course.followingDay")
            }
            talkLink
            if let nextFamily { Text("下次从 \(nextFamily.root)（\(nextFamily.meaning)）开始。").accessibilityIdentifier("course.tomorrow") }
            Button("今天先到这里", action: returnToCourse).buttonStyle(.bordered).accessibilityIdentifier("course.rest")
            familyLink
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if position > 0 {
                Button { go(position - 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 46) }
                    .accessibilityLabel("上一步").accessibilityIdentifier("course.previous")
            }
            Button {
                if position == day.lastStep && !studiedWords.isEmpty {
                    stopAudio()
                    showingCards = true
                } else { advance() }
            } label: {
                Text(position == day.lastStep && !studiedWords.isEmpty ? "开始听音练习" : nextTitle).font(.headline).frame(maxWidth: .infinity, minHeight: 47)
                    .background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(MapStyle.onAccent)
            }.accessibilityIdentifier(position == day.lastStep && !studiedWords.isEmpty ? "course.recapCards" : "course.next")
        }.buttonStyle(.plain).foregroundStyle(MapStyle.pine).padding(.horizontal, 20).padding(.vertical, 8).background(MapStyle.page)
    }

    private var nextMissing: Int? {
        var covered = learned
        if let word { covered.insert(word.id) }
        return day.lessonIDs.firstIndex { !covered.contains($0) }.map { $0 + 1 }
    }

    private var nextPosition: Int {
        if position == 0 { return 1 }
        if finished { return min(position + 1, day.lastStep) }
        let after = day.lessonIDs.dropFirst(position).firstIndex { !learned.contains($0) }
        return after.map { $0 + 1 } ?? nextMissing ?? day.lastStep
    }

    private var nextTitle: String {
        if position == day.lastStep && finished { return day.id == 100 ? "回到课程路线" : "接着学第 \(day.id + 1) 天" }
        let next = nextPosition
        if next == day.lastStep { return "学完第 \(day.id) 天" }
        let upcoming = words[next - 1]
        if day.basicIDs.contains(upcoming.id) {
            let action = learned.contains(upcoming.id) ? "重温" : "学"
            return "\(action) \(upcoming.word)（\(upcoming.primaryMeaning)）"
        }
        return "学 \(upcoming.word)"
    }

    private func advance() {
        if position == day.lastStep && finished { nextDay(); return }
        let next = nextPosition
        stopAudio()
        save(PendingSave(target: next, add: word?.id, complete: next == day.lastStep))
    }

    private func playGuide() {
        let lines: [GuideSpeech]
        if position == 0 { lines = family.openingSpeech(firstDay: day.id == 1) }
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
        row.step = pending.target
        row.updatedAt = .now
        if pending.complete && covered.isSuperset(of: day.lessonIDs) { row.completedAt = row.completedAt ?? .now }
        else if !alreadyFinished { row.completedAt = nil }
        do {
            if let id = pending.add { _ = try CourseReview.seed(id, in: context) }
            try context.save()
            step = pending.target
            retry = nil
        }
        catch { context.rollback(); retry = pending; failed = true }
    }
}
