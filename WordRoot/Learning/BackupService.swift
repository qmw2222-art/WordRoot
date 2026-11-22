import Foundation
import SwiftData

struct LearningSnapshot: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let reviewCards: [ReviewCardSnapshot]
    let attempts: [AttemptSnapshot]
    let courseDays: [CourseDaySnapshot]?
    var familyRounds: [FamilyRoundBackup]? = nil
    var familyCursors: [String: String]? = nil
}

struct FamilyRoundBackup: Codable {
    let key: String
    let payload: Data
}

struct CourseDaySnapshot: Codable {
    let day: Int
    let step: Int
    let updatedAt: Date
    let completedAt: Date?
    var studiedIDs: [String]? = nil
}

struct ReviewCardSnapshot: Codable {
    let id: String
    let senseID: String
    let abilityRawValue: String
    let isWeakCard: Bool
    let stateData: Data
    let updatedAt: Date
}

struct AttemptSnapshot: Codable {
    let id: UUID
    let reviewAttemptID: UUID
    let senseID: String
    let abilityRawValue: String
    let firstAnswer: String
    let normalizedAnswer: String
    let outcomeRawValue: String
    let usedAssistance: Bool
    let independentEvidence: Bool
    let wasShownAnswer: Bool
    let answeredAt: Date
    let timeZoneIdentifier: String
}

enum BackupError: Error {
    case unsupportedVersion
    case invalidSnapshot
}

@MainActor
enum BackupService {
    static let formatVersion = 7

