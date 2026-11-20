import Foundation

enum GuideSpeech: Equatable {
    case mandarin(String)
    case english(String, pronunciation: String? = nil, pauseBefore: TimeInterval = 0)

    var pauseBefore: TimeInterval {
        if case let .english(_, _, pause) = self { return pause }
        return 0
    }
}

extension WordFamily {
    static let firstIntroduction = "有些词里藏着同一小块，叫作词根。先听这一块怎么读。"

    func openingSpeech(firstDay: Bool) -> [GuideSpeech] {
        let lead = firstDay ? Self.firstIntroduction
            : rootKind == "词根" ? "今天先听一个词根。" : "今天先听一个生活里常用的词。"
        return [.mandarin(lead), .english(rootSpoken, pronunciation: rootIPA), .mandarin(rootIntro)]
    }
}

extension Word {
    var primaryMeaning: String {
        meaning.components(separatedBy: "；").first ?? meaning
    }

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
        for part in parts {
            lines.append(.english(part.text, pronunciation: part.ipa, pauseBefore: 0.12))
            lines.append(.mandarin(part.meaning + "。"))
        }
        lines.append(.mandarin(combined))
        return lines
    }
}
