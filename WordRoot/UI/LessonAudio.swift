import Foundation
import SQLite3

/// All English playback resolves to the same offline Heart recording for a given text and IPA.
final class LessonAudio {
    private let database: OpaquePointer?
    private static let englishVoice = "af_heart"

    init(bundle: Bundle = .main) {
        var connection: OpaquePointer?
        if let file = bundle.url(forResource: "LessonAudio", withExtension: "sqlite"),
           sqlite3_open_v2(file.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            database = connection
        } else {
            sqlite3_close(connection)
            database = nil
        }
    }

    deinit { sqlite3_close(database) }

    func recording(_ text: String, pronunciation: String? = nil) -> (bytes: Data, source: String)? {
        clip(text, pronunciation: pronunciation, voice: Self.englishVoice).map { ($0, Self.englishVoice) }
    }

    struct PartRecording {
        let whole: Data
        let excerpt: Data
        let startMS: Int
        let endMS: Int
    }

    func wordPart(wordID: String, index: Int) -> PartRecording? {
        let sql = """
            SELECT c.mp3, p.mp3, p.start_ms, p.end_ms
            FROM word_parts p JOIN clips c ON c.key = p.word_key
            WHERE p.word_id = ? AND p.position = ?
            """
        guard let database else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let copy = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard wordID.withCString({ sqlite3_bind_text(statement, 1, $0, -1, copy) }) == SQLITE_OK,
              sqlite3_bind_int64(statement, 2, Int64(index)) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW,
              let whole = sqlite3_column_blob(statement, 0), let part = sqlite3_column_blob(statement, 1)
        else { return nil }
        return PartRecording(whole: Data(bytes: whole, count: Int(sqlite3_column_bytes(statement, 0))),
                             excerpt: Data(bytes: part, count: Int(sqlite3_column_bytes(statement, 1))),
                             startMS: Int(sqlite3_column_int(statement, 2)),
                             endMS: Int(sqlite3_column_int(statement, 3)))
    }

    func mandarin(_ text: String) -> Data? {
        clip(text, pronunciation: nil, voice: "zf_xiaoxiao")
    }

    private func clip(_ text: String, pronunciation: String?, voice: String) -> Data? {
        let key = [voice, pronunciation ?? "", text].joined(separator: "\u{1F}")
            .precomposedStringWithCanonicalMapping
        var statement: OpaquePointer?
        guard let database,
              sqlite3_prepare_v2(database, "SELECT mp3 FROM clips WHERE key = ?", -1, &statement, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard key.withCString({ sqlite3_bind_text(statement, 1, $0, -1, transient) }) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0)
        else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
}
