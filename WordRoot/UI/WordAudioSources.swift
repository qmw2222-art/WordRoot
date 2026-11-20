import SwiftUI

struct WordAudioSources: View {
    struct Credit: Decodable, Identifiable {
        let word, ipa, title, author, license, licenseURL, source: String
        var id: String { word + "|" + ipa }
    }
    private static let credits: [Credit] = {
        guard let url = Bundle.main.url(forResource: "word-audio-credits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Credit].self, from: data) else { return [] }
        return list
    }()
    @State private var search = ""

    var body: some View {
        List {
            Text("这些美式真人录音由维基词典收录，已在本机保存，并做了去除首尾静音、音量调整和 MP3 转码。其余词使用 Heart 美式教学发音。")
            ForEach(Self.credits.filter { search.isEmpty || $0.word.localizedCaseInsensitiveContains(search) }) { credit in
                VStack(alignment: .leading, spacing: 4) {
                    Text(credit.word + " /" + credit.ipa + "/").font(.headline)
                    Text(credit.author + " · " + credit.license)
                    Text(verbatim: credit.title).font(.caption)
                    Text(verbatim: credit.source).font(.caption).textSelection(.enabled)
                    if !credit.licenseURL.isEmpty {
                        Text(verbatim: credit.licenseURL).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "查找单词")
        .navigationTitle("整词录音来源")
    }
}
