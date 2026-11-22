import Foundation
import SwiftData

struct ListeningQuestion: Codable, Identifiable {
    let id: UUID
    let wordID: String
    let options: [String]
    let retryDate: Date?

    init(wordID: String, options: [String], retryDate: Date? = nil) {
        id = UUID()
        self.wordID = wordID
        self.options = options
        self.retryDate = retryDate
    }

    var audioID: String { "cards.listen." + id.uuidString }
}

struct FamilyPracticeProgress: Codable {
    let questions: [ListeningQuestion]
    let nextIndex: Int
    let missed: Set<String>
    let spelling: Bool

    var targetIDs: [String] {
        questions.filter { $0.retryDate == nil }.map(\.wordID)
    }

    static func key(familyID: String, targets: [String]) -> String {
        ([familyID] + targets.sorted()).joined(separator: "|")
    }

    func isValid(for key: String, in lexicon: Lexicon) -> Bool {
        let parts = key.components(separatedBy: "|")
        guard let familyID = parts.first, let family = lexicon.family(id: familyID) else { return false }
        let targets = targetIDs
        let repeated = questions.filter { $0.retryDate != nil }.map(\.wordID)
        let allowed = Set(family.words.map(\.id))
        return (1..<max(1, questions.count)).contains(nextIndex)
            && key == Self.key(familyID: familyID, targets: targets)
            && Set(targets).count == targets.count && Set(targets).isSubset(of: allowed)
            && Set(repeated) == missed && repeated.count == missed.count && missed.isSubset(of: targets)
            && Set(questions.map(\.id)).count == questions.count
            && questions.allSatisfy {
                (1...4).contains($0.options.count) && Set($0.options).count == $0.options.count
                    && $0.options.contains($0.wordID) && Set($0.options).isSubset(of: allowed)
            }
    }
}

@Model
final class FamilyPracticeRecord {
    @Attribute(.unique) var key: String
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }

    func progress(in lexicon: Lexicon) throws -> FamilyPracticeProgress? {
        let progress = try JSONDecoder().decode(FamilyPracticeProgress.self, from: payload)
        return progress.isValid(for: key, in: lexicon) ? progress : nil
    }

    static func fetch(_ key: String, in context: ModelContext) throws -> FamilyPracticeRecord? {
        var request = FetchDescriptor<FamilyPracticeRecord>(predicate: #Predicate { $0.key == key })
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
