import Foundation

enum CoursePhase: String, CaseIterable, Identifiable {
    case daily, travel
    case everyday = "other"

    var id: Self { self }

    var days: ClosedRange<Int> {
        switch self {
        case .daily: 1...40
        case .travel: 41...75
        case .everyday: 76...100
        }
    }

    var title: String {
        switch self {
        case .daily: "日常开口"
        case .travel: "实用旅行"
        case .everyday: "生活与工作"
        }
    }

    var topics: String {
        switch self {
        case .daily: "做饭、购物、出门和日常表达"
        case .travel: "订票、出行、住店和游览"
        case .everyday: "沟通、阅读、学习和工作"
        }
    }

    var symbol: String {
        switch self {
        case .daily: "sun.max"
        case .travel: "airplane"
        case .everyday: "bubble.left.and.bubble.right"
        }
    }
}

struct DailyCourse {
    let days: [CourseDay]
    let firstDayBySense: [String: Int]

    init(days: [CourseDay]) {
        self.days = days
        var firstDay: [String: Int] = [:]
        for day in days {
            for id in day.lessonIDs where firstDay[id] == nil { firstDay[id] = day.id }
        }
        firstDayBySense = firstDay
    }

    func loadDescription(for day: CourseDay) -> String {
        let newCount = day.lessonIDs.filter { firstDayBySense[$0] == day.id }.count
        let revisited = day.lessonIDs.count - newCount
        if revisited == 0 { return "这一组学 \(newCount) 个用法" }
        return "新学 \(newCount) 个用法，再用一遍 \(revisited) 个旧用法"
    }

    subscript(day: Int) -> CourseDay? {
        guard CourseDay.dayRange.contains(day) else { return nil }
        return days[day - 1]
    }

    static let bundled: Result<Self, Error> = Result {
        try load(from: .main, lexicon: Lexicon.bundled.get())
    }

    static func load(from bundle: Bundle, lexicon: Lexicon) throws -> Self {
        var days: [CourseDay] = []
        for phase in CoursePhase.allCases {
            guard let url = bundle.url(forResource: "course-" + phase.rawValue, withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            let units = try JSONDecoder().decode([CourseDay].self, from: Data(contentsOf: url))
            guard units.map(\.id) == Array(phase.days), units.allSatisfy({ $0.isValid(in: lexicon) }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            days += units
        }
        guard Set(days.flatMap(\.wordIDs)) == lexicon.familySenseIDs,
              Set(days.flatMap(\.lessonIDs)).isSuperset(of: lexicon.basicWords.keys) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Self(days: days)
    }
}

struct CourseDay: Decodable, Identifiable {
    static let dayRange = 1...100
    // Days 1–100 in existing stores belong to the original conversation course.
    static let recordOffset = 1000
    var recordID: Int { Self.recordOffset + id }
    var lastStep: Int { lessonIDs.count + 1 }
    var lessonIDs: [String] { wordIDs + basicIDs }

    let id: Int
    let familyID: String
    let title: String
    let guide: String
    let wordIDs: [String]
    let basicIDs: [String]
    let legacyWordCount: Int
    let bridge: LessonBridge
    let mission: SpeakingMission
    let scene: String
    let roles: [String]
    let dialogue: [Line]
    let recallDay: Int?

    struct Line: Decodable {
        let text: String
        let translation: String
    }

    func words(in lexicon: Lexicon) -> [Word] {
        lessonIDs.compactMap { lexicon.word(id: $0) }
    }

    fileprivate func isValid(in lexicon: Lexicon) -> Bool {
        let ids = lessonIDs
        return [title, guide, scene].allSatisfy { !$0.isEmpty }
            && (3...4).contains(legacyWordCount) && wordIDs.count >= legacyWordCount
            && Set(ids).count == ids.count
            && wordIDs.allSatisfy { lexicon.entry(id: $0)?.family.id == familyID }
            && wordIDs.contains(bridge.familyID) && ids.contains(bridge.basicID) && lexicon.basicWords[bridge.basicID] != nil
            && !bridge.text.isEmpty && !bridge.translation.isEmpty
            && basicIDs.allSatisfy { lexicon.basicWords[$0] != nil } && mission.turns.count == 2
            && roles.count == 2 && roles.allSatisfy { !$0.isEmpty }
            && dialogue.count == 2 && dialogue.allSatisfy { !$0.text.isEmpty && !$0.translation.isEmpty }
            && (recallDay.map { (1..<id).contains($0) } ?? (id == 1))
    }
}


struct LessonBridge: Decodable {
    let familyID: String
    let basicID: String
    let text: String
    let translation: String
}

struct SpeakingMission: Decodable {
    let goal: String
    let turns: [Turn]

    struct Turn: Codable {
        let partner: String
        let partnerZH: String
        let reply: String
        let replyZH: String
    }
}
