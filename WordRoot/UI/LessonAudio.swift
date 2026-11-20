import Foundation
import SQLite3

/// The same recording serves the lesson, the dictionary and listening practice.
final class LessonAudio {
    private var database: OpaquePointer?

    init(bundle: Bundle = .main) {
        guard let file = bundle.url(forResource: "LessonAudio", withExtension: "sqlite") else { return }
        if sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(database)
            database = nil
        }
    }

    deinit { sqlite3_close(database) }

    func recording(_ text: String, pronunciation: String? = nil) -> Data? {
        recording(text, pronunciation: pronunciation, voiceID: "af_heart")
    }

    func mandarin(_ text: String) -> Data? {
        recording(text, pronunciation: nil, voiceID: "zf_xiaoxiao")
    }

    private func recording(_ text: String, pronunciation: String?, voiceID: String) -> Data? {
        let key = [voiceID, pronunciation ?? "", text].joined(separator: "\u{1F}")
            .precomposedStringWithCanonicalMapping
        var statement: OpaquePointer?
        guard let database, sqlite3_prepare_v2(database, "SELECT mp3 FROM clips WHERE key = ?", -1,
                                                &statement, nil) == SQLITE_OK else { return nil }
        return key.withCString { pointer in
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_text(statement, 1, pointer, -1, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW,
                  let bytes = sqlite3_column_blob(statement, 0) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        }
    }
}
