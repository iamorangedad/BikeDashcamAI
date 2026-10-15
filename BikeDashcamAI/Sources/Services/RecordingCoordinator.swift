import Combine
import CoreLocation
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

/// 把相机成片、传感器和场景片段写到同一次骑行。片段是成片上的时间区间。
final class RecordingCoordinator {
    let camera: CameraManager
    let sensors: SensorDataCollector
    private let files: FileSystemManager
    private let database: DatabaseManager
    private let segments: SegmentManager
    private let sceneDetector = SceneDetector()
    private let descriptions = DescriptionGenerator()

    private(set) var recordingID: UUID?
    private var segmentID: UUID?
    private var sessionToken = UUID()
    private var startedAt: Date?
    private var marks: [RideMark] = []
    private let lock = NSLock()
    private let analysis = DispatchQueue(label: "com.bikedashcam.analysis")
    private var sensorCancellable: AnyCancellable?
    private var lastIngestVideoTime: TimeInterval = -1
    private var speedSamples: [Double] = []
    private var segmentAscent = 0.0
    private var segmentDescent = 0.0
    private var rideAscent = 0.0
    private var rideDescent = 0.0
    private var lastAltitude: Double?
    private var lastSpeed: Double?
    private var videoRelativePath = ""

    init(
        camera: CameraManager,
        sensors: SensorDataCollector,
        files: FileSystemManager = .shared,
        database: DatabaseManager = .shared,
        segments: SegmentManager = .shared
    ) {
        self.camera = camera
        self.sensors = sensors
        self.files = files
        self.database = database
        self.segments = segments
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
        let token = UUID()
        self.recordingID = recordingID
        self.segmentID = segmentID
        self.sessionToken = token
        self.startedAt = Date()
        self.marks = []
        videoRelativePath = "segments/\(segmentID.uuidString).mov"
        lock.unlock()
        analysis.sync {
            self.resetAnalysisState()
        }

        do {
            _ = try files.createRecordingDirectory(for: recordingID)
            let url = files.segmentVideoURL(recordingID: recordingID, segmentID: segmentID)
            sceneDetector.reset()
            let ride = RideRecording(
                id: recordingID,
                startTime: Date().timeIntervalSince1970,
                endTime: nil,
                totalDistance: 0,
                avgSpeed: 0,
                maxSpeed: 0,
                totalDuration: 0,
                totalAscent: 0,
                totalDescent: 0,
                createdAt: Date(),
                thumbnailPath: nil,
                videoPath: videoRelativePath
            )
            try? database.createRecording(ride)
            _ = segments.createSegment(
                for: recordingID,
                sceneType: .other,
                videoPath: videoRelativePath,
                startTime: 0,
                location: nil,
                avgSpeed: nil,
                description: "骑行开始"
            )
            observeSensors(token: token)
            camera.startRecording(to: url) { [weak self] error in
                guard let self, error != nil else { return }
                self.abort(recordingID)
            }
        } catch {
            abort(recordingID)
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
        let videoTime = camera.recordingDuration
        let mark = RideMark(videoTime: videoTime, createdAt: Date())
        lock.lock()
        marks.append(mark)
        let recordingID = self.recordingID
        let token = sessionToken
        lock.unlock()
        if let recordingID {
            let bookmark = Bookmark(
                id: UUID(),
                recordingID: recordingID,
                timestamp: videoTime,
                type: "manual",
                description: "手动标记",
                voiceNotePath: nil,
                thumbnailPath: nil,
                isUserCreated: true,
                createdAt: Date()
            )
            try? database.createBookmark(bookmark)
        }
        sceneDetector.forceSceneChange()
        analysis.sync {
            guard let recordingID, self.isSession(token, recordingID: recordingID) else { return }
            self.ingest(sensor: nil, videoTime: videoTime, forced: true, recordingID: recordingID)
        }
    }

    func stopRecording(completion: @escaping (Result<RecordingMetadata, Error>) -> Void) {
        lock.lock()
        guard let recordingID, let segmentID, let startedAt else {
            lock.unlock()
            completion(.failure(RecordingCoordinatorError.notRecording))
            return
        }
        let marks = self.marks
        let videoPath = videoRelativePath
        let token = sessionToken
        lock.unlock()
        sensorCancellable?.cancel()
        sensorCancellable = nil

        camera.stopRecording { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.clearSession()
                completion(.failure(error))
            case .success:
                let end = Date()
                let frames = self.sensors.frames(from: startedAt.timeIntervalSince1970, to: end.timeIntervalSince1970)
                let stats = self.sensors.getCurrentStatistics()
                let configuration = self.camera.configuration
                let recordingStats = self.camera.lastStatistics
                self.analysis.sync {
                    guard self.isSession(token, recordingID: recordingID) else { return }
                    self.closeOpenSegment(at: recordingStats.duration, recordingID: recordingID)
                }
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
                            recordingStats: recordingStats,
                            videoPath: videoPath
                        )
                        self.scheduleThumbnails(recordingID: recordingID)
                        DispatchQueue.main.async {
                            self.clearSession()
                            NotificationCenter.default.post(name: .rideLibraryDidChange, object: recordingID)
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

    private func observeSensors(token: UUID) {
        sensorCancellable = sensors.sensorFramePublisher
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] frame in
                guard let self else { return }
                self.analysis.async {
                    self.lock.lock()
                    let recordingID = self.recordingID
                    let current = self.sessionToken
                    self.lock.unlock()
                    guard current == token, let recordingID else { return }
                    guard self.camera.recordingState == .recording else { return }
                    let videoTime = self.camera.recordingDuration
                    guard videoTime - self.lastIngestVideoTime >= 0.8 else { return }
                    self.lastIngestVideoTime = videoTime
                    self.ingest(sensor: frame, videoTime: videoTime, forced: false, recordingID: recordingID)
                }
            }
    }

    private func ingest(sensor frame: SensorFrame?, videoTime: TimeInterval, forced: Bool, recordingID: UUID) {
        if let speed = frame?.currentSpeed ?? frame?.speed, speed >= 0 {
            speedSamples.append(speed)
        }
        noteAltitude(frame)
        let prediction = ScenePrediction(
            sceneType: .other,
            confidence: 0,
            featureVector: [],
            timestamp: videoTime,
            description: nil
        )
        let location = location(from: frame)
        let measuredSpeed = frame?.currentSpeed ?? frame?.speed
        if let measuredSpeed, measuredSpeed >= 0 {
            lastSpeed = measuredSpeed
        }
        let speed = measuredSpeed ?? lastSpeed
        guard let event = sceneDetector.processFrame(prediction, location: location, speed: speed) else {
            if !forced {
                segments.updateCurrentSegment(
                    description: nil,
                    endTime: videoTime,
                    avgSpeed: average(speedSamples),
                    location: location
                )
            }
            return
        }
        split(at: event, location: location, recordingID: recordingID)
    }

    private func split(at event: SceneChangeEvent, location: CLLocation?, recordingID: UUID) {
        lock.lock()
        let videoPath = videoRelativePath
        let stillCurrent = self.recordingID == recordingID
        lock.unlock()
        guard stillCurrent else { return }
        guard let current = segments.currentSegment(in: recordingID) else { return }
        let context = RidingContext.make(
            date: Date(),
            averageSpeed: average(speedSamples) ?? 0,
            ascent: segmentAscent,
            descent: segmentDescent
        )
        let description = descriptions.generateWithTemplate(current, context: context)
        segments.finalizeSegment(current.id, endTime: event.timestamp, description: description, avgSpeed: average(speedSamples))
        speedSamples = []
        segmentAscent = 0
        segmentDescent = 0
        let next = segments.createSegment(
            for: recordingID,
            sceneType: event.newScene,
            videoPath: videoPath,
            startTime: event.timestamp,
            location: location,
            avgSpeed: nil,
            description: event.newScene.rawValue
        )
        lock.lock()
        segmentID = next.id
        lock.unlock()
    }

    private func closeOpenSegment(at endTime: TimeInterval, recordingID: UUID) {
        guard let current = segments.currentSegment(in: recordingID) else { return }
        let context = RidingContext.make(
            date: Date(),
            averageSpeed: average(speedSamples) ?? 0,
            ascent: segmentAscent,
            descent: segmentDescent
        )
        let description = descriptions.generateWithTemplate(current, context: context)
        segments.finalizeSegment(current.id, endTime: endTime, description: description, avgSpeed: average(speedSamples))
    }

    private func scheduleThumbnails(recordingID: UUID) {
        let items = segments.getSegments(for: recordingID)
        Task {
            for segment in items {
                _ = await segments.generateThumbnail(for: segment)
            }
            if let first = segments.getSegments(for: recordingID).first,
               let thumb = first.thumbnailPath,
               var ride = try? database.getRecording(id: recordingID) {
                ride.thumbnailPath = thumb
                try? database.updateRecording(ride)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .rideLibraryDidChange, object: recordingID)
            }
        }
    }

