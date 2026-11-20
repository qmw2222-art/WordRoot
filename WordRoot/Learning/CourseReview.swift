import Foundation
import SwiftData

enum CourseReview {
    static func seed(_ senseID: String, in context: ModelContext, now: Date = .now) throws -> ReviewCardRecord {
        let key = senseID + ":" + LearningAbility.meaningRecall.rawValue
        var query = FetchDescriptor<ReviewCardRecord>(predicate: #Predicate { $0.id == key })
        query.fetchLimit = 1
        if let card = try context.fetch(query).first { return card }
        let card = try ReviewCardRecord(id: key, senseID: senseID, ability: .meaningRecall,
                                        state: ReviewScheduleState(now: now))
        card.updatedAt = now
        context.insert(card)
        return card
    }

    @discardableResult
    static func grade(_ senseID: String, as grade: ReviewGrade, attemptID: UUID,
                      in context: ModelContext, now: Date = .now) throws -> Date {
        let card = try seed(senseID, in: context, now: now)
        let before = try JSONDecoder().decode(ReviewScheduleState.self, from: card.stateData)
        if before.lastAttemptID == attemptID { return before.card.due }
        var scheduled = try ReviewScheduler.schedule(state: before, grade: grade, attemptID: attemptID, now: now)
        if grade == .again {
            scheduled.card.due = min(scheduled.card.due, now.addingTimeInterval(10 * 60))
        }
        card.stateData = try JSONEncoder().encode(scheduled)
        card.updatedAt = now
        card.isWeakCard = grade == .again
        return scheduled.card.due
    }
}
