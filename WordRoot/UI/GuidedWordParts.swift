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
    let word: Word
    let parts: [WordPart]
    let combined: String
    let formation: String
    let soundID: String
    let prefix: String

    private func isCurrent(_ index: Int) -> Bool {
        if speaker.activeID == soundID + ".part.\(index)" {
            return speaker.segmentIndex == 1 || speaker.highlightedPart == index
        }
        guard speaker.activeID == soundID, let line = speaker.segmentIndex, line >= 2 else { return false }
        let partStart = 2 + index * 2
        return line == partStart || line == partStart + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(parts.map(\.text).joined(separator: "  +  ")).font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(MapStyle.pine).accessibilityLabel(formation).accessibilityIdentifier(prefix + ".formation")
            Text("点喇叭，先听整词，再听亮起的部分。")
                .font(.caption).foregroundStyle(MapStyle.secondary)
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
                    SpeechButton(id: soundID + ".part.\(index)", wordPart: (word.id, index),
                                 label: "听 \(part.text) 在 \(word.word) 里的读音", identifier: prefix + ".partAudio.\(index)")
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
    var pieces: [LessonPhrase.Piece] = []
    @State private var showingPieces = false

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
                if !pieces.isEmpty {
                    Button { showingPieces.toggle() } label: {
                        Label("逐段看意思", systemImage: showingPieces ? "chevron.up" : "chevron.down")
                            .font(.subheadline).frame(minHeight: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                    .accessibilityIdentifier("course.context.pieces")
                    .accessibilityValue(showingPieces ? "已展开" : "已收起")
                    if showingPieces {
                        ForEach(pieces.indices, id: \.self) { index in
                            let piece = pieces[index]
                            Text(piece.text.trimmingCharacters(in: CharacterSet(charactersIn: ".,?!")) + " · " + piece.meaning)
                                .font(.subheadline).accessibilityIdentifier("course.context.piece.\(index)")
                        }
                    }
                }
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

    private func formInSentence(_ word: Word) -> String {
        guard let form = word.exampleForm else { return word.word }
        let tokens = text.lowercased().split { !$0.isLetter }
        return tokens.contains(Substring(form.lowercased())) ? form : word.word
    }

    @ViewBuilder private func wordLinks(_ words: [Word]) -> some View {
        ForEach(words) { word in
            Button { open(word.id) } label: {
                HStack(spacing: 4) {
                    Text("\(formInSentence(word))（\(word.primaryMeaning)）").font(.system(.body, design: .serif, weight: .semibold))
                    Image(systemName: "arrow.up.right").font(.caption2)
                }.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 7).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(MapStyle.pine)
                .accessibilityLabel("学 \(word.word)，\(word.primaryMeaning)")
                .accessibilityIdentifier("course.context." + word.id)
        }
    }
}

struct LessonRootReminder: View {
    let family: WordFamily
    let prefix: String
    let soundID: String

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(family.rootKind == "词根" ? "本课词根" : "本课熟词").font(.subheadline)
                    Text(family.root).font(.system(.headline, design: .serif)).accessibilityIdentifier(prefix + ".reminder.root")
                    Text(family.meaning).font(.subheadline.weight(.medium)).accessibilityIdentifier(prefix + ".reminder.meaning")
                }
                if !family.rootContext.isEmpty {
                    Text("\(family.rootContext)读 \(family.rootSpoken)").font(.caption).foregroundStyle(MapStyle.secondary)
                }
            }
            Spacer(minLength: 3)
            HStack(spacing: 0) {
                Text(verbatim: "/\(family.rootIPA)/").font(.system(.callout, design: .serif))
                SpeechButton(id: soundID, text: family.rootSpoken, pronunciation: family.rootIPA,
                             label: "听 \(family.rootSpoken) 的教学示范", identifier: prefix + ".reminder.audio")
                    .labelStyle(.iconOnly)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 2).frame(maxWidth: 620)
        .frame(maxWidth: .infinity).background(MapStyle.tintSurface).foregroundStyle(MapStyle.pine)
    }
}