    private func noteAltitude(_ frame: SensorFrame?) {
        guard let altitude = frame?.altitude, let accuracy = frame?.verticalAccuracy, accuracy >= 0, accuracy < 30 else { return }
        if let lastAltitude {
            let delta = altitude - lastAltitude
            if delta > 1 {
                segmentAscent += delta
                rideAscent += delta
            } else if delta < -1 {
                segmentDescent -= delta
                rideDescent -= delta
            }
        }
        lastAltitude = altitude
    }

    private func location(from frame: SensorFrame?) -> CLLocation? {
        guard let latitude = frame?.latitude, let longitude = frame?.longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func average(_ samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    private func abort(_ recordingID: UUID) {
        lock.lock()
        let stillCurrent = self.recordingID == recordingID
        if stillCurrent {
            sessionToken = UUID()
            clearLocked()
        }
        lock.unlock()
        if stillCurrent {
            sensorCancellable?.cancel()
            sensorCancellable = nil
        }
        analysis.sync {}
        segments.discard(recordingID: recordingID)
        try? database.deleteRecording(id: recordingID)
        try? files.deleteRecording(recordingID)
    }

    private func resetAnalysisState() {
        lastIngestVideoTime = -1
        speedSamples = []
        segmentAscent = 0
        segmentDescent = 0
        rideAscent = 0
        rideDescent = 0
        lastAltitude = nil
        lastSpeed = nil
    }

    private func isSession(_ token: UUID, recordingID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionToken == token && self.recordingID == recordingID
    }

    private func clearSession() {
        sensorCancellable?.cancel()
        sensorCancellable = nil
        lock.lock()
        clearLocked()
        lock.unlock()
    }

    private func clearLocked() {
        recordingID = nil
        segmentID = nil
        startedAt = nil
        marks = []
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
        recordingStats: RecordingStatistics,
        videoPath: String
    ) throws -> RecordingMetadata {
        let metadata = RecordingMetadata(
            id: recordingID,
            segmentID: segmentID,
            startedAt: startedAt,
            endedAt: endedAt,
            videoFileName: videoPath,
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
            var ride = try database.getRecording(id: recordingID) ?? RideRecording(
                id: recordingID,
                startTime: startedAt.timeIntervalSince1970,
                endTime: nil,
                totalDistance: 0,
                avgSpeed: 0,
                maxSpeed: 0,
                totalDuration: 0,
                totalAscent: 0,
                totalDescent: 0,
                createdAt: startedAt,
                thumbnailPath: nil,
                videoPath: videoPath
            )
            ride.endTime = endedAt.timeIntervalSince1970
            ride.totalDistance = stats.totalDistance
            ride.avgSpeed = stats.averageSpeed
            ride.maxSpeed = stats.maxSpeed
            ride.totalDuration = recordingStats.duration
            ride.totalAscent = rideAscent
            ride.totalDescent = rideDescent
            ride.videoPath = videoPath
            if try database.getRecording(id: recordingID) == nil {
                try database.createRecording(ride)
            } else {
                try database.updateRecording(ride)
            }
        } catch {
            throw RecordingCoordinatorError.persistFailed(error.localizedDescription)
        }
        return metadata
    }
}
