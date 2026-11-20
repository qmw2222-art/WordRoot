import Foundation
import SwiftData

@Model
final class CourseDayRecord {
    @Attribute(.unique) var day: Int
    var step: Int
    var updatedAt: Date
    var completedAt: Date?
    // Nil identifies the pre-expansion course. The old row is projected without altering it on launch.
    var studiedIDs: [String]?

    func credited(in unit: CourseDay) -> Set<String> {
        if let studiedIDs { return Set(studiedIDs).intersection(unit.lessonIDs) }
        return completedAt == nil ? [] : Set(unit.wordIDs.prefix(unit.legacyWordCount))
    }

    func isFinished(in unit: CourseDay) -> Bool {
        completedAt != nil && credited(in: unit).isSuperset(of: unit.lessonIDs)
    }

    func position(in unit: CourseDay) -> Int {
        if studiedIDs == nil && (completedAt != nil || step > unit.legacyWordCount) {
            return min(unit.legacyWordCount + 1, unit.lastStep)
        }
        return min(max(0, step), unit.lastStep)
    }

    init(day: Int, step: Int = 0, updatedAt: Date = .now, completedAt: Date? = nil) {
        self.day = day
        self.step = step
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

@Model
final class ReviewCardRecord {
    @Attribute(.unique) var id: String
    var senseID: String
    var abilityRawValue: String
    var isWeakCard: Bool
    var stateData: Data
    var updatedAt: Date

    init(
        id: String,
        senseID: String,
        ability: LearningAbility,
        isWeakCard: Bool = false,
        state: ReviewScheduleState = ReviewScheduleState()
    ) throws {
        self.id = id
        self.senseID = senseID
        self.abilityRawValue = ability.rawValue
        self.isWeakCard = isWeakCard
        self.stateData = try JSONEncoder().encode(state)
        self.updatedAt = .now
    }

    var state: ReviewScheduleState? {
        try? JSONDecoder().decode(ReviewScheduleState.self, from: stateData)
    }

    var ability: LearningAbility? {
        LearningAbility(rawValue: abilityRawValue)
    }
}

@Model
final class LearningAttemptRecord {
    @Attribute(.unique) var id: UUID
    var reviewAttemptID: UUID
    var senseID: String
    var abilityRawValue: String
    var firstAnswer: String
    var normalizedAnswer: String
    var outcomeRawValue: String
    var usedAssistance: Bool
    var independentEvidence: Bool
    var wasShownAnswer: Bool
    var answeredAt: Date
    var timeZoneIdentifier: String

    init(
        reviewAttemptID: UUID,
        senseID: String,
        ability: LearningAbility,
        firstAnswer: String,
        evaluation: AnswerEvaluation,
        wasShownAnswer: Bool,
        answeredAt: Date = .now
    ) {
        self.id = UUID()
        self.reviewAttemptID = reviewAttemptID
        self.senseID = senseID
        self.abilityRawValue = ability.rawValue
        self.firstAnswer = firstAnswer
        self.normalizedAnswer = evaluation.normalizedAnswer
        self.outcomeRawValue = String(describing: evaluation.outcome)
        self.usedAssistance = evaluation.usedAssistance
        self.independentEvidence = evaluation.isIndependentEvidence && !wasShownAnswer
        self.wasShownAnswer = wasShownAnswer
        self.answeredAt = answeredAt
        self.timeZoneIdentifier = TimeZone.current.identifier
    }
}
