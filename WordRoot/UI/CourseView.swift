import SwiftData
import SwiftUI

struct CourseView: View {
    @Query(filter: #Predicate<CourseDayRecord> { $0.day > 1000 && $0.day <= 1100 },
           sort: \CourseDayRecord.updatedAt, order: .reverse) private var records: [CourseDayRecord]
    @Environment(SubscriptionService.self) private var subscription
    @State private var path: [Route] = []
    @State private var review: ReviewRound?
    @AppStorage("wordroot.course.autoGuide") private var autoGuide = true
    let course: DailyCourse
    let lexicon: Lexicon
    let studyDefaults: UserDefaults
    let openWord: (String) -> Void

    private enum Route: Hashable {
        case phase(CoursePhase)
        case day(Int, fromBeginning: Bool = false)
    }

    private var completedDays: Set<Int> {
        Set(records.compactMap { row in
            guard let day = course[row.day - CourseDay.recordOffset], row.isFinished(in: day) else { return nil }
            return day.id
        })
    }

    private var suggestedDay: CourseDay? {
        if let lastOpened = records.first, let day = course[lastOpened.day - CourseDay.recordOffset],
           !lastOpened.isFinished(in: day) { return day }
        return course.days.first { !completedDays.contains($0.id) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    header
                    today
                    VStack(alignment: .leading, spacing: 10) {
                        Text("课程路线").font(.headline).foregroundStyle(MapStyle.pine)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(CoursePhase.allCases) { phase in
                            phaseCard(phase)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 30)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(MapStyle.page.ignoresSafeArea())
            .navigationTitle("100 天英语")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .phase(let phase):
                    phaseDays(phase)
                case let .day(number, fromBeginning):
                    if let day = course[number], let family = lexicon.family(id: day.familyID) {
                        MembershipGate(free: DailyCourse.freeDays.contains(number), context: "接着学第 \(number) 天 · \(family.root)") {
                            CourseLessonView(
                                day: day, fromBeginning: fromBeginning,
                                nextFamily: course[number + 1].flatMap { lexicon.family(id: $0.familyID) },
                                family: family, lexicon: lexicon,
                                openWord: openWord, returnToCourse: { path.removeAll() },
                                nextDay: {
                                    guard path.last == route else { return }
                                    if course[number + 1] != nil {
                                        path.removeLast()
                                        if case .phase(let phase) = path.last, !phase.days.contains(number + 1) {
                                            path.removeLast()
                                        }
                                        path.append(.day(number + 1))
                                    } else {
                                        path.removeAll()
                                    }
                                }
                            )
                            .id(day.id)
                        }
                    }
                }
            }
        }
        .sheet(item: $review) { MemoryCardsSheet(words: $0.words, lexicon: lexicon) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("100 天英语")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(MapStyle.pine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("course.title")
            Text("每天从一个词根或熟词出发，听读音，拆开记，再把词用进一句话。")
                .font(.subheadline)
                .foregroundStyle(MapStyle.secondary)
        }
    }

