import Foundation

struct Lexicon {
    let families: [WordFamily]
    let unavailableFamilyCount: Int
    let basicWords: [String: Word]
    var familySenseIDs: Set<String> { Set(entriesByID.keys) }
    func word(id: String) -> Word? { entriesByID[id]?.word ?? basicWords[id] }
    private let familiesByID: [String: WordFamily]
    private let entriesByID: [String: Entry]

    struct Entry: Identifiable {
        let word: Word
        let family: WordFamily

        var id: String { word.id }
    }

    func family(id: String) -> WordFamily? { familiesByID[id] }
    func entry(id: String) -> Entry? { entriesByID[id] }

    func matchingFamilies(_ query: String) -> [WordFamily] {
        families.filter {
            $0.root.localizedStandardContains(query) || $0.meaning.localizedStandardContains(query)
        }
    }

    func matchingWords(_ query: String) -> [Entry] {
        let matching = families.flatMap { family in
            family.words.compactMap { word -> Entry? in
                guard [word.word, word.meaning].contains(where: { $0.localizedStandardContains(query) }) else {
                    return nil
                }
                return Entry(word: word, family: family)
            }
        }
        return matching.sorted { left, right in
            let leftRank = left.word.matchRank(query)
            let rightRank = right.word.matchRank(query)
            guard leftRank == rightRank else { return leftRank < rightRank }
            return left.word.word.localizedStandardCompare(right.word.word) == .orderedAscending
        }
    }

    func matchingStandaloneBasic(_ query: String) -> [Word] {
        basicWords.values.filter { word in
            entriesByID[word.id] == nil &&
            (word.word.localizedStandardContains(query) || word.meaning.localizedStandardContains(query))
        }.sorted { left, right in
            let a = left.matchRank(query), b = right.matchRank(query)
            return a == b ? left.word.localizedStandardCompare(right.word) == .orderedAscending : a < b
        }
    }

    static let bundled: Result<Self, Error> = Result { try load() }

    static func load(from bundle: Bundle = .main) throws -> Self {
        let resources = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        let familyFiles = resources.filter { $0.lastPathComponent.hasPrefix("family-") }
        let decoder = JSONDecoder()
        var families: [WordFamily] = []
        var familiesByID: [String: WordFamily] = [:]
        var entriesByID: [String: Entry] = [:]
        var unavailableFamilyCount = 0

        for file in familyFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let family = try? decoder.decode(WordFamily.self, from: Data(contentsOf: file)),
                  family.isValid,
                  familiesByID[family.id] == nil,
                  family.words.allSatisfy({ entriesByID[$0.id] == nil }) else {
                unavailableFamilyCount += 1
                continue
            }
            families.append(family)
            familiesByID[family.id] = family
            for word in family.words { entriesByID[word.id] = Entry(word: word, family: family) }
        }
        guard !families.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

        guard let basicURL = bundle.url(forResource: "basic-850", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let basic = try decoder.decode([Word].self, from: Data(contentsOf: basicURL))
        guard basic.count == 850, basic.allSatisfy(\.isValid),
              Set(basic.map(\.id)).count == basic.count,
              Set(basic.map { $0.word.lowercased() }).count == basic.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Self(
            families: families, unavailableFamilyCount: unavailableFamilyCount,
            basicWords: Dictionary(uniqueKeysWithValues: basic.map { ($0.id, $0) }),
            familiesByID: familiesByID, entriesByID: entriesByID
        )
    }
}

struct WordFamily: Decodable, Identifiable {
    let id: String
    let root: String
    let rootIPA: String
    let rootSpoken: String
    let rootContext: String
    let rootIntro: String
    let rootKind: String
    let meaning: String
    let explanation: String
    let words: [Word]
    let links: [WordLink]

    var mapWords: [Word] { Array(words.filter { $0.rootRelation?.isEmpty == false }.prefix(4)) }

    struct Neighbor: Identifiable {
        let word: Word
        let link: WordLink

        var id: String { word.id }
    }

    func neighbors(of word: Word) -> [Neighbor] {
        links.compactMap { link in
            guard let opposite = link.otherEnd(from: word.id),
                  let related = words.first(where: { $0.id == opposite }) else { return nil }
            return Neighbor(word: related, link: link)
        }
    }

    fileprivate var isValid: Bool {
        guard ![id, root, rootSpoken, rootIPA, rootIntro, rootKind, meaning, explanation].contains(where: \.isBlank),
              !mapWords.isEmpty else { return false }
        let wordIDs = Set(words.map(\.id))
        guard wordIDs.count == words.count,
              words.allSatisfy(\.isValid),
              links.allSatisfy({ wordIDs.contains($0.from) && wordIDs.contains($0.to) && $0.isValid }),
              Set(links.map(\.endpointPair)).count == links.count,
              words.allSatisfy({ !neighbors(of: $0).isEmpty }) else { return false }

        var reached = Set(mapWords.map(\.id))
        var frontier = Array(reached)
        while let wordID = frontier.popLast() {
            for link in links {
                if let neighbor = link.otherEnd(from: wordID), reached.insert(neighbor).inserted {
                    frontier.append(neighbor)
                }
            }
        }
        return reached == wordIDs
    }
}

struct Word: Decodable, Identifiable {
    let id: String
    let word: String
    let partOfSpeech: String
    let meaning: String
    let memoryCue: String
    let plainCue: String?
    let parts: [WordPart]?
    let combined: String?
    let relatedIDs: [String]?
    let formation: String
    let explanation: String
    let example: String
    let translation: String
    let rootRelation: String?
    let pronunciation: String?
    let exampleForm: String?
    let acceptedAnswers: [String]
    let otherMeanings: [String]?

    fileprivate var isValid: Bool {
        ![id, word, partOfSpeech, meaning, formation, explanation, example, translation].contains(where: \.isBlank)
            && !memoryCue.isBlank && pronunciation?.isBlank == false
            && !acceptedAnswers.isEmpty && !acceptedAnswers.contains(where: \.isBlank)
    }

    fileprivate func matchRank(_ query: String) -> Int {
        if word.localizedStandardCompare(query) == .orderedSame { return 0 }
        if word.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil {
            return 1
        }
        return 2
    }

    // Only use an example as a fill-in exercise when its target can be identified unambiguously.
    var targetRange: Range<String.Index>? {
        let lemma = NSRegularExpression.escapedPattern(for: word)
        let variants = [lemma, lemma + "(?:s|es|ed|ing)"]
        var forms = variants
        if word.hasSuffix("e") {
            forms.append(NSRegularExpression.escapedPattern(for: String(word.dropLast())) + "(?:ed|ing)")
        }
        if word.hasSuffix("y") {
            forms.append(NSRegularExpression.escapedPattern(for: String(word.dropLast())) + "(?:ies|ied)")
        }
        if let exampleForm {
            forms = [NSRegularExpression.escapedPattern(for: exampleForm)]
        }
        let pattern = "\\b(?:" + forms.joined(separator: "|") + ")\\b"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let matches = expression.matches(in: example, range: NSRange(example.startIndex..., in: example))
        guard matches.count == 1, let match = matches.first else { return nil }
        return Range(match.range, in: example)
    }
}

struct WordPart: Decodable {
    let text: String
    let meaning: String
    let ipa: String
}

struct WordLink: Decodable {
    let from: String
    let to: String
    let kind: String
    let note: String

    fileprivate var endpointPair: Set<String> { [from, to] }
    fileprivate var isValid: Bool { from != to && !kind.isBlank && !note.isBlank }

    fileprivate func otherEnd(from wordID: String) -> String? {
        if from == wordID { return to }
        if to == wordID { return from }
        return nil
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
