import Foundation

enum GuideSpeech: Equatable {
    case mandarin(String)
    case english(String, pronunciation: String? = nil, pauseBefore: TimeInterval = 0)

    case wordPart(wordID: String, index: Int)

    var pauseBefore: TimeInterval {
        if case .wordPart = self { return 0.12 }
        if case let .english(_, _, pause) = self { return pause }
        return 0
    }
}

extension WordFamily {
    static let firstIntroduction = "几个词里意思相通的小块，叫作词根。先听它，再学第一个词。"

    func openingSpeech(firstDay: Bool, mnemonic: String? = nil) -> [GuideSpeech] {
        let lead = firstDay ? Self.firstIntroduction
            : rootKind == "词根" ? "今天先听一个词根。" : "今天先听一个生活里常用的词。"
        return [.mandarin(lead), .english(rootSpoken, pronunciation: rootIPA), .mandarin(mnemonic ?? rootIntro)]
    }
}

extension Word {
    var primaryMeaning: String {
        meaning.components(separatedBy: "；").first ?? meaning
    }

    var studyLabel: String { "\(word)（\(primaryMeaning)）" }

    var studyNarration: [GuideSpeech] {
        var lines: [GuideSpeech] = [.english(word, pronunciation: pronunciation)]
        let cue = plainCue ?? memoryCue
        if parts == nil && cue.hasPrefix("「" + primaryMeaning + "」") {
            return lines + [.mandarin(cue)]
        }
        lines.append(.mandarin("意思是" + primaryMeaning + "。"))
        guard let parts, !parts.isEmpty, let combined else {
            if cue != primaryMeaning && cue != primaryMeaning + "。" { lines.append(.mandarin(cue)) }
            return lines
        }
        for (index, part) in parts.enumerated() {
            lines.append(.wordPart(wordID: id, index: index))
            lines.append(.mandarin(part.meaning + "。"))
        }
        lines.append(.mandarin(combined))
        return lines
    }
}
