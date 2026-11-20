import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private struct SnapshotDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SubscriptionService.self) private var subscription
    @Environment(SpeechPlayer.self) private var speaker
    @State private var document: SnapshotDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var restoreDetails = ""
    @State private var confirmingRestore = false
    @State private var confirmingDelete = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("英语发音") {
                Text("Heart · 美式女声").accessibilityIdentifier("settings.voice")
                SpeechButton(id: SpeechPlayer.auditionID,
                             text: "Hello. It’s nice to meet you. How are you today?",
                             label: "试听声音", identifier: SpeechPlayer.auditionID)
            }
            Section("学习记录") {
                Button("导出备份") { export() }
                Button("从备份恢复") { importing = true }
                Button("删除本机学习记录", role: .destructive) { confirmingDelete = true }
                if let message { Text(message).foregroundStyle(.secondary) }
            }
            Section("订阅") {
                NavigationLink("查看方案、管理订阅与恢复购买") { SubscriptionView() }
            }
        }
        .navigationTitle("设置")
        .onDisappear { speaker.stop(id: SpeechPlayer.auditionID) }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "WordRoot-Backup") { result in
            message = switch result {
            case .success: "已保存备份。"
            case .failure: "备份未能保存。"
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let snapshot = try BackupService.validate(data)
                pendingRestore = data
                let lessonCount = snapshot.courseDays?.count ?? 0
                restoreDetails = "\(snapshot.exportedAt.formatted()) 的备份含 \(lessonCount) 天课程进度、\(snapshot.attempts.count) 条作答和 \(snapshot.reviewCards.count) 张卡片。恢复会替换本机记录。"
                confirmingRestore = true
            } catch {
                message = "无法读取这份备份。当前记录已保留。"
            }
        }
        .alert("恢复备份", isPresented: $confirmingRestore) {
            Button("恢复", role: .destructive) { restore() }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: { Text(restoreDetails) }
        .alert("删除本机学习记录？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) { deleteHistory() }
            Button("先导出备份") { export() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除课程进度、作答和复习卡片。Apple 订阅仍然有效。")
        }
    }

    private func export() {
        do {
            document = SnapshotDocument(data: try BackupService.export(from: context))
            exporting = true
        } catch {
            message = "无法生成备份。"
        }
    }

    private func restore() {
        guard let pendingRestore else { return }
        defer { self.pendingRestore = nil }
        do {
            let before = try BackupService.export(from: context)
            let directory = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            )
            try before.write(to: directory.appendingPathComponent("WordRoot-BeforeRestore.json"), options: .atomic)
            try BackupService.restore(pendingRestore, into: context)
            message = "已恢复学习记录。"
            Task { await subscription.refresh() }
        } catch {
            message = "恢复未完成。请检查备份版本与内容。"
        }
    }

    private func deleteHistory() {
        do {
            try context.fetch(FetchDescriptor<LearningAttemptRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ReviewCardRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CourseDayRecord>()).forEach(context.delete)
            try context.save()
            message = "已删除本机学习记录。"
            Task { await subscription.refresh() }
        } catch {
            context.rollback()
            message = "未能删除学习记录。"
        }
    }
}
