import Foundation

struct WordReadingAid: Decodable {
    let sound: String
    let tip: String

    private static let all: [String: WordReadingAid] = {
        guard let file = Bundle.main.url(forResource: "word-reading-aids", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([String: Self].self, from: data) else { return [:] }
        return entries
    }()

    static func lookup(_ text: String, ipa: String?) -> Self? {
        guard let ipa else { return nil }
        return all[text + "|" + ipa]
    }
}
