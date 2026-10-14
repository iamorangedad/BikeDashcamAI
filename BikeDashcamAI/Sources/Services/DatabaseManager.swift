import Foundation
import SQLite3

enum DatabaseError: LocalizedError {
    case openFailed(String)
    case statementFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message): return "数据库打开失败: \(message)"
        case .statementFailed(let message): return "数据库操作失败: \(message)"
        }
    }
}

/// 系统 SQLite。骑行的 start/end 用 Unix 时间，片段的 start/end 用成片内的秒数。
final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.bikedashcam.database")
    private let destructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() {
        try? open()
    }

    func createRecording(_ recording: RideRecording) throws {
        try queue.sync {
            try insertRecording(recording)
        }
    }

    func updateRecording(_ recording: RideRecording) throws {
        try queue.sync {
            let sql = """
            UPDATE recordings SET end_time = ?, total_distance = ?, avg_speed = ?, max_speed = ?,
            total_duration = ?, total_ascent = ?, total_descent = ?, thumbnail_path = ?, video_path = ?
            WHERE id = ?
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindDouble(statement, 1, recording.endTime)
            sqlite3_bind_double(statement, 2, recording.totalDistance)
            sqlite3_bind_double(statement, 3, recording.avgSpeed)
            sqlite3_bind_double(statement, 4, recording.maxSpeed)
            sqlite3_bind_double(statement, 5, recording.totalDuration)
            sqlite3_bind_double(statement, 6, recording.totalAscent)
            sqlite3_bind_double(statement, 7, recording.totalDescent)
            bindOptionalText(statement, 8, recording.thumbnailPath)
            bindText(statement, 9, recording.videoPath)
            bindText(statement, 10, recording.id.uuidString)
            try stepDone(statement)
        }
    }

    func getRecording(id: UUID) throws -> RideRecording? {
        try queue.sync {
            let statement = try prepare("SELECT * FROM recordings WHERE id = ? LIMIT 1")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            if sqlite3_step(statement) == SQLITE_ROW {
                return readRecording(statement)
            }
            return nil
        }
    }

    func getAllRecordings(limit: Int? = nil, offset: Int? = nil) throws -> [RideRecording] {
        try queue.sync {
            var sql = "SELECT * FROM recordings ORDER BY created_at DESC"
            if let limit {
                sql += " LIMIT \(limit)"
                if let offset {
                    sql += " OFFSET \(offset)"
                }
            }
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            var rows: [RideRecording] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(readRecording(statement))
            }
            return rows
        }
    }

    func deleteRecording(id: UUID) throws {
        try queue.sync {
            let statement = try prepare("DELETE FROM recordings WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            try stepDone(statement)
        }
    }

    func createSegment(_ segment: SceneSegment) throws {
        try queue.sync {
            try insertSegment(segment)
        }
    }

    func updateSegment(_ segment: SceneSegment) throws {
        try queue.sync {
            let sql = """
            UPDATE scene_segments SET end_time = ?, scene_type = ?, description = ?, location_lat = ?,
            location_lon = ?, avg_speed = ?, video_path = ?, thumbnail_path = ?, is_compressed = ?, compression_ratio = ?
            WHERE id = ?
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindDouble(statement, 1, segment.endTime)
            bindText(statement, 2, segment.sceneType.rawValue)
            bindText(statement, 3, segment.description)
            bindDouble(statement, 4, segment.latitude)
            bindDouble(statement, 5, segment.longitude)
            bindDouble(statement, 6, segment.avgSpeed)
            bindText(statement, 7, segment.videoPath)
            bindOptionalText(statement, 8, segment.thumbnailPath)
            sqlite3_bind_int(statement, 9, segment.isCompressed ? 1 : 0)
            bindDouble(statement, 10, segment.compressionRatio.map(Double.init))
            bindText(statement, 11, segment.id.uuidString)
            try stepDone(statement)
        }
    }

    func getSegments(forRecording id: UUID) throws -> [SceneSegment] {
        try queue.sync {
            let statement = try prepare("SELECT * FROM scene_segments WHERE recording_id = ? ORDER BY start_time ASC")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            var rows: [SceneSegment] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(readSegment(statement))
            }
            return rows
        }
    }

    func deleteSegment(id: UUID) throws {
        try queue.sync {
            let statement = try prepare("DELETE FROM scene_segments WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            try stepDone(statement)
        }
    }

    func createBookmark(_ bookmark: Bookmark) throws {
        try queue.sync {
            let sql = """
            INSERT INTO bookmarks (id, recording_id, timestamp, type, description, voice_note_path, thumbnail_path, is_user_created, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, bookmark.id.uuidString)
            bindText(statement, 2, bookmark.recordingID.uuidString)
            sqlite3_bind_double(statement, 3, bookmark.timestamp)
            bindText(statement, 4, bookmark.type)
            bindOptionalText(statement, 5, bookmark.description)
            bindOptionalText(statement, 6, bookmark.voiceNotePath)
            bindOptionalText(statement, 7, bookmark.thumbnailPath)
            sqlite3_bind_int(statement, 8, bookmark.isUserCreated ? 1 : 0)
            bindText(statement, 9, isoDate(bookmark.createdAt))
            try stepDone(statement)
        }
    }

    func getBookmarks(forRecording id: UUID) throws -> [Bookmark] {
        try queue.sync {
            let statement = try prepare("SELECT * FROM bookmarks WHERE recording_id = ? ORDER BY timestamp ASC")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            var rows: [Bookmark] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(readBookmark(statement))
            }
            return rows
        }
    }

    func deleteBookmark(id: UUID) throws {
        try queue.sync {
            let statement = try prepare("DELETE FROM bookmarks WHERE id = ?")
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, id.uuidString)
            try stepDone(statement)
        }
    }

    func getTotalStats() throws -> RidingStats {
        try queue.sync {
            let statement = try prepare("SELECT COUNT(*), COALESCE(SUM(total_distance), 0), COALESCE(SUM(total_duration), 0), COALESCE(AVG(avg_speed), 0) FROM recordings")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                return RidingStats(totalRecordings: 0, totalDistance: 0, totalDuration: 0, avgSpeed: 0)
            }
            return RidingStats(
                totalRecordings: Int(sqlite3_column_int(statement, 0)),
                totalDistance: sqlite3_column_double(statement, 1),
                totalDuration: sqlite3_column_double(statement, 2),
                avgSpeed: sqlite3_column_double(statement, 3)
            )
        }
    }

    private func open() throws {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BikeDashcam.sqlite")
        if sqlite3_open(url.path, &db) != SQLITE_OK {
            throw DatabaseError.openFailed(lastError())
        }
        try exec("PRAGMA foreign_keys = ON")
        try migrate()
    }

    private func migrate() throws {
        let version = try userVersion()
        guard version < 1 else { return }
        try exec("""
        CREATE TABLE IF NOT EXISTS recordings (
            id TEXT PRIMARY KEY,
            start_time REAL NOT NULL,
            end_time REAL,
            total_distance REAL,
            avg_speed REAL,
            max_speed REAL,
            total_duration REAL,
            total_ascent REAL,
            total_descent REAL,
            created_at TEXT NOT NULL,
            thumbnail_path TEXT,
            video_path TEXT
        );
        CREATE TABLE IF NOT EXISTS scene_segments (
            id TEXT PRIMARY KEY,
            recording_id TEXT NOT NULL,
            start_time REAL NOT NULL,
            end_time REAL,
            scene_type TEXT NOT NULL,
            description TEXT,
            location_lat REAL,
            location_lon REAL,
            avg_speed REAL,
            video_path TEXT NOT NULL,
            thumbnail_path TEXT,
            is_compressed INTEGER DEFAULT 0,
            compression_ratio REAL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS bookmarks (
            id TEXT PRIMARY KEY,
            recording_id TEXT NOT NULL,
            timestamp REAL NOT NULL,
            type TEXT NOT NULL,
            description TEXT,
            voice_note_path TEXT,
            thumbnail_path TEXT,
            is_user_created INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_segments_recording ON scene_segments(recording_id);
        CREATE INDEX IF NOT EXISTS idx_bookmarks_recording ON bookmarks(recording_id);
        CREATE INDEX IF NOT EXISTS idx_recordings_date ON recordings(created_at DESC);
        """)
        try exec("PRAGMA user_version = 1")
    }

    private func insertRecording(_ recording: RideRecording) throws {
        let sql = """
        INSERT OR REPLACE INTO recordings
        (id, start_time, end_time, total_distance, avg_speed, max_speed, total_duration, total_ascent, total_descent, created_at, thumbnail_path, video_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, recording.id.uuidString)
        sqlite3_bind_double(statement, 2, recording.startTime)
        bindDouble(statement, 3, recording.endTime)
        sqlite3_bind_double(statement, 4, recording.totalDistance)
        sqlite3_bind_double(statement, 5, recording.avgSpeed)
        sqlite3_bind_double(statement, 6, recording.maxSpeed)
        sqlite3_bind_double(statement, 7, recording.totalDuration)
        sqlite3_bind_double(statement, 8, recording.totalAscent)
        sqlite3_bind_double(statement, 9, recording.totalDescent)
        bindText(statement, 10, isoDate(recording.createdAt))
        bindOptionalText(statement, 11, recording.thumbnailPath)
        bindText(statement, 12, recording.videoPath)
        try stepDone(statement)
    }

    private func insertSegment(_ segment: SceneSegment) throws {
        let sql = """
        INSERT OR REPLACE INTO scene_segments
        (id, recording_id, start_time, end_time, scene_type, description, location_lat, location_lon, avg_speed, video_path, thumbnail_path, is_compressed, compression_ratio, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, segment.id.uuidString)
        bindText(statement, 2, segment.recordingID.uuidString)
        sqlite3_bind_double(statement, 3, segment.startTime)
        bindDouble(statement, 4, segment.endTime)
        bindText(statement, 5, segment.sceneType.rawValue)
        bindText(statement, 6, segment.description)
        bindDouble(statement, 7, segment.latitude)
        bindDouble(statement, 8, segment.longitude)
        bindDouble(statement, 9, segment.avgSpeed)
        bindText(statement, 10, segment.videoPath)
        bindOptionalText(statement, 11, segment.thumbnailPath)
        sqlite3_bind_int(statement, 12, segment.isCompressed ? 1 : 0)
        bindDouble(statement, 13, segment.compressionRatio.map(Double.init))
        bindText(statement, 14, isoDate(segment.createdAt))
        try stepDone(statement)
    }

    private func readRecording(_ statement: OpaquePointer?) -> RideRecording {
        RideRecording(
            id: uuid(statement, 0),
            startTime: sqlite3_column_double(statement, 1),
            endTime: optionalDouble(statement, 2),
            totalDistance: sqlite3_column_double(statement, 3),
            avgSpeed: sqlite3_column_double(statement, 4),
            maxSpeed: sqlite3_column_double(statement, 5),
            totalDuration: sqlite3_column_double(statement, 6),
            totalAscent: sqlite3_column_double(statement, 7),
            totalDescent: sqlite3_column_double(statement, 8),
            createdAt: date(statement, 9),
            thumbnailPath: optionalText(statement, 10),
            videoPath: text(statement, 11)
        )
    }

    private func readSegment(_ statement: OpaquePointer?) -> SceneSegment {
        let scene = SceneType(rawValue: text(statement, 4)) ?? .other
        return SceneSegment(
            id: uuid(statement, 0),
            recordingID: uuid(statement, 1),
            startTime: sqlite3_column_double(statement, 2),
            endTime: optionalDouble(statement, 3),
            sceneType: scene,
            description: text(statement, 5),
            latitude: optionalDouble(statement, 6),
            longitude: optionalDouble(statement, 7),
            avgSpeed: optionalDouble(statement, 8),
            thumbnailPath: optionalText(statement, 10),
            videoPath: text(statement, 9),
            isCompressed: sqlite3_column_int(statement, 11) == 1,
            compressionRatio: optionalDouble(statement, 12).map { Float($0) },
            createdAt: date(statement, 13)
        )
    }

    private func readBookmark(_ statement: OpaquePointer?) -> Bookmark {
        Bookmark(
            id: uuid(statement, 0),
            recordingID: uuid(statement, 1),
            timestamp: sqlite3_column_double(statement, 2),
            type: text(statement, 3),
            description: optionalText(statement, 4),
            voiceNotePath: optionalText(statement, 5),
            thumbnailPath: optionalText(statement, 6),
            isUserCreated: sqlite3_column_int(statement, 7) == 1,
            createdAt: date(statement, 8)
        )
    }

    private func userVersion() throws -> Int {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastError()
            sqlite3_free(error)
            throw DatabaseError.statementFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw DatabaseError.statementFailed(lastError())
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw DatabaseError.statementFailed(lastError())
        }
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(statement, index, pointer, -1, destructor)
        }
    }

    private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindDouble(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }

    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let value = text(statement, index)
        return value.isEmpty ? nil : value
    }

    private func optionalDouble(_ statement: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    private func uuid(_ statement: OpaquePointer?, _ index: Int32) -> UUID {
        UUID(uuidString: text(statement, index)) ?? UUID()
    }

    private func date(_ statement: OpaquePointer?, _ index: Int32) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text(statement, index)) ?? Date()
    }

    private func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func lastError() -> String {
        guard let db else { return "sqlite" }
        return String(cString: sqlite3_errmsg(db))
    }
}
