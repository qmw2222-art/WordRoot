import Foundation
import SwiftData

enum CourseReview {
    static func seed(_ rawID: String, in context: ModelContext, now: Date = .now) throws -> ReviewCardRecord {
        let senseID = WordSense.canonical(rawID)
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

    static func mergeLegacySenses(in context: ModelContext) throws {
        for (alias, canonical) in WordSense.aliases {
            let legacy = try context.fetch(FetchDescriptor<ReviewCardRecord>(predicate: #Predicate { $0.senseID == alias }))
            for old in legacy {
                let key = canonical + ":" + old.abilityRawValue
                let matches = try context.fetch(FetchDescriptor<ReviewCardRecord>(predicate: #Predicate { $0.id == key }))
                if let current = matches.first {
                    let oldState = try JSONDecoder().decode(ReviewScheduleState.self, from: old.stateData)
                    let currentState = try JSONDecoder().decode(ReviewScheduleState.self, from: current.stateData)
                    if (oldState.card.due, -old.updatedAt.timeIntervalSince1970) <
                        (currentState.card.due, -current.updatedAt.timeIntervalSince1970) {
                        current.stateData = old.stateData
                    }
                    current.isWeakCard = old.isWeakCard || current.isWeakCard
                    current.updatedAt = max(old.updatedAt, current.updatedAt)
                    context.delete(old)
                } else {
                    old.id = key
                    old.senseID = canonical
                }
            }
            let attempts = try context.fetch(FetchDescriptor<LearningAttemptRecord>(predicate: #Predicate { $0.senseID == alias }))
            for row in attempts { row.senseID = canonical }
        }
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
