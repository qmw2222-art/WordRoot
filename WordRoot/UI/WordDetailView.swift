import AVFoundation
import SwiftUI

struct WordDetailView: View {
    @Environment(SpeechPlayer.self) private var speaker
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize = 47.0
    @State private var checking = false
    let word: Word
    let family: WordFamily
    let openWord: (Word) -> Void
    let returnToFamily: () -> Void
    let practice: () -> Void

    private var wordAudioID: String { word.id + ".word" }
    private var exampleAudioID: String { word.id + ".example" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                explanation
                example
                connections
                Divider().overlay(MapStyle.line)
                Button(action: practice) {
                    Label("用记忆卡练这个词", systemImage: "rectangle.stack")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(MapStyle.accent)
                .accessibilityIdentifier("word.practice")
                Button(action: returnToFamily) {
                    Label("回到 \(family.root) 词族地图", systemImage: "map")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(MapStyle.pine)
                .accessibilityIdentifier("word.returnToFamily")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 34)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(MapStyle.page.ignoresSafeArea())
        .toolbarBackground(MapStyle.page, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("\(family.root) 词族")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $checking) { WordSelfCheck(word: word) }
        .onDisappear {
            speaker.stop(id: wordAudioID)
            speaker.stop(id: exampleAudioID)
            if let id = speaker.activeID, id.hasPrefix(word.id + ".detail") { speaker.stop(id: id) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            headword
            WordPronunciationRow(word: word, prefix: "word", audioID: wordAudioID)
            Text(word.meaning)
                .font(.title3.weight(.semibold)).foregroundStyle(MapStyle.ink)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("word.meaning")
            Text("词性 · \(word.partOfSpeech)").font(.footnote).foregroundStyle(MapStyle.secondary)
            Text(word.formation)
                .font(.callout.weight(.semibold))
                .foregroundStyle(MapStyle.pine)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MapStyle.tintSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("word.formation")
        }
    }

    private var headword: some View {
        Text(word.word)
            .font(.system(size: titleSize, weight: .bold, design: .serif))
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(MapStyle.pine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("word.headword")
    }

    private var explanation: some View {
        MapPanel {
            VStack(alignment: .leading, spacing: 9) {
                MapSectionTitle(title: "怎么理解", symbol: "text.book.closed")
                if let parts = word.parts, let combined = word.combined {
                    WordPartsView(parts: parts, combined: combined, formation: word.formation,
                                  soundID: word.id + ".detail", prefix: "detail.parts")
                } else {
                    Text(word.plainCue ?? word.memoryCue)
                }
                Button("自查发音和词义") {
                    if let id = speaker.activeID { speaker.stop(id: id) }
                    checking = true
                }
                    .frame(minHeight: 44).accessibilityIdentifier("word.selfcheck")
                Text(word.explanation)
                    .foregroundStyle(MapStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("word.explanation")
                if let rootRelation = word.rootRelation {
                    Divider().overlay(MapStyle.line)
                    Text(rootRelation)
                        .font(.subheadline)
                        .foregroundStyle(MapStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("word.rootRelation")
                }
            }
        }
    }

    private var example: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                MapSectionTitle(title: "例句", symbol: "quote.opening")
                Spacer(minLength: 6)
                SpeechButton(
                    id: exampleAudioID, text: word.example,
                    label: "读例句", identifier: "word.audio.example"
                )
            }
            Text(highlightedExample)
                .font(.system(.title3, design: .serif, weight: .medium))
                .foregroundStyle(MapStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("word.example")
            Text(word.translation)
                .font(.callout)
                .foregroundStyle(MapStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("word.translation")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(MapStyle.tintSurface, in: RoundedRectangle(cornerRadius: 17))
    }

    private var highlightedExample: AttributedString {
        var text = AttributedString(word.example)
        if let target = word.targetRange, let range = Range(target, in: text) {
            text[range].font = .system(.title3, design: .serif, weight: .bold)
        }
        return text
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 11) {
            MapSectionTitle(title: "沿关联继续学", symbol: "point.3.connected.trianglepath.dotted")
            VStack(spacing: 9) {
                ForEach(family.neighbors(of: word)) { neighbor in
                    Button {
                        openWord(neighbor.word)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(MapStyle.branch).frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            connectionCard(neighbor)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("打开这个关联词")
                    .accessibilityIdentifier("related.\(neighbor.word.id)")
                }
            }
            .background(alignment: .leading) {
                Rectangle().fill(MapStyle.branch)
                    .frame(width: 1.5)
                    .padding(.vertical, 12)
                    .padding(.leading, 3.25)
                    .accessibilityHidden(true)
            }
        }
    }

    private func connectionCard(_ neighbor: WordFamily.Neighbor) -> some View {
        MapPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(neighbor.word.word)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(MapStyle.pine)
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                        .foregroundStyle(MapStyle.secondary)
                        .accessibilityHidden(true)
                }
                Text(neighbor.word.formation)
                    .font(.callout)
                    .foregroundStyle(MapStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(neighbor.link.kind) · \(neighbor.link.note)")
                    .font(.subheadline)
                    .foregroundStyle(MapStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SpeechButton: View {
    @Environment(SpeechPlayer.self) private var speaker
    @State private var unavailable = false
    let id: String
    var text = ""
    var dialogue: [String]? = nil
    var pronunciation: String? = nil
    let label: String
    let identifier: String
    var ink = MapStyle.pine

    private var playing: Bool { speaker.activeID == id }

    var body: some View {
        Button {
            if let dialogue {
                unavailable = !speaker.toggle(id: id, dialogue: dialogue)
            } else {
                unavailable = !speaker.toggle(id: id, text: text, pronunciation: pronunciation)
            }
        } label: {
            Label(playing ? "停止" : label, systemImage: playing ? "stop.circle.fill" : "speaker.wave.2.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 9)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "停止\(label)" : label)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(speaker.speakingID == id ? "朗读中" : "")
        .alert("暂时无法发音", isPresented: $unavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请再点一次播放。")
        }
    }
}
