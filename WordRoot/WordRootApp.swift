import SwiftData
import SwiftUI

@main
struct WordRootApp: App {
    @State private var subscription = SubscriptionService()
    fileprivate static let learningModels: [any PersistentModel.Type] = [
        LearningAttemptRecord.self, ReviewCardRecord.self, CourseDayRecord.self, FamilyPracticeRecord.self
    ]
    #if DEBUG
    private let testRun = TestRun()
    #endif

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let testRun {
                if let container = testRun.container, let defaults = testRun.defaults {
                    root(using: defaults).defaultAppStorage(defaults).modelContainer(container)
                } else {
                    ContentUnavailableView("测试数据无法载入", systemImage: "exclamationmark.circle")
                }
            } else {
                root(using: .standard).modelContainer(for: Self.learningModels)
            }
            #else
            root(using: .standard).modelContainer(for: Self.learningModels)
            #endif
        }
    }

    private func root(using defaults: UserDefaults) -> some View {
        RootView(studyDefaults: defaults)
            .environment(subscription)
            .task { await subscription.monitor() }
    }
}

#if DEBUG
@MainActor
private struct TestRun {
    let defaults: UserDefaults?
    let container: ModelContainer?

    init?() {
        guard let id = ProcessInfo.processInfo.environment["WORDROOT_UI_TEST_RUN"],
              UUID(uuidString: id) != nil else { return nil }
        let name = "wordroot-ui-\(id)"
        defaults = UserDefaults(suiteName: name)
        let schema = Schema(WordRootApp.learningModels)
        let configuration = ModelConfiguration(
            schema: schema, url: URL.temporaryDirectory.appendingPathComponent(name + ".store"),
            cloudKitDatabase: .none
        )
        let isolated = try? ModelContainer(for: schema, configurations: [configuration])
        if ProcessInfo.processInfo.environment["WORDROOT_TEST_LEGACY_DAY"] == "wash-v22",
           let isolated, let defaults {
            do { try Self.restoreMixedCourse(in: isolated, defaults: defaults) }
            catch { container = nil; return }
        }
        if let fixture = ProcessInfo.processInfo.environment["WORDROOT_TEST_LEGACY_DAY"],
           ["port-start-v24", "port-finished-v24", "port-backup-v24", "drink-backup-v25"].contains(fixture), let isolated, let defaults {
            let context = ModelContext(isolated)
            do {
                if try context.fetchCount(FetchDescriptor<CourseDayRecord>()) == 0 {
                    let current = try DailyCourse.bundled.get()
                    let returning = fixture != "drink-backup-v25"
                    let course = returning ? current.preservingLegacyRecords([2001]) : current
                    guard let first = course[1] else { throw CocoaError(.fileReadCorruptFile) }
                    let done = fixture == "port-finished-v24"
                    let isBackup = fixture.contains("-backup-")
                    let step = done ? first.lastStep : isBackup ? (returning ? 4 : 2) : 0
                    let studied = done ? first.lessonIDs : Array(first.lessonIDs.prefix(max(0, step - 1)))
                    if isBackup {
                        let day = CourseDaySnapshot(day: first.recordID, step: step, updatedAt: .now, completedAt: nil, studiedIDs: studied)
                        let snapshot = LearningSnapshot(formatVersion: returning ? 6 : 7, exportedAt: .now, reviewCards: [], attempts: [], courseDays: [day])
                        try BackupService.restore(JSONEncoder().encode(snapshot), into: context, defaults: defaults)
                        let exported = try BackupService.export(from: context, defaults: defaults)
                        let target = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
                        let other = ModelContext(target)
                        try BackupService.restore(exported, into: other, defaults: defaults)
                        let rows = try other.fetch(FetchDescriptor<CourseDayRecord>())
                        guard rows.count == 1, let restored = rows.first, restored.day == day.day,
                              restored.step == step, restored.studiedIDs == studied else { throw BackupError.invalidSnapshot }
                    } else {
                        let row = CourseDayRecord(day: first.recordID, step: step, completedAt: done ? .now : nil)
                        row.studiedIDs = studied
                        context.insert(row)
                        try context.save()
                    }
                }
            } catch { container = nil; return }
        }
        container = isolated
        if let container, let due = ProcessInfo.processInfo.environment["WORDROOT_TEST_DUE_WORD"],
           ["basic.new", "basic.now", "basic.present", "basic.like"].contains(due) {
            let context = ModelContext(container)
            _ = try? CourseReview.seed(due, in: context)
            try? context.save()
        }
        if let container, let fixture = ProcessInfo.processInfo.environment["WORDROOT_TEST_LEGACY_DAY"],
           ["1", "completed-v11"].contains(fixture) {
            let context = ModelContext(container)
            if (try? context.fetchCount(FetchDescriptor<CourseDayRecord>())) == 0 {
                let row = CourseDayRecord(day: 1001, step: 5, completedAt: .now)
                if fixture == "completed-v11" {
                    row.studiedIDs = ["sense.import.goods", "sense.export.goods", "sense.transport.carry", "sense.portable.easy-carry",
                                      "basic.i", "basic.take", "basic.this", "basic.bag", "basic.you", "basic.please",
                                      "basic.give", "basic.of", "basic.small"]
                    row.step = 14
                }
                context.insert(row)
                try? context.save()
            }
        }
    }

    // Exercise a real old backup and a mixed-version round trip in the isolated UI-test store.
    @MainActor
    private static func restoreMixedCourse(in container: ModelContainer, defaults: UserDefaults) throws {
        let context = ModelContext(container)
        guard try context.fetchCount(FetchDescriptor<CourseDayRecord>()) == 0 else { return }
        let wash = CourseDaySnapshot(day: 1003, step: 5, updatedAt: .now, completedAt: nil,
            studiedIDs: ["wash.wash", "wash.washer", "wash.dishwasher", "basic.wash"])
        let old = LearningSnapshot(formatVersion: 5, exportedAt: .now, reviewCards: [], attempts: [], courseDays: [wash])
        try BackupService.restore(JSONEncoder().encode(old), into: context, defaults: defaults)
        let first = CourseDayRecord(day: 2001, step: 1, updatedAt: .distantPast)
        first.studiedIDs = []
        context.insert(first)
        try context.save()
        let data = try BackupService.export(from: context, defaults: defaults)
        let other = ModelContext(container)
        try BackupService.restore(data, into: other, defaults: defaults)
        let restored = try other.fetch(FetchDescriptor<CourseDayRecord>())
        guard restored.count == 2, restored.contains(where: { $0.day == 1003 && $0.studiedIDs == wash.studiedIDs }),
              restored.contains(where: { $0.day == 2001 && $0.step == 1 && $0.studiedIDs == [] }) else {
            throw BackupError.invalidSnapshot
        }
    }
}
#endif
