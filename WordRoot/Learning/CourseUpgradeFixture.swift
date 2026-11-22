#if DEBUG
import Foundation
import SwiftData

/// Only called from the isolated UI-test container. Fixture records never enter the learner's database.
@MainActor
enum CourseUpgradeFixture {
    static func prepare(_ name: String, container: ModelContainer, defaults: UserDefaults) throws {
        let context = ModelContext(container)
        let course = try DailyCourse.bundled.get()
        guard try context.fetchCount(FetchDescriptor<CourseDayRecord>()) == 0 else { return }
        if name == "alias-backup" {
            try exerciseMigration(context: context, course: course, defaults: defaults)
            return
        }
        let parts = name.split(separator: "-")
        guard parts.count == 2, let number = Int(parts[1]), let day = course[number] else { throw BackupError.invalidSnapshot }
        let finished = ["finished", "yesterday", "replay"].contains(parts[0])
        let date = parts[0] == "yesterday" ? Calendar.current.date(byAdding: .day, value: -1, to: Date())! : Date()
        let row = CourseDayRecord(day: day.recordID, step: finished && parts[0] != "replay" ? day.storedStep(for: day.lastStep) : 0,
                                  updatedAt: date, completedAt: finished ? date : nil)
        row.studiedIDs = finished ? day.lessonIDs : []
        context.insert(row)
        if parts[0] == "yesterday", let first = day.taughtFamilyIDs.first {
            context.insert(LearningAttemptRecord(reviewAttemptID: UUID(), senseID: first, ability: .choiceRecognition,
                firstAnswer: "喝", evaluation: AnswerEvaluation(outcome: .correct, normalizedAnswer: "喝",
                usedAssistance: false, isIndependentEvidence: false), wasShownAnswer: false, answeredAt: date))
        }
        try context.save()
    }

    private static func exerciseMigration(context: ModelContext, course: DailyCourse, defaults: UserDefaults) throws {
        guard let wash = course[7] else { throw BackupError.invalidSnapshot }
        let now = Date()
        let uuids = [UUID(), UUID()]
        let ids = ["basic.wash", "wash.wash", "basic.form", "form.form.0"]
        var cards: [ReviewCardSnapshot] = []
        for (i, id) in ids.enumerated() {
            var schedule = ReviewScheduleState(now: now)
            schedule.card.due = now.addingTimeInterval(Double(i + 1) * -3600)
            schedule.lastAttemptID = uuids[i % 2]
            cards.append(ReviewCardSnapshot(id: id + ":" + LearningAbility.meaningRecall.rawValue, senseID: id, abilityRawValue: LearningAbility.meaningRecall.rawValue,
                                            isWeakCard: i == 0, stateData: try JSONEncoder().encode(schedule), updatedAt: now))
        }
        let attempts = uuids.enumerated().map { i, uuid in
            AttemptSnapshot(id: uuid, reviewAttemptID: UUID(), senseID: ids[i], abilityRawValue: LearningAbility.meaningRecall.rawValue,
                            firstAnswer: i == 0 ? "清洗" : "洗", normalizedAnswer: "洗", outcomeRawValue: "correct",
                            usedAssistance: false, independentEvidence: false, wasShownAnswer: false,
                            answeredAt: now.addingTimeInterval(Double(i)), timeZoneIdentifier: "Asia/Shanghai")
        }
        // Build 29 stored wash twice, then soap at position 5.
        let oldPosition = CourseDaySnapshot(day: wash.recordID, step: 5, updatedAt: now, completedAt: nil,
                                            studiedIDs: ["wash.wash", "wash.washer", "wash.dishwasher", "basic.wash"])
        let original = LearningSnapshot(formatVersion: 7, exportedAt: now, reviewCards: cards, attempts: attempts,
                                        courseDays: [oldPosition])
        let originalBytes = try JSONEncoder().encode(original)
        try BackupService.restore(originalBytes, into: context, defaults: defaults)
        let migrated = try BackupService.validate(BackupService.export(from: context, defaults: defaults))
        try BackupService.restore(try JSONEncoder().encode(migrated), into: context, defaults: defaults)
        let restored = try BackupService.validate(BackupService.export(from: context, defaults: defaults))
        let known = try Lexicon.bundled.get()
        let cook = course[6]!.words(in: known).filter { $0.word.lowercased() == "cook" }
        func rows(_ s: LearningSnapshot) -> [[String: Any]] {
            s.attempts.sorted { $0.answeredAt < $1.answeredAt }.map { row in
                ["id": row.id.uuidString, "reviewAttemptID": row.reviewAttemptID.uuidString,
                 "firstAnswer": row.firstAnswer, "assisted": row.usedAssistance, "answeredAt": row.answeredAt.timeIntervalSince1970]
            }
        }
        func schedule(_ card: ReviewCardSnapshot) throws -> ReviewScheduleState {
            try JSONDecoder().decode(ReviewScheduleState.self, from: card.stateData)
        }
        func object(_ state: ReviewScheduleState) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        }
        let before = try cards.prefix(2).map(schedule)
        let selected = before.min { $0.card.due < $1.card.due }!
        guard let after = migrated.reviewCards.first(where: { $0.senseID == "wash.wash" }),
              let roundTrip = restored.reviewCards.first(where: { $0.senseID == "wash.wash" }),
              let record = try context.fetch(FetchDescriptor<CourseDayRecord>()).first,
              let nextWord = wash.words(in: known).dropFirst(record.position(in: wash) - 1).first,
              let sourceBasic = wash.plannedBasicIDs?.dropFirst().first else { throw BackupError.invalidSnapshot }
        let output: [String: Any] = [
            "beforeDue": before.map { $0.card.due.timeIntervalSince1970 }, "afterDue": try schedule(after).card.due.timeIntervalSince1970,
            "roundTripDue": try schedule(roundTrip).card.due.timeIntervalSince1970, "afterCards": migrated.reviewCards.filter { $0.senseID.contains("wash") }.map(\.senseID),
            "roundTripCards": restored.reviewCards.filter { $0.senseID.contains("wash") }.map(\.senseID),
            "formCards": restored.reviewCards.filter { $0.senseID.contains("form") }.map(\.senseID),
            "cookSpellings": cook.map(\.word), "cookIDs": cook.map(\.id), "wasWeak": cards[0].isWeakCard, "isWeak": roundTrip.isWeakCard,
            "oldCurrent": sourceBasic, "restoredCurrent": nextWord.id, "beforeAttempts": rows(original),
            "afterAttempts": rows(migrated), "roundTripAttempts": rows(restored), "selectedSchedule": try object(selected),
            "restoredSchedule": try object(schedule(after)), "roundTripSchedule": try object(schedule(roundTrip))
        ]
        try JSONSerialization.data(withJSONObject: output).write(to: URL.temporaryDirectory.appendingPathComponent("native-migration.json"), options: .atomic)
    }
}
#endif