    private var today: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let day = suggestedDay, let family = lexicon.family(id: day.familyID) {
                let words = day.words(in: lexicon)
                let step = records.first { $0.day == day.recordID }?.position(in: day) ?? 0
                Text("第 \(day.id) 天")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("course.suggestedDay")
                Text("\(family.root) · \(family.meaning)")
                    .font(.system(.title, design: .serif, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                Text(day.title).font(.headline)
                if day.id == 1 {
                    Text("先记住 port 是「带、运」。在前面加一小段，就能看懂进口和出口。").font(.subheadline)
                } else {
                    Text(course.loadDescription(for: day)).font(.subheadline)
                }
                NavigationLink(value: Route.day(day.id)) {
                    HStack {
                        Text(startTitle(day: day, words: words, step: step))
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .font(.headline)
                    .foregroundStyle(MapStyle.pine)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 48)
                    .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("course.start")
                if step > 0 {
                    NavigationLink(value: Route.day(day.id, fromBeginning: true)) {
                        Label(day.id == 1 ? "从头跟学第一课" : "从头跟学这一天", systemImage: "arrow.counterclockwise")
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("course.restart")
                }
                Button { autoGuide.toggle() } label: {
                    Label(autoGuide ? "自动带读已开启" : "自动带读已关闭",
                          systemImage: autoGuide ? "speaker.wave.2" : "speaker.slash")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint(autoGuide ? "轻点后可安静地看文字" : "轻点后会在课里自动播放示范")
                .accessibilityIdentifier("course.autoVoice")
            } else {
                Label("100 天课程已完成", systemImage: "checkmark.seal.fill")
                    .font(.title2.weight(.bold))
                Text("回到下面的课程路线，就能重温任何一组词。")
            }
            HomeDuePractice(lexicon: lexicon, course: course, lessons: records, studyDefaults: studyDefaults) { words in
                review = ReviewRound(words: words)
            }
            Divider().overlay(MapStyle.onAccent.opacity(0.24))
            Text("已完成 \(completedDays.count) / \(course.days.count) 天")
                .font(.footnote)
                .accessibilityIdentifier("course.completedCount")
            let studied = records.reduce(into: Set<String>()) { result, row in
                if let day = course[row.day - CourseDay.recordOffset] { result.formUnion(row.credited(in: day)) }
            }
            let total = lexicon.familySenseIDs.union(lexicon.basicWords.keys).count
            Text("已学 \(studied.count) / \(total) 个用法")
                .font(.footnote).accessibilityIdentifier("course.learnedSenses")
            ProgressView(value: Double(completedDays.count), total: Double(course.days.count))
                .tint(MapStyle.onAccent)
                .accessibilityHidden(true)
        }
        .foregroundStyle(MapStyle.onAccent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(19)
        .background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 23))
    }

    private func startTitle(day: CourseDay, words: [Word], step: Int) -> String {
        if !DailyCourse.freeDays.contains(day.id) && !subscription.hasAccess { return "开通后学第 \(day.id) 天" }
        if step == 0 { return day.id == 1 ? "跟我学第一课" : "跟我学第 \(day.id) 天" }
        if step <= words.count { return "继续学 \(words[step - 1].word)" }
        return "继续第 \(day.id) 天的小结"
    }

    private func phaseCard(_ phase: CoursePhase) -> some View {
        NavigationLink(value: Route.phase(phase)) {
            MapPanel {
                HStack(spacing: 13) {
                    Image(systemName: phase.symbol)
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(MapStyle.tintSurface, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phase.title).font(.headline)
                        Text("第 \(phase.days.lowerBound)–\(phase.days.upperBound) 天 · \(phase.topics)")
                            .font(.footnote)
                            .foregroundStyle(MapStyle.secondary)
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(MapStyle.pine)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("course.phase.\(phase.rawValue)")
    }

    private func phaseDays(_ phase: CoursePhase) -> some View {
        List {
            Section {
                ForEach(phase.days.compactMap { course[$0] }) { day in
                    NavigationLink(value: Route.day(day.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Label(
                                "第 \(day.id) 天 · \(day.title)",
                                systemImage: !DailyCourse.freeDays.contains(day.id) && !subscription.hasAccess ? "lock" : completedDays.contains(day.id) ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.headline)
                            .foregroundStyle(MapStyle.pine)
                            Text(day.wordIDs.compactMap { lexicon.word(id: $0)?.word }.joined(separator: " · "))
                                .font(.subheadline).foregroundStyle(MapStyle.secondary)
                        }
                        .padding(.vertical, 7)
                    }
                    .listRowBackground(MapStyle.surface)
                    .accessibilityValue(!DailyCourse.freeDays.contains(day.id) && !subscription.hasAccess ? "开通后学习" : completedDays.contains(day.id) ? "已完成" : "")
                    .accessibilityIdentifier("course.day.\(day.id)")
                }
            } header: {
                Text(phase.topics)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MapStyle.page)
        .navigationTitle(phase.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
