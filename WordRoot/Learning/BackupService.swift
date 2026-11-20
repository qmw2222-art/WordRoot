import Foundation
import SwiftData

struct LearningSnapshot: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let reviewCards: [ReviewCardSnapshot]
    let attempts: [AttemptSnapshot]
    let courseDays: [CourseDaySnapshot]?
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
    static let formatVersion = 4

    static func export(from context: ModelContext) throws -> Data {
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
        return try JSONEncoder().encode(
            LearningSnapshot(
                formatVersion: formatVersion,
                exportedAt: .now,
                reviewCards: cards,
                attempts: attempts,
                courseDays: courseDays
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
        guard Set(snapshot.reviewCards.map(\.id)).count == snapshot.reviewCards.count,
              Set(snapshot.attempts.map(\.id)).count == snapshot.attempts.count,
              snapshot.formatVersion == 1 || snapshot.courseDays != nil,
              Set(courseDays.map(\.day)).count == courseDays.count,
              courseDays.allSatisfy({
                  if CourseDay.dayRange.contains($0.day) { return (0...5).contains($0.step) }
                  guard $0.day > CourseDay.recordOffset else { return false }
                  let day = $0.day - CourseDay.recordOffset
                  guard snapshot.formatVersion >= 3, CourseDay.dayRange.contains(day),
                        case .success(let course) = DailyCourse.bundled, let unit = course[day] else { return false }
                  if let ids = $0.studiedIDs {
                      return snapshot.formatVersion >= 4 && (0...unit.lastStep).contains($0.step)
                          && Set(ids).count == ids.count && Set(ids).isSubset(of: unit.lessonIDs)
                  }
                  return (0...(unit.legacyWordCount + 1)).contains($0.step)
              }) else {
            throw BackupError.invalidSnapshot
        }
        return snapshot
    }

    static func restore(_ data: Data, into context: ModelContext) throws {
        let snapshot = try validate(data)
        do {
            try replace(with: snapshot, context: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func replace(with snapshot: LearningSnapshot, context: ModelContext) throws {
        try context.fetch(FetchDescriptor<LearningAttemptRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ReviewCardRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<CourseDayRecord>()).forEach(context.delete)

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