    static func export(from context: ModelContext, defaults: UserDefaults = .standard) throws -> Data {
        let cards = try context.fetch(FetchDescriptor<ReviewCardRecord>()).map {
            ReviewCardSnapshot(
                id: $0.id,
                senseID: $0.senseID,
                abilityRawValue: $0.abilityRawValue,
                isWeakCard: $0.isWeakCard,
                stateData: $0.stateData,
                updatedAt: $0.updatedAt
            )
        }
        let attempts = try context.fetch(FetchDescriptor<LearningAttemptRecord>()).map {
            AttemptSnapshot(
                id: $0.id,
                reviewAttemptID: $0.reviewAttemptID,
                senseID: $0.senseID,
                abilityRawValue: $0.abilityRawValue,
                firstAnswer: $0.firstAnswer,
                normalizedAnswer: $0.normalizedAnswer,
                outcomeRawValue: $0.outcomeRawValue,
                usedAssistance: $0.usedAssistance,
                independentEvidence: $0.independentEvidence,
                wasShownAnswer: $0.wasShownAnswer,
                answeredAt: $0.answeredAt,
                timeZoneIdentifier: $0.timeZoneIdentifier
            )
        }
        let courseDays = try context.fetch(FetchDescriptor<CourseDayRecord>()).map {
            CourseDaySnapshot(day: $0.day, step: $0.step, updatedAt: $0.updatedAt, completedAt: $0.completedAt, studiedIDs: $0.studiedIDs)
        }
        let rounds = try context.fetch(FetchDescriptor<FamilyPracticeRecord>()).map { FamilyRoundBackup(key: $0.key, payload: $0.payload) }
        let cursors = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("wordroot.familyStudy.") }.compactMapValues { $0 as? String }
        return try JSONEncoder().encode(
            LearningSnapshot(
                formatVersion: formatVersion,
                exportedAt: .now,
                reviewCards: cards,
                attempts: attempts,
                courseDays: courseDays,
                familyRounds: rounds,
                familyCursors: cursors
            )
        )
    }

    static func validate(_ data: Data) throws -> LearningSnapshot {
        guard let snapshot = try? JSONDecoder().decode(LearningSnapshot.self, from: data) else {
            throw BackupError.invalidSnapshot
        }
        guard (1...formatVersion).contains(snapshot.formatVersion) else {
            throw BackupError.unsupportedVersion
        }
        let courseDays = snapshot.courseDays ?? []
        let course = (try? DailyCourse.bundled.get())?.preservingLegacyRecords(Set(courseDays.map(\.day)))
        guard Set(snapshot.reviewCards.map(\.id)).count == snapshot.reviewCards.count,
              Set(snapshot.attempts.map(\.id)).count == snapshot.attempts.count,
              snapshot.formatVersion == 1 || snapshot.courseDays != nil,
              Set(courseDays.map(\.day)).count == courseDays.count,
              courseDays.allSatisfy({
                  if CourseDay.dayRange.contains($0.day) { return (0...5).contains($0.step) }
                  guard snapshot.formatVersion >= 3, let unit = course?.day(forRecord: $0.day) else { return false }
                  if CourseDay.dailyStartRecords.contains($0.day), snapshot.formatVersion < 7 || $0.studiedIDs == nil {
                      return false
                  }
                  if CourseDay.plannedRecords.contains($0.day), snapshot.formatVersion < 6 || $0.studiedIDs == nil {
                      return false
                  }
                  if let ids = $0.studiedIDs {
                      return snapshot.formatVersion >= 4 && (0...unit.lastStep).contains($0.step)
                          && Set(ids).count == ids.count && Set(ids).isSubset(of: unit.lessonIDs)
                  }
                  return (0...(unit.legacyWordCount + 1)).contains($0.step)
              }) else {
            throw BackupError.invalidSnapshot
        }
        if let rounds = snapshot.familyRounds, !rounds.isEmpty {
            guard snapshot.formatVersion >= 5, Set(rounds.map(\.key)).count == rounds.count,
                  let lexicon = try? Lexicon.bundled.get(),
                  rounds.allSatisfy({ item in
                      guard let round = try? JSONDecoder().decode(FamilyPracticeProgress.self, from: item.payload) else { return false }
                      return round.isValid(for: item.key, in: lexicon)
                  }) else { throw BackupError.invalidSnapshot }
        }
        if let cursors = snapshot.familyCursors, !cursors.isEmpty {
            guard snapshot.formatVersion >= 5, let lexicon = try? Lexicon.bundled.get(),
                  cursors.allSatisfy({ key, cursor in
                      guard key.hasPrefix("wordroot.familyStudy."),
                            let family = lexicon.family(id: String(key.dropFirst("wordroot.familyStudy.".count))) else { return false }
                      return cursor.isEmpty || cursor == "finished" || family.words.contains { $0.id == cursor }
                  }) else { throw BackupError.invalidSnapshot }
        }
        return snapshot
    }

    static func restore(_ data: Data, into context: ModelContext, defaults: UserDefaults = .standard) throws {
        let snapshot = try validate(data)
        do {
            try replace(with: snapshot, context: context)
            try context.save()
            replaceFamilyCursors(with: snapshot.familyCursors ?? [:], defaults: defaults)
        } catch {
            context.rollback()
            throw error
        }
    }

    static func replaceFamilyCursors(with cursors: [String: String], defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("wordroot.familyStudy.") {
            defaults.removeObject(forKey: key)
        }
        for (key, cursor) in cursors { defaults.set(cursor, forKey: key) }
    }

    private static func replace(with snapshot: LearningSnapshot, context: ModelContext) throws {
        try context.fetch(FetchDescriptor<LearningAttemptRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ReviewCardRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CourseDayRecord>()).forEach(context.delete)

        try context.fetch(FetchDescriptor<FamilyPracticeRecord>()).forEach(context.delete)
        for item in snapshot.familyRounds ?? [] {
            context.insert(FamilyPracticeRecord(key: item.key, payload: item.payload))
        }
        for item in snapshot.reviewCards {
            guard let ability = LearningAbility(rawValue: item.abilityRawValue),
                  let state = try? JSONDecoder().decode(ReviewScheduleState.self, from: item.stateData) else {
                throw BackupError.invalidSnapshot
            }
            let record = try ReviewCardRecord(
                id: item.id,
                senseID: item.senseID,
                ability: ability,
                isWeakCard: item.isWeakCard,
                state: state
            )
            record.updatedAt = item.updatedAt
            context.insert(record)
        }
        for day in snapshot.courseDays ?? [] {
            let record = CourseDayRecord(day: day.day, step: day.step, updatedAt: day.updatedAt, completedAt: day.completedAt)
            record.studiedIDs = day.studiedIDs
            context.insert(record)
        }
        for item in snapshot.attempts {
            guard let ability = LearningAbility(rawValue: item.abilityRawValue) else {
                throw BackupError.invalidSnapshot
            }
            let record = LearningAttemptRecord(
                reviewAttemptID: item.reviewAttemptID,
                senseID: item.senseID,
                ability: ability,
                firstAnswer: item.firstAnswer,
                evaluation: AnswerEvaluation(
                    outcome: AnswerOutcome(rawValue: item.outcomeRawValue) ?? .needsReview,
                    normalizedAnswer: item.normalizedAnswer,
                    usedAssistance: item.usedAssistance,
                    isIndependentEvidence: item.independentEvidence
                ),
                wasShownAnswer: item.wasShownAnswer,
                answeredAt: item.answeredAt
            )
            record.id = item.id
            record.timeZoneIdentifier = item.timeZoneIdentifier
            record.independentEvidence = item.independentEvidence
            context.insert(record)
        }
    }
}

private extension AnswerOutcome {
    init?(rawValue: String) {
        switch rawValue {
        case "correct": self = .correct
        case "incorrect": self = .incorrect
        case "needsReview": self = .needsReview
        default: return nil
        }
    }
}
