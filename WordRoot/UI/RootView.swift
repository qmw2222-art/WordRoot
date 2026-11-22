import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SubscriptionService.self) private var subscription
    @State private var speaker = SpeechPlayer()
    @Environment(\.modelContext) private var context
    @State private var migrationFailed = false
    @State private var tab: Tab = .course
    @State private var requestedWord: String?
    @Query private var courseRecords: [CourseDayRecord]

    let studyDefaults: UserDefaults

    private func mergeEarlierRecords() {
        do {
            try CourseReview.mergeLegacySenses(in: context)
            if context.hasChanges { try context.save() }
        } catch {
            context.rollback()
            migrationFailed = true
        }
    }

    private enum Tab: Hashable {
        case course, map, history, settings
    }

    var body: some View {
        switch Lexicon.bundled {
        case .success(let lexicon):
            let course = (try? DailyCourse.bundled.get())?.preservingLegacyRecords(Set(courseRecords.map(\.day)))
            TabView(selection: $tab) {
                Group {
                    if let course {
                        CourseView(course: course, lexicon: lexicon, studyDefaults: studyDefaults) { id in
                            requestedWord = id
                            tab = .map
                        }
                    } else {
                        ContentUnavailableView("无法载入课程", systemImage: "book",
                                               description: Text("应用内的课程文件缺失或损坏。"))
                    }
                }
                .tabItem { Label("课程", systemImage: "book") }
                .tag(Tab.course)
                FamilyMapView(lexicon: lexicon, course: course, requestedWord: $requestedWord)
                    .tabItem { Label("地图", systemImage: "map") }
                    .tag(Tab.map)
                HistoryView(lexicon: lexicon, course: course)
                    .tabItem { Label("记录", systemImage: "chart.bar.xaxis") }
                    .tag(Tab.history)
                NavigationStack { DataSettingsView(studyDefaults: studyDefaults) }
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .environment(speaker)
            .task { mergeEarlierRecords() }
            .alert("旧版复习记录暂未整理完成", isPresented: $migrationFailed) {
                Button("重试") { mergeEarlierRecords() }
                Button("稍后再试", role: .cancel) {}
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await subscription.refresh() } }
                if phase == .background, let id = speaker.activeID { speaker.stop(id: id) }
            }
            .tint(MapStyle.pine)
        case .failure:
            ContentUnavailableView("无法加载词根地图", systemImage: "map", description: Text("应用内的词汇文件缺失或损坏。"))
        }
    }
}

private struct HistoryView: View {
    @Query(sort: \LearningAttemptRecord.answeredAt, order: .reverse) private var records: [LearningAttemptRecord]
    @Query(sort: \CourseDayRecord.updatedAt, order: .reverse) private var lessons: [CourseDayRecord]
    let lexicon: Lexicon
    let course: DailyCourse?

    var body: some View {
        NavigationStack {
            List {
                if let course, !lessons.isEmpty {
                    Section("课程进度") {
                        ForEach(lessons) { record in
                            if let day = course.day(forRecord: record.day) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("第 \(day.id) 天 · \(day.title)").font(.headline)
                                    Text(record.isFinished(in: day) ? "已完成" : "学习中")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            } else if CourseDay.dayRange.contains(record.day) {
                                Text("旧版场景课 · 第 \(record.day) 天").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !records.isEmpty {
                    Section("词汇作答") {
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 5) {
                                if let word = lexicon.word(id: record.senseID) {
                                    Text(word.word).font(.headline)
                                }
                                Text("作答：\(record.firstAnswer)")
                                Text("\(abilityName(record.abilityRawValue)) · \(record.answeredAt.formatted())")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .overlay {
                if records.isEmpty && lessons.isEmpty {
                    ContentUnavailableView("还没有学习记录", systemImage: "chart.bar.xaxis")
                }
            }
            .navigationTitle("学习记录")
        }
    }

    private func abilityName(_ raw: String) -> String {
        switch LearningAbility(rawValue: raw) {
        case .choiceRecognition: "记忆卡选择"
        case .pronunciationSelfCheck: "发音自查"
        case .meaningRecall: "词义回忆"
        case .audioMeaning: "听音识义"
        case .contextCuedProduction: "语境填词"
        case nil: "未知题型"
        }
    }
}
