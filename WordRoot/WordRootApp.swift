import SwiftData
import SwiftUI

@main
struct WordRootApp: App {
    @State private var subscription = SubscriptionService()
    fileprivate static let learningModels: [any PersistentModel.Type] = [
        LearningAttemptRecord.self, ReviewCardRecord.self, CourseDayRecord.self
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
        container = try? ModelContainer(for: schema, configurations: [configuration])
        if let container, ProcessInfo.processInfo.environment["WORDROOT_TEST_LEGACY_DAY"] == "1" {
            let context = ModelContext(container)
            if (try? context.fetchCount(FetchDescriptor<CourseDayRecord>())) == 0 {
                context.insert(CourseDayRecord(day: 1001, step: 5, completedAt: .now))
                try? context.save()
            }
        }
    }
}
#endif
