import Foundation
import SQLite3

/// The same recording serves the lesson, the dictionary and listening practice.
final class LessonAudio {
    private var database: OpaquePointer?
    private var nativeWords: OpaquePointer?

    init(bundle: Bundle = .main) {
        database = Self.open("LessonAudio", in: bundle)
        nativeWords = Self.open("WordAudio", in: bundle)
    }

    private static func open(_ resource: String, in bundle: Bundle) -> OpaquePointer? {
        guard let file = bundle.url(forResource: resource, withExtension: "sqlite") else { return nil }
        var connection: OpaquePointer?
        guard sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            return nil
        }
        return connection
    }

    deinit {
        sqlite3_close(database)
        sqlite3_close(nativeWords)
    }

    func recording(_ text: String, pronunciation: String? = nil) -> (bytes: Data, source: String)? {
        if let pronunciation,
           let human = query(nativeWords, sql: "SELECT mp3 FROM recordings WHERE spelling = ? AND ipa = ?",
                             values: [text, pronunciation]) {
            return (human, "wiktionary-us")
        }
        return recording(text, pronunciation: pronunciation, voiceID: "af_heart").map { ($0, "af_heart") }
    }

    func mandarin(_ text: String) -> Data? {
        recording(text, pronunciation: nil, voiceID: "zf_xiaoxiao")
    }

    private func recording(_ text: String, pronunciation: String?, voiceID: String) -> Data? {
        let key = [voiceID, pronunciation ?? "", text].joined(separator: "\u{1F}")
            .precomposedStringWithCanonicalMapping
        return query(database, sql: "SELECT mp3 FROM clips WHERE key = ?", values: [key])
    }

    private func query(_ db: OpaquePointer?, sql: String, values: [String]) -> Data? {
        var statement: OpaquePointer?
        guard let db, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, transient) }
            guard status == SQLITE_OK else { return nil }
        }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
