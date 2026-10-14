import Foundation

struct RideMark: Codable {
    let videoTime: TimeInterval
    let createdAt: Date
}

struct RecordingMetadata: Codable {
    let id: UUID
    let segmentID: UUID
    var startedAt: Date
    var endedAt: Date?
    var videoFileName: String
    var width: Int
    var height: Int
    var frameRate: Int
    var bitrate: Int
    var hdrSupported: Bool
    var colorSpace: String
    var stabilization: Bool
    var marks: [RideMark]
    var encodedFrames: Int
    var sampledFrames: Int
    var distanceMeters: Double
    var maxSpeedMetersPerSecond: Double
    var averageSpeedMetersPerSecond: Double
}

enum RecordingCoordinatorError: LocalizedError {
    case notRecording
    case persistFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRecording: return "当前没有正在进行的录制"
        case .persistFailed(let message): return "保存骑行记录失败: \(message)"
        }
    }
}

/// 把相机成片、3fps 抽帧统计和传感器轨迹写到同一次骑行目录。
final class RecordingCoordinator {
    let camera: CameraManager
    let sensors: SensorDataCollector
    private let files: FileSystemManager

    private(set) var recordingID: UUID?
    private var segmentID: UUID?
    private var startedAt: Date?
    private var marks: [RideMark] = []
    private let lock = NSLock()

    init(camera: CameraManager, sensors: SensorDataCollector, files: FileSystemManager = .shared) {
        self.camera = camera
        self.sensors = sensors
        self.files = files
        try? files.cleanupTempFiles()
    }

    func startRecording() throws {
        lock.lock()
        guard recordingID == nil else {
            lock.unlock()
            return
        }
        let recordingID = UUID()
        let segmentID = UUID()
        self.recordingID = recordingID
        self.segmentID = segmentID
        self.startedAt = Date()
        self.marks = []
        lock.unlock()

        do {
            _ = try files.createRecordingDirectory(for: recordingID)
            let url = files.segmentVideoURL(recordingID: recordingID, segmentID: segmentID)
            camera.startRecording(to: url) { [weak self] error in
                guard let self, error != nil else { return }
                self.lock.lock()
                let stillCurrent = self.recordingID == recordingID
                if stillCurrent {
                    self.recordingID = nil
                    self.segmentID = nil
                    self.startedAt = nil
                    self.marks = []
                }
                self.lock.unlock()
                if stillCurrent {
                    try? self.files.deleteRecording(recordingID)
                }
            }
        } catch {
            lock.lock()
            self.recordingID = nil
            self.segmentID = nil
            self.startedAt = nil
            lock.unlock()
            throw error
        }
    }

    func pauseRecording() {
        camera.pauseRecording()
    }

    func resumeRecording() {
        camera.resumeRecording()
    }

    func addMark() {
        guard camera.recordingState == .recording || camera.recordingState == .paused else { return }
        let mark = RideMark(videoTime: camera.recordingDuration, createdAt: Date())
        lock.lock()
        marks.append(mark)
        lock.unlock()
    }

    func stopRecording(completion: @escaping (Result<RecordingMetadata, Error>) -> Void) {
        lock.lock()
        guard let recordingID, let segmentID, let startedAt else {
            lock.unlock()
            completion(.failure(RecordingCoordinatorError.notRecording))
            return
        }
        let marks = self.marks
        lock.unlock()

        camera.stopRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.lock.lock()
                self.recordingID = nil
                self.segmentID = nil
                self.startedAt = nil
                self.marks = []
                self.lock.unlock()
                completion(.failure(error))
            case .success:
                let end = Date()
                let frames = self.sensors.frames(from: startedAt.timeIntervalSince1970, to: end.timeIntervalSince1970)
                let stats = self.sensors.getCurrentStatistics()
                let configuration = self.camera.configuration
                let recordingStats = self.camera.lastStatistics
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let metadata = try self.persist(
                            recordingID: recordingID,
                            segmentID: segmentID,
                            startedAt: startedAt,
                            endedAt: end,
                            marks: marks,
                            frames: frames,
                            stats: stats,
                            configuration: configuration,
                            recordingStats: recordingStats
                        )
                        DispatchQueue.main.async {
                            self.lock.lock()
                            self.recordingID = nil
                            self.segmentID = nil
                            self.startedAt = nil
                            self.marks = []
                            self.lock.unlock()
                            completion(.success(metadata))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                }
            }
        }
    }

    private func persist(
        recordingID: UUID,
        segmentID: UUID,
        startedAt: Date,
        endedAt: Date,
        marks: [RideMark],
        frames: [SensorFrame],
        stats: SensorStatistics,
        configuration: CaptureConfiguration,
        recordingStats: RecordingStatistics
    ) throws -> RecordingMetadata {
        let metadata = RecordingMetadata(
            id: recordingID,
            segmentID: segmentID,
            startedAt: startedAt,
            endedAt: endedAt,
            videoFileName: "segments/\(segmentID.uuidString).mov",
            width: configuration.width,
            height: configuration.height,
            frameRate: configuration.frameRate,
            bitrate: configuration.bitratePreset.bitrate,
            hdrSupported: configuration.hdrSupported,
            colorSpace: configuration.colorSpace,
            stabilization: configuration.stabilization,
            marks: marks,
            encodedFrames: recordingStats.encodedFrames,
            sampledFrames: recordingStats.sampledFrames,
            distanceMeters: stats.totalDistance,
            maxSpeedMetersPerSecond: stats.maxSpeed,
            averageSpeedMetersPerSecond: stats.averageSpeed
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(metadata).write(to: files.metadataURL(recordingID: recordingID), options: .atomic)
            try encoder.encode(frames).write(to: files.sensorsURL(recordingID: recordingID), options: .atomic)
        } catch {
            throw RecordingCoordinatorError.persistFailed(error.localizedDescription)
        }
        return metadata
    }
}
