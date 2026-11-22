import SwiftData
import SwiftUI

struct ReviewRound: Identifiable {
    let id = UUID()
    let words: [Word]
    var family: WordFamily? = nil
}

struct HomeLearningProgress: View {
    @Query private var cards: [ReviewCardRecord]
    let lexicon: Lexicon
    let course: DailyCourse
    let lessons: [CourseDayRecord]
    let studyDefaults: UserDefaults
    let completedDayCount: Int
    let start: ([Word]) -> Void

    private struct Item {
        let word: Word
        let due: Date
        let weak: Bool
        let day: Int
    }

    private var scheduledWords: [Item] {
        var studied = Set<String>()
        for row in lessons {
            if let day = course.day(forRecord: row.day) { studied.formUnion(row.credited(in: day)) }
        }
        // Earlier versions stored the last word of a family in preferences only.
        for family in lexicon.families {
            guard let cursor = studyDefaults.string(forKey: "wordroot.familyStudy." + family.id) else { continue }
            if cursor == "finished" { studied.formUnion(family.words.map(\.id)) }
            else if let position = family.words.firstIndex(where: { $0.id == cursor }) {
                studied.formUnion(family.words.prefix(position).map(\.id))
            }
        }
        let schedules = Dictionary(cards.filter { $0.ability == .meaningRecall }.map { (WordSense.canonical($0.senseID), $0) },
                                   uniquingKeysWith: { $0.updatedAt > $1.updatedAt ? $0 : $1 })
        return studied.union(schedules.keys).compactMap { id in
            guard let word = lexicon.word(id: id) else { return nil }
            let card = schedules[id]
            return Item(word: word, due: card?.state?.card.due ?? .distantPast,
                        weak: card?.isWeakCard == true, day: course.firstDayBySense[id] ?? 101)
        }.sorted {
            if $0.weak != $1.weak { return $0.weak }
            return ($0.due, $0.day, $0.word.id) < ($1.due, $1.day, $1.word.id)
        }
    }

    var body: some View {
        let items = scheduledWords
        let now = Date.now
        let dueDates = Set(items.map(\.due).filter { $0 > now })
        TimelineView(.explicit([now] + dueDates.sorted())) { clock in
            let due = items.filter { $0.due <= clock.date }
            if !due.isEmpty {
                Button { start(due.prefix(10).map(\.word)) } label: {
                    Label("练到期的听音卡 · \(min(due.count, 10)) 个词", systemImage: "ear")
                        .font(.headline).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityIdentifier("home.due")
                    .accessibilityValue("共有\(due.count)个词到期")
                    .accessibilityHint("每轮最多练十个词")
            }
        }
        Divider().overlay(MapStyle.onAccent.opacity(0.24))
        Text("已完成 \(completedDayCount) / \(course.days.count) 天")
            .font(.footnote)
            .accessibilityIdentifier("course.completedCount")
        let total = lexicon.familySenseIDs.union(lexicon.basicWords.keys).count
        Text("已学 \(items.count) / \(total) 个用法")
            .font(.footnote).accessibilityIdentifier("course.learnedSenses")
        ProgressView(value: Double(completedDayCount), total: Double(course.days.count))
            .tint(MapStyle.onAccent)
            .accessibilityHidden(true)
    }
}

private func reviewDate(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: Locale(identifier: "zh_CN")))
}

func nextRecallDescription(_ due: Date, now: Date = .now) -> String {
    let seconds = max(0, due.timeIntervalSince(now))
    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                               to: Calendar.current.startOfDay(for: due)).day ?? 0
    let interval = days > 0 ? "\(days) 天后" : seconds < 3600 ? "\(max(1, Int(ceil(seconds / 60)))) 分钟后" : "今天稍后"
    return interval + "（" + reviewDate(due) + "）"
}
