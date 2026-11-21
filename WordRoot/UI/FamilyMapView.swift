import SwiftUI
import UIKit

struct FamilyMapView: View {
    @Environment(SubscriptionService.self) private var subscription
    @AppStorage("wordroot.currentFamily") private var familyID = "family.port"
    @AppStorage("wordroot.lastReadWord") private var lastReadWord = ""
    @FocusState private var searchFocused: Bool
    @State private var path: [Route] = []
    @State private var query = ""
    @State private var showingDirectory = false
    let lexicon: Lexicon
    let course: DailyCourse?
    @Binding var requestedWord: String?

    private enum Route: Hashable {
        case word(String)
        case practice(String)
        case familyStudy(String)
    }

    private var family: WordFamily { lexicon.family(id: familyID) ?? lexicon.families[0] }
    private var orderedFamilies: [WordFamily] {
        lexicon.families.sorted {
            (course?.firstDayByFamily[$0.id] ?? Int.max, $0.root) <
            (course?.firstDayByFamily[$1.id] ?? Int.max, $1.root)
        }
    }
    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header.id("map-top")
                        searchBar
                        if !searchTerm.isEmpty {
                            searchResults
                        } else {
                            mapContent
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: familyID) { _, _ in scroll.scrollTo("map-top", anchor: .top) }
            }
            .background(MapStyle.page.ignoresSafeArea())
            .navigationTitle("词根地图")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .word(let id):
                    MembershipGate(free: course?.isFree(wordID: id) == true, context: "学习这个词和它的用法") {
                        if let entry = lexicon.entry(id: id) {
                            WordDetailView(
                                word: entry.word,
                                family: entry.family,
                                openWord: { openWord($0) },
                                returnToFamily: { selectFamily(entry.family) },
                                practice: { path.append(.practice(id)) }
                            )
                            .task {
                                lastReadWord = id
                                familyID = entry.family.id
                            }
                        }
                        else if let basic = lexicon.basicWords[id] {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    StudyCard(word: basic, prefix: "word", soundID: "map.word." + id)
                                    Button("用记忆卡练这个词") { path.append(.practice(id)) }
                                        .buttonStyle(.bordered).accessibilityIdentifier("word.practice")
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                            }.navigationTitle(basic.word).navigationBarTitleDisplayMode(.inline)
                                .toolbar(.visible, for: .navigationBar).background(MapStyle.page.ignoresSafeArea())
                        }
                    }
                case .practice(let id):
                    MembershipGate(free: course?.isFree(wordID: id) == true, context: "练习这个词的听音卡") {
                        if let word = lexicon.word(id: id) { MemoryCardsView(words: [word], lexicon: lexicon) }
                    }
                case .familyStudy(let familyID):
                    if let selected = lexicon.family(id: familyID) {
                        MembershipGate(free: course?.isFree(familyID: familyID) == true, context: "学习 \(selected.root) 词族") {
                            FamilyStudyView(family: selected, lexicon: lexicon)
                        }
                    }
                }
            }
        }
        .onChange(of: requestedWord, initial: true) { _, id in
            guard let id, let word = lexicon.word(id: id) else { return }
            requestedWord = nil
            path.removeAll()
            if let entry = lexicon.entry(id: id) { selectFamily(entry.family) }
            openWord(word)
        }
        .sheet(isPresented: $showingDirectory) {
            NavigationStack {
                FamilyDirectory(families: orderedFamilies, isLocked: { !canOpen($0) }) { next in
                    showingDirectory = false
                    selectFamily(next)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { showingDirectory = false }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("词根地图")
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(MapStyle.pine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("map.title")
                Text("从一个词根出发，沿关联继续学。")
                    .font(.subheadline)
                    .foregroundStyle(MapStyle.secondary)
            }
            Spacer(minLength: 0)
            Button {
                searchFocused = false
                showingDirectory = true
            } label: {
                Image(systemName: "books.vertical")
                    .font(.title3)
                    .frame(width: 48, height: 48)
                    .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                    .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(MapStyle.line) }
            }
            .buttonStyle(.plain)
            .foregroundStyle(MapStyle.pine)
            .accessibilityLabel("查看全部词根")
            .accessibilityIdentifier("map.directory")
        }
    }

    private var searchBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(MapStyle.pine)
                .accessibilityHidden(true)
            TextField("搜索英文、中文或词根", text: $query)
                .foregroundStyle(MapStyle.ink)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
                .accessibilityIdentifier("map.search")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MapStyle.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, query.isEmpty ? 14 : 4)
        .frame(minHeight: 49)
        .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(MapStyle.line) }
    }

    private var mapContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            familyPicker
            if canOpen(family) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(family.root) · \(family.meaning)").font(.headline).foregroundStyle(MapStyle.pine)
                    WordOverviewGrid(words: family.words, prefix: "catalog.") { openWord($0) }
                }
                NavigationLink(value: Route.familyStudy(family.id)) {
                    Label("从头到尾学 \(family.words.count) 个用法", systemImage: "book").frame(minHeight: 44)
                }.accessibilityIdentifier("map.family.all")
                FamilyDiagram(family: family, openWord: { openWord($0) })
            } else {
                MapPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(family.root).font(.system(.title, design: .serif, weight: .bold))
                        Text(family.meaning)
                        Button("开通后学习这个词族", systemImage: "lock") { path.append(.familyStudy(family.id)) }
                            .accessibilityIdentifier("map.membership")
                            .buttonStyle(.borderedProminent)
                    }
                }
            }

            MapPanel {
                VStack(alignment: .leading, spacing: 9) {
                    MapSectionTitle(title: "词根讲解", symbol: "book")
                    Text(family.explanation)
                        .font(.callout)
                        .foregroundStyle(MapStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let entry = lexicon.entry(id: lastReadWord), canOpen(entry.family) {
                Button {
                    openWord(entry.word)
                } label: {
                    MapListRow(title: "继续学 \(entry.word.word)", subtitle: entry.family.root, symbol: "bookmark")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("map.resume")
            }

            if lexicon.unavailableFamilyCount > 0 {
                Text("有 \(lexicon.unavailableFamilyCount) 个词族暂时无法载入。")
                    .font(.footnote)
                    .foregroundStyle(MapStyle.secondary)
            }
        }
    }

    private var familyPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(orderedFamilies) { candidate in
                    let isCurrent = candidate.id == family.id
                    Button {
                        selectFamily(candidate)
                    } label: {
                        HStack(spacing: 5) {
                            Text(candidate.root).font(.system(.callout, design: .serif, weight: .semibold))
                            if !canOpen(candidate) {
                                Image(systemName: "lock.fill").font(.caption2).accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(isCurrent ? MapStyle.onAccent : MapStyle.pine)
                        .padding(.horizontal, 15)
                        .frame(minHeight: 44)
                        .background(isCurrent ? MapStyle.accent : MapStyle.tintSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .accessibilityHint(canOpen(candidate) ? "显示词族地图" : "需要订阅")
                    .accessibilityIdentifier(candidate.id)
                }
            }
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("切换词根")
    }

    private var searchResults: some View {
        let families = lexicon.matchingFamilies(searchTerm)
        let entries = lexicon.matchingWords(searchTerm)
        let basic = lexicon.matchingStandaloneBasic(searchTerm)
        return LazyVStack(alignment: .leading, spacing: 9) {
            if families.isEmpty && entries.isEmpty && basic.isEmpty {
                ContentUnavailableView.search(text: searchTerm)
                    .accessibilityIdentifier("search.empty")
            }
            if let first = basic.first, first.word.localizedStandardCompare(searchTerm) == .orderedSame {
                basicSearchRow(first)
            }
            if !families.isEmpty {
                Text("词根").font(.headline).foregroundStyle(MapStyle.pine).accessibilityAddTraits(.isHeader)
                ForEach(families) { candidate in
                    Button {
                        selectFamily(candidate)
                    } label: {
                        MapListRow(title: candidate.root, subtitle: candidate.meaning,
                                   symbol: canOpen(candidate) ? nil : "lock")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("search.\(candidate.id)")
                }
            }
            if !entries.isEmpty {
                Text("单词").font(.headline).foregroundStyle(MapStyle.pine).accessibilityAddTraits(.isHeader)
                ForEach(entries) { entry in
                    wordRow(entry.word, in: entry.family, identifierPrefix: "search.")
                }
            }
            ForEach(basic.filter { $0.word.localizedStandardCompare(searchTerm) != .orderedSame }) { basicSearchRow($0) }
        }
    }

    private func basicSearchRow(_ word: Word) -> some View {
        Button {
            searchFocused = false
            path.append(.word(word.id))
        } label: {
            MapListRow(title: word.word, subtitle: word.meaning, symbol: subscription.hasAccess || course?.isFree(wordID: word.id) == true ? nil : "lock")
        }.buttonStyle(.plain).accessibilityIdentifier("search." + word.id)
    }

    private func wordRow(_ word: Word, in family: WordFamily, identifierPrefix: String) -> some View {
        Button {
            openWord(word)
        } label: {
            MapListRow(title: word.word, subtitle: word.formation,
                       symbol: canOpen(family) ? nil : "lock")
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifierPrefix + word.id)
    }

    private func canOpen(_ family: WordFamily) -> Bool {
        subscription.hasAccess || course?.isFree(familyID: family.id) == true
    }

    private func openWord(_ word: Word) {
        searchFocused = false
        path.append(.word(word.id))
    }

    private func selectFamily(_ family: WordFamily) {
        searchFocused = false
        familyID = family.id
        query = ""
        path.removeAll()
    }
}

private struct FamilyDiagram: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let family: WordFamily
    let openWord: (Word) -> Void

    private var leading: [Word] { Array(family.mapWords.prefix((family.mapWords.count + 1) / 2)) }
    private var trailing: [Word] { Array(family.mapWords.dropFirst(leading.count)) }

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                rootNode
                ForEach(family.mapWords) { word in branch(word) }
            }
        } else {
            VStack(spacing: 0) {
                row(leading)
                ConnectorStem(count: leading.count, fromRoot: false)
                rootNode
                if !trailing.isEmpty {
                    ConnectorStem(count: trailing.count, fromRoot: true)
                    row(trailing)
                }
            }
        }
    }

    private var rootNode: some View {
        VStack(spacing: 3) {
            Text(family.root).font(.system(.largeTitle, design: .serif, weight: .bold))
            Text(family.meaning).font(.subheadline.weight(.medium))
            RootPronunciationRow(family: family, prefix: "map", soundID: "map.root." + family.id, ink: MapStyle.onAccent)
        }
        .foregroundStyle(MapStyle.onAccent)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .frame(minWidth: 153)
        .background(MapStyle.accent, in: RoundedRectangle(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).strokeBorder(MapStyle.branch, lineWidth: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.root")
    }

    private func row(_ words: [Word]) -> some View {
        HStack(alignment: .bottom, spacing: 13) {
            ForEach(words) { word in branch(word) }
        }
    }

    private func branch(_ word: Word) -> some View {
        Button {
            openWord(word)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(word.word)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(MapStyle.pine)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.caption2.weight(.semibold))
                        .foregroundStyle(MapStyle.secondary)
                        .accessibilityHidden(true)
                }
                Text(word.formation).font(.footnote)
                    .foregroundStyle(MapStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 77, alignment: .leading)
            .contentShape(Rectangle())
            .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(MapStyle.line) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(word.word)，\(word.formation)")
        .accessibilityHint("查看读音、例句和关联词")
        .accessibilityIdentifier("branch.\(word.id)")
    }
}

private struct ConnectorStem: View {
    let count: Int
    let fromRoot: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let leaves: [CGFloat] = count == 2 ? [width * 0.25, width * 0.75] : [width * 0.5]
            let spread: CGFloat = count == 2 ? min(44, width * 0.13) : 0

            Path { path in
                for leaf in leaves {
                    let root = width * 0.5 + (leaf < width * 0.5 ? -spread : spread)
                    let leafY = fromRoot ? height : 0
                    let rootY = fromRoot ? 0 : height
                    path.move(to: CGPoint(x: leaf, y: leafY))
                    path.addCurve(to: CGPoint(x: root, y: rootY),
                                  control1: CGPoint(x: leaf, y: height * 0.5),
                                  control2: CGPoint(x: root, y: height * 0.5))
                }
            }
            .stroke(MapStyle.branch, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            ForEach(leaves, id: \.self) { leaf in
                Circle().fill(MapStyle.branch)
                    .frame(width: 7, height: 7)
                    .position(x: leaf, y: fromRoot ? height - 3 : 3)
            }
        }
        .frame(height: 25)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct FamilyDirectory: View {
    @State private var query = ""
    let families: [WordFamily]
    let isLocked: (WordFamily) -> Bool
    let select: (WordFamily) -> Void

    private var results: [WordFamily] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return families.filter { term.isEmpty || $0.root.localizedStandardContains(term) || $0.meaning.localizedStandardContains(term) }
    }

    var body: some View {
        List(results) { family in
            Button {
                select(family)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family.root).font(.system(.headline, design: .serif))
                        Text(family.meaning).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isLocked(family) {
                        Image(systemName: "lock").accessibilityLabel("需要订阅")
                    }
                    Text("\(family.words.count) 词条").font(.footnote).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("directory.\(family.id)")
        }
        .overlay {
            if results.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .navigationTitle("全部词根")
        .searchable(text: $query, prompt: "找词根或中文含义")
    }
}

struct MapPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .contentShape(Rectangle())
            .background(MapStyle.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).strokeBorder(MapStyle.line) }
    }
}

struct MapSectionTitle: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(MapStyle.pine)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct MapListRow: View {
    let title: String
    let subtitle: String
    let symbol: String?

    var body: some View {
        MapPanel {
            HStack(spacing: 12) {
                if let symbol { Image(systemName: symbol).foregroundStyle(MapStyle.pine) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.headline, design: .serif)).foregroundStyle(MapStyle.pine)
                    Text(subtitle).font(.subheadline).foregroundStyle(MapStyle.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(MapStyle.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

enum MapStyle {
    static let page = adaptive(0xF6F3EA, 0x191F1A)
    static let surface = adaptive(0xFFFCF3, 0x242A22)
    static let tintSurface = adaptive(0xE9ECD9, 0x2D3C2F)
    static let pine = adaptive(0x173C2C, 0xD6E6CE)
    static let accent = adaptive(0x214B38, 0xA9C7A3)
    static let onAccent = adaptive(0xFFFDF3, 0x18271B)
    static let ink = adaptive(0x222921, 0xF3F2E9)
    static let secondary = adaptive(0x505A4C, 0xCBD3C7)
    static let branch = adaptive(0x6F8551, 0x91A87A)
    static let line = adaptive(0xD9D6C6, 0x4D584C)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
