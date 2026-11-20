import Foundation
import FSRS

struct ReviewScheduleState: Codable, Equatable {
    var card: Card
    var algorithmVersion: String
    var lastAttemptID: UUID?

    init(now: Date = .now) {
        self.card = FSRSDefaults().createEmptyCard(now: now)
        self.algorithmVersion = "FSRS-6.0.0"
    }
}

enum ReviewScheduler {
    private static let scheduler = FSRS(parameters: FSRSParameters(
        w: FSRSDefaults.defaultWv6,
        enableFuzz: false,
        enableShortTerm: false
    ))

    static func schedule(
        state: ReviewScheduleState,
        grade: ReviewGrade,
        attemptID: UUID,
        now: Date = .now
    ) throws -> ReviewScheduleState {
        guard state.lastAttemptID != attemptID else { return state }
        let rating: Rating = grade == .again ? .again : .good
        let result = try scheduler.next(card: state.card, now: now, grade: rating)
        return ReviewScheduleState(
            card: result.card,
            algorithmVersion: "FSRS-6.0.0",
            lastAttemptID: attemptID
        )
    }

    static func dueQueue<T>(
        _ items: [(item: T, dueAt: Date, isWeak: Bool)],
        now: Date = .now,
        limit: Int
    ) -> [T] {
        guard limit > 0 else { return [] }
        return items.filter { $0.dueAt <= now }.sorted {
            if $0.isWeak != $1.isWeak { return !$0.isWeak }
            return $0.dueAt < $1.dueAt
        }.prefix(limit).map(\.item)
    }

    static func newItemAllowance(
        dailyBudgetSeconds: TimeInterval,
        estimatedDueReviewSeconds: TimeInterval,
        desiredNewItems: Int
    ) -> Int {
        guard desiredNewItems > 0, dailyBudgetSeconds > estimatedDueReviewSeconds else { return 0 }
        return desiredNewItems
    }
}

extension ReviewScheduleState {
    init(card: Card, algorithmVersion: String, lastAttemptID: UUID?) {
        self.card = card
        self.algorithmVersion = algorithmVersion
        self.lastAttemptID = lastAttemptID
    }
}
