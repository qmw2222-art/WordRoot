import Foundation

enum LearningAbility: String, Codable, CaseIterable, Identifiable {
    case choiceRecognition = "choice_recognition"
    case pronunciationSelfCheck = "pronunciation_self_check"
    case meaningRecall = "meaning_recall"
    case audioMeaning = "audio_meaning"
    case contextCuedProduction = "context_cued_production"

    var id: String { rawValue }
}

enum AnswerOutcome: Equatable {
    case correct
    case incorrect
    case needsReview
}

enum ReviewGrade: String, Codable {
    case again
    case good
}

enum AttemptValidity {
    case completed
    case cancelled
    case technicalFailure
}

struct AnswerEvaluation {
    let outcome: AnswerOutcome
    let normalizedAnswer: String
    let usedAssistance: Bool
    let isIndependentEvidence: Bool
}

enum AnswerEvaluator {
    static func evaluate(
        answer: String,
        acceptedAnswers: Set<String>,
        usedAssistance: Bool,
        wasShownAnswer: Bool,
        requiresExactForm: Bool = false
    ) -> AnswerEvaluation {
        let normalized = normalize(answer)
        guard !normalized.isEmpty else {
            return AnswerEvaluation(
                outcome: .needsReview,
                normalizedAnswer: normalized,
                usedAssistance: usedAssistance,
                isIndependentEvidence: false
            )
        }

        let accepted = Set(acceptedAnswers.map(normalize))
        let correct = accepted.contains(normalized)
        return AnswerEvaluation(
            outcome: correct ? .correct : .needsReview,
            normalizedAnswer: normalized,
            usedAssistance: usedAssistance,
            isIndependentEvidence: correct && !usedAssistance && !wasShownAnswer
        )
    }

    static func grade(for evaluation: AnswerEvaluation) -> ReviewGrade {
        evaluation.outcome == .correct && !evaluation.usedAssistance ? .good : .again
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: #"[.!?,;:。！？，；：]+$"#, with: "", options: .regularExpression)
    }
}

struct MemoryEvidence {
    let ability: LearningAbility
    let firstAnswer: String
    let evaluation: AnswerEvaluation
    let answeredAt: Date
    let intervalSincePriorExposure: TimeInterval?
}

enum MasteryStatus: Equatable {
    case encountered
    case practicing
    case independentlyRecallable
    case delayedVerified
    case needsConsolidation
}

enum MasteryStatusEvaluator {
    static func status(for evidence: [MemoryEvidence], now: Date = .now) -> MasteryStatus {
        guard !evidence.isEmpty else { return .encountered }
        if evidence.contains(where: { $0.evaluation.outcome == .incorrect }) {
            return .needsConsolidation
        }
        let independent = evidence
            .filter { $0.evaluation.isIndependentEvidence }
            .sorted { $0.answeredAt < $1.answeredAt }
        guard let last = independent.last else { return .practicing }
        if let interval = last.intervalSincePriorExposure, interval >= 7 * 24 * 60 * 60 {
            return .delayedVerified
        }
        if independent.count >= 2,
           let first = independent.first,
           last.answeredAt.timeIntervalSince(first.answeredAt) >= 24 * 60 * 60 {
            return .independentlyRecallable
        }
        return .practicing
    }
}
