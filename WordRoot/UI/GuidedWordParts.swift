import SwiftUI

struct RootPronunciationRow: View {
    let family: WordFamily
    let prefix: String
    let soundID: String
    let ink: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !family.rootContext.isEmpty {
                Text("\(family.rootSpoken) · \(family.rootContext)").font(.footnote)
            }
            HStack(spacing: 4) {
                Text(verbatim: "/\(family.rootIPA)/").font(.system(.title3, design: .serif))
                    .accessibilityIdentifier(prefix + ".rootIPA")
                SpeechButton(id: soundID, text: family.rootSpoken, pronunciation: family.rootIPA,
                             label: "听 \(family.rootSpoken) 的读音", identifier: prefix + ".audio.root", ink: ink)
                    .labelStyle(.iconOnly)
            }
        }.foregroundStyle(ink)
    }
}

struct WordPartsView: View {
    @Environment(SpeechPlayer.self) private var speaker
    let parts: [WordPart]
    let combined: String
    let formation: String
    let soundID: String
    let prefix: String

    private func isCurrent(_ index: Int) -> Bool {
        if speaker.activeID == soundID + ".part.\(index)" { return true }
        guard speaker.activeID == soundID, let line = speaker.segmentIndex, line >= 2 else { return false }
        let partStart = 2 + index * 2
        return line == partStart || line == partStart + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(parts.map(\.text).joined(separator: "  +  ")).font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(MapStyle.pine).accessibilityLabel(formation).accessibilityIdentifier(prefix + ".formation")
            ForEach(parts.indices, id: \.self) { index in
                let part = parts[index]
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(part.text).font(.system(.headline, design: .serif))
                        Text(part.meaning).font(.subheadline)
                    }
                    Spacer(minLength: 4)
                    Text(verbatim: "/\(part.ipa)/").font(.system(.body, design: .serif))
                        .accessibilityIdentifier(prefix + ".partIPA.\(index)")
                    SpeechButton(id: soundID + ".part.\(index)", text: part.text, pronunciation: part.ipa,
                                 label: "听 \(part.text) 在这个词里的读音", identifier: prefix + ".partAudio.\(index)")
                        .labelStyle(.iconOnly)
                }
                .padding(.horizontal, 8)
                .foregroundStyle(MapStyle.pine)
                .background(isCurrent(index) ? MapStyle.tintSurface : .clear, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityValue(isCurrent(index) ? "正在讲这一段" : "")
                .accessibilityIdentifier(prefix + ".part.\(index)")
            }
            Text(combined).font(.body.weight(.medium)).padding(.top, 3)
                .accessibilityLabel(parts.map { "\($0.text)，\($0.meaning)" }.joined(separator: "。") + "。" + combined)
                .accessibilityIdentifier(prefix + ".coach.word")
        }
    }
}

struct SentenceInStudy: View {
    let text: String
    let translation: String
    let neighbors: [Word]
    let current: String?
    let soundID: String
    let open: (String) -> Void

    var body: some View {
        MapPanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(text).font(.system(.title3, design: .serif, weight: .medium))
                        .accessibilityIdentifier("course.context.line")
                    Spacer(minLength: 2)
                    SpeechButton(id: soundID, text: text, label: "听这句话", identifier: "course.context.audio")
                        .labelStyle(.iconOnly)
                }
                Text(translation).font(.subheadline).foregroundStyle(MapStyle.secondary)
                let others = neighbors.filter { $0.id != current }
                if !others.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 7) { wordLinks(others) }
                        VStack(alignment: .leading, spacing: 3) { wordLinks(others) }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func wordLinks(_ words: [Word]) -> some View {
        ForEach(words) { word in
            Button { open(word.id) } label: {
                HStack(spacing: 4) {
                    Text("\(word.exampleForm ?? word.word)（\(word.primaryMeaning)）").font(.system(.body, design: .serif, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.caption2)
                }.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 7).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                .accessibilityLabel("学 \(word.word)，\(word.primaryMeaning)")
                .accessibilityIdentifier("course.context." + word.id)
        }
    }
}
