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
    static let freeDays = 1...10
    let days: [CourseDay]
    let firstDayByFamily: [String: Int]
    let firstDayBySense: [String: Int]

    private let displayDayByRecord: [Int: Int]

    private let previousDays: [CourseDay]?

    init(days: [CourseDay], previousDays: [CourseDay]? = nil) {
        self.previousDays = previousDays
        displayDayByRecord = Dictionary(uniqueKeysWithValues: days.map { ($0.recordID, $0.id) })
        self.days = days
        var firstDay: [String: Int] = [:]
        for day in days {
            for id in day.lessonIDs where firstDay[id] == nil { firstDay[id] = day.id }
        }
        firstDayBySense = firstDay
        firstDayByFamily = Dictionary(days.map { ($0.familyID, $0.id) }, uniquingKeysWith: min)
    }

    func day(forRecord record: Int) -> CourseDay? {
        displayDayByRecord[record].flatMap { self[$0] }
    }

    // A saved lesson keeps its original cards, their order, and the meaning of its saved step.
    func preservingLegacyRecords(_ records: Set<Int>) -> Self {
        let started = Set(records.filter { CourseDay.legacyRecords.contains($0) })
        let returning = !started.isEmpty || records.contains(where: CourseDay.plannedRecords.contains)
        guard returning, let previousDays else { return self }
        guard !started.isEmpty else { return Self(days: previousDays) }
        var lessons = previousDays
        for i in lessons.indices where started.contains(CourseDay.recordOffset + lessons[i].unitID) {
            lessons[i].plannedBasicIDs = nil
        }
        // If a frozen lesson would have introduced a newly assigned word, teach it
        // in its original topic. Every mixed course still covers the full vocabulary.
        var scheduled = Set(lessons.flatMap(\.lessonIDs))
        for i in lessons.indices where lessons[i].plannedBasicIDs != nil {
            let missing = lessons[i].basicIDs.filter { scheduled.insert($0).inserted }
            lessons[i].plannedBasicIDs?.append(contentsOf: missing)
        }
        return Self(days: lessons)
    }

    func isFree(wordID: String) -> Bool {
        firstDayBySense[wordID].map(Self.freeDays.contains) ?? false
    }

    func isFree(familyID: String) -> Bool {
        firstDayByFamily[familyID].map(Self.freeDays.contains) ?? false
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
        var introduced = Set<String>()
        for index in days.indices where introduced.insert(days[index].familyID).inserted {
            let scheduled = Set(days[index].lessonIDs)
            let family = lexicon.family(id: days[index].familyID)!
            days[index].addedFamilyIDs = family.words.map(\.id).filter { !scheduled.contains($0) }
        }
        struct PathEntry: Decodable {
            let unit: Int
            let basicIDs: [String]
            let familyIDs: [String]?
            let examples: [LessonPhrase]?
            let previousDay: Int?
            let previousBasicIDs: [String]?
            let previousFamilyIDs: [String]?
        }
        guard let url = bundle.url(forResource: "learning-path", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let path = try JSONDecoder().decode([PathEntry].self, from: Data(contentsOf: url))
        guard path.count == days.count, Set(path.map(\.unit)) == Set(days.map(\.id)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let originalIDs = Set(days.flatMap(\.lessonIDs))
        var seenFamilies = Set<String>()
        let ordered = try path.enumerated().map { index, entry -> CourseDay in
            var unit = days[entry.unit - 1]
            unit.dailyStart = true
            unit.sourceUnit = entry.unit
            unit.id = index + 1
            let originalFamily = unit.taughtFamilyIDs
            if let familyIDs = entry.familyIDs {
                guard familyIDs.count == originalFamily.count, Set(familyIDs) == Set(originalFamily) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            unit.plannedFamilyIDs = entry.familyIDs
            unit.plannedBasicIDs = entry.basicIDs
            unit.starterExamples = entry.examples
            let ids = unit.lessonIDs
            if let examples = entry.examples {
                let targets = examples.flatMap(\.ids)
                guard Set(targets).count == targets.count, Set(ids).isSuperset(of: targets),
                      examples.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
            }
            guard entry.basicIDs.allSatisfy({ lexicon.basicWords[$0] != nil }),
                  Set(ids).count == ids.count, ids.contains(unit.bridge.basicID) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if seenFamilies.insert(unit.familyID).inserted,
               Set(unit.taughtFamilyIDs) != Set(lexicon.family(id: unit.familyID)!.words.map(\.id)) {
                throw CocoaError(.fileReadCorruptFile)
            }
            return unit
        }
        guard Set(ordered.flatMap(\.lessonIDs)) == originalIDs else { throw CocoaError(.fileReadCorruptFile) }
        // Restore the exact order of earlier editions for learners who already started.
        let previous = zip(path, ordered).map { entry, current -> CourseDay in
            var day = current
            day.id = entry.previousDay ?? current.id
            day.dailyStart = false
            if let ids = entry.previousBasicIDs { day.plannedBasicIDs = ids }
            if let ids = entry.previousFamilyIDs { day.plannedFamilyIDs = ids }
            let taught = Set(day.lessonIDs)
            day.starterExamples = day.starterExamples?.compactMap { phrase in
                var copy = phrase
                copy.ids = copy.ids.filter(taught.contains)
                return copy.ids.isEmpty ? nil : copy
            }
            return day
        }.sorted { $0.id < $1.id }
        guard previous.map(\.id) == Array(CourseDay.dayRange),
              Set(previous.flatMap(\.lessonIDs)) == originalIDs else { throw CocoaError(.fileReadCorruptFile) }
        return Self(days: ordered, previousDays: previous)
    }
}

struct LessonPhrase: Decodable {
    struct Piece: Decodable {
        let text: String
        let meaning: String
    }

    var ids: [String]
    let translation: String
    let pieces: [Piece]
    var text: String { pieces.map(\.text).joined(separator: " ") }
    fileprivate var isValid: Bool {
        !ids.isEmpty && !translation.isEmpty && pieces.count >= 2 &&
        pieces.allSatisfy { !$0.text.isEmpty && !$0.meaning.isEmpty }
    }
}

struct CourseDay: Decodable, Identifiable {
    static let dayRange = 1...100
    // Days 1–100 in existing stores belong to the original conversation course.
    static let recordOffset = 1000
    static let legacyRecords = 1001...1100
    static let plannedRecords = 2001...2100
    static let dailyStartRecords = 3001...3100
    var dailyStart: Bool?
    var starterExamples: [LessonPhrase]?
    var sourceUnit: Int?
    var plannedBasicIDs: [String]?
    var plannedFamilyIDs: [String]?
    var unitID: Int { sourceUnit ?? id }
    var recordID: Int {
        if dailyStart == true { return 3000 + unitID }
        return (plannedBasicIDs == nil ? Self.recordOffset : 2000) + unitID
    }
    var studyBasicIDs: [String] { plannedBasicIDs ?? basicIDs }
    var speakingMission: SpeakingMission { plannedBasicIDs == nil ? mission : beginnerMission ?? mission }
    var lastStep: Int { lessonIDs.count + 1 }
    var addedFamilyIDs: [String]?   // Derived on loading the first encounter with a family.
    var taughtFamilyIDs: [String] {
        if plannedBasicIDs != nil, let plannedFamilyIDs { return plannedFamilyIDs }
        return wordIDs + (addedFamilyIDs ?? [])
    }
    var lessonIDs: [String] { taughtFamilyIDs + studyBasicIDs }
    var originalLessonIDs: [String] { plannedBasicIDs == nil ? wordIDs + basicIDs : lessonIDs }

    func starterExample(for id: String) -> LessonPhrase? {
        starterExamples?.first { $0.ids.contains(id) }
    }

    // Pair neighboring words. Give an odd final word two companions in its own section.
    func studyGroup(at position: Int) -> ClosedRange<Int>? {
        let familyCount = taughtFamilyIDs.count
        let total = familyCount + studyBasicIDs.count
        guard position > 0, position <= total else { return nil }
        let section = position <= familyCount ? 1...familyCount : (familyCount + 1)...total
        if section.count >= 3, !section.count.isMultiple(of: 2), position >= section.upperBound - 2 {
            return (section.upperBound - 2)...section.upperBound
        }
        let first = section.lowerBound + (position - section.lowerBound) / 2 * 2
        return first...min(first + 1, section.upperBound)
    }

    // Previously saved steps keep their original meaning, including the recap.
    // Newly introduced family members use slots after the original recap.
    func storedStep(for position: Int) -> Int {
        if plannedBasicIDs != nil { return min(max(0, position), lastStep) }
        let added = addedFamilyIDs?.count ?? 0
        if position == 0 || position <= wordIDs.count { return position }
        if position == lastStep { return originalLessonIDs.count + 1 }
        if position <= taughtFamilyIDs.count {
            return originalLessonIDs.count + 1 + position - wordIDs.count
        }
        return position - added
    }

    func displayPosition(for step: Int) -> Int {
        if plannedBasicIDs != nil { return min(max(0, step), lastStep) }
        let originalEnd = originalLessonIDs.count + 1
        if step <= wordIDs.count { return max(0, step) }
        if step == originalEnd { return lastStep }
        if step > originalEnd { return min(taughtFamilyIDs.count, wordIDs.count + step - originalEnd) }
        return step + (addedFamilyIDs?.count ?? 0)
    }

    var id: Int
    let familyID: String
    let title: String
    let guide: String
    let wordIDs: [String]
    let basicIDs: [String]
    let legacyWordCount: Int
    let bridge: LessonBridge
    let mission: SpeakingMission
    let beginnerMission: SpeakingMission?
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
            && basicIDs.allSatisfy { lexicon.basicWords[$0] != nil } && mission.isValid && (beginnerMission?.isValid ?? true)
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
    var isValid: Bool {
        !goal.isEmpty && turns.count == 2 && turns.allSatisfy { turn in
            [turn.partner, turn.partnerZH, turn.reply, turn.replyZH].allSatisfy { !$0.isEmpty }
        }
    }

    struct Turn: Codable {
        let partner: String
        let partnerZH: String
        let reply: String
        let replyZH: String
    }
}
