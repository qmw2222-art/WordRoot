import Foundation

struct FirstWordListen {
    private(set) var revealed = false

    func waiting(automatic: Bool, screenReader: Bool) -> Bool {
        automatic && !screenReader && !revealed
    }

    mutating func show() { revealed = true }

    mutating func segmentChanged(isCurrentWord: Bool, index: Int?) {
        if isCurrentWord, let index, index > 0 { show() }
    }
}

enum LessonPlaybackTrace {
    #if DEBUG
    private static let destination: URL? = {
        guard let raw = ProcessInfo.processInfo.environment["WORDROOT_UI_TEST_RUN"], UUID(uuidString: raw) != nil else { return nil }
        let url = URL.temporaryDirectory.appendingPathComponent("wordroot-audio-" + raw + ".txt")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        return url
    }()
    #endif

    static var isEnabled: Bool {
        #if DEBUG
        return destination != nil
        #else
        return false
        #endif
    }

    @MainActor static func note(_ message: String) {
        #if DEBUG
        guard let file = destination, let out = try? FileHandle(forWritingTo: file) else { return }
        defer { try? out.close() }
        guard (try? out.seekToEnd()) != nil else { return }
        try? out.write(contentsOf: Data((message + "\n").utf8))
        #endif
    }
}
