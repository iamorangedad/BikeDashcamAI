import CoreLocation
import CoreMedia
import UIKit

/// 片段是成片上的时间区间，共用同一次骑行的视频文件。
final class SegmentManager {
    static let shared = SegmentManager()

    private let queue = DispatchQueue(label: "com.bikedashcam.segments")
    private var sessionSegments: [UUID: [SceneSegment]] = [:]
    private var currentSegmentID: UUID?
    private let database: DatabaseManager
    private let files: FileSystemManager

    init(database: DatabaseManager = .shared, files: FileSystemManager = .shared) {
        self.database = database
        self.files = files
    }

    func createSegment(
        for recording: UUID,
        sceneType: SceneType,
        videoPath: String,
        startTime: TimeInterval,
        location: CLLocation?,
        avgSpeed: Double?,
        description: String
    ) -> SceneSegment {
        queue.sync {
            let segment = SceneSegment(
                id: UUID(),
                recordingID: recording,
                startTime: startTime,
                endTime: startTime,
                sceneType: sceneType,
                description: description,
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                avgSpeed: avgSpeed,
                thumbnailPath: nil,
                videoPath: videoPath,
                isCompressed: false,
                compressionRatio: nil,
                createdAt: Date()
            )
            var list = sessionSegments[recording] ?? []
            list.append(segment)
            sessionSegments[recording] = list
            currentSegmentID = segment.id
            try? database.createSegment(segment)
            return segment
        }
    }

    func updateCurrentSegment(description: String?, endTime: TimeInterval?, avgSpeed: Double?, location: CLLocation?) {
        queue.sync {
            guard let currentSegmentID, var segment = find(currentSegmentID) else { return }
            if let description {
                segment.description = description
            }
            if let endTime {
                segment.endTime = endTime
            }
            if let avgSpeed {
                segment.avgSpeed = avgSpeed
            }
            if let location {
                segment.latitude = location.coordinate.latitude
                segment.longitude = location.coordinate.longitude
            }
            replace(segment)
            try? database.updateSegment(segment)
        }
    }

    func finalizeSegment(_ segmentID: UUID, endTime: TimeInterval, description: String?, avgSpeed: Double?) {
        queue.sync {
            guard var segment = find(segmentID) else { return }
            segment.endTime = max(endTime, segment.startTime)
            if let description {
                segment.description = description
            }
            if let avgSpeed {
                segment.avgSpeed = avgSpeed
            }
            replace(segment)
            try? database.updateSegment(segment)
        }
    }

    func currentSegment(in recordingID: UUID) -> SceneSegment? {
        queue.sync {
            guard let currentSegmentID else { return sessionSegments[recordingID]?.last }
            return find(currentSegmentID)
        }
    }

    func discard(recordingID: UUID) {
        queue.sync {
            sessionSegments[recordingID] = nil
            currentSegmentID = nil
        }
    }

    func getSegments(for recordingID: UUID) -> [SceneSegment] {
        if let cached = queue.sync(execute: { sessionSegments[recordingID] }), !cached.isEmpty {
            return cached
        }
        let stored = (try? database.getSegments(forRecording: recordingID)) ?? []
        queue.sync {
            sessionSegments[recordingID] = stored
        }
        return stored
    }

    func split(_ segment: SceneSegment, at time: TimeInterval) -> SceneSegment? {
        queue.sync {
            guard let end = segment.endTime, time > segment.startTime + 1, time < end - 1 else { return nil }
            guard var original = find(segment.id) else { return nil }
            original.endTime = time
            replace(original)
            try? database.updateSegment(original)
            let created = SceneSegment(
                id: UUID(),
                recordingID: original.recordingID,
                startTime: time,
                endTime: end,
                sceneType: original.sceneType,
                description: original.description,
                latitude: original.latitude,
                longitude: original.longitude,
                avgSpeed: original.avgSpeed,
                thumbnailPath: nil,
                videoPath: original.videoPath,
                isCompressed: false,
                compressionRatio: nil,
                createdAt: Date()
            )
            var list = sessionSegments[original.recordingID] ?? []
            if let index = list.firstIndex(where: { $0.id == original.id }) {
                list.insert(created, at: index + 1)
            } else {
                list.append(created)
            }
            sessionSegments[original.recordingID] = list.sorted { $0.startTime < $1.startTime }
            try? database.createSegment(created)
            return created
        }
    }

    func merge(_ first: SceneSegment, with second: SceneSegment) -> SceneSegment? {
        queue.sync {
            guard first.recordingID == second.recordingID else { return nil }
            guard var kept = find(first.id) else { return nil }
            kept.endTime = second.endTime ?? kept.endTime
            replace(kept)
            try? database.updateSegment(kept)
            sessionSegments[first.recordingID]?.removeAll { $0.id == second.id }
            try? database.deleteSegment(id: second.id)
            return kept
        }
    }

    func deleteSegment(_ segment: SceneSegment) {
        queue.sync {
            sessionSegments[segment.recordingID]?.removeAll { $0.id == segment.id }
            try? database.deleteSegment(id: segment.id)
            if let path = segment.thumbnailPath {
                let url = files.recordingRoot(segment.recordingID).appendingPathComponent(path)
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func updateDescription(_ segmentID: UUID, description: String) -> SceneSegment? {
        queue.sync {
            guard var segment = find(segmentID) else { return nil }
            segment.description = description
            replace(segment)
            try? database.updateSegment(segment)
            return segment
        }
    }

    func updateThumbnailPath(_ segmentID: UUID, path: String) {
        queue.sync {
            guard var segment = find(segmentID) else { return }
            segment.thumbnailPath = path
            replace(segment)
            try? database.updateSegment(segment)
        }
    }

    func generateThumbnail(for segment: SceneSegment) async -> UIImage? {
        let url = files.recordingRoot(segment.recordingID).appendingPathComponent(segment.videoPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let midpoint = CMTime(seconds: segment.startTime + segment.duration / 2, preferredTimescale: 600)
        guard let image = try? await ThumbnailGenerator.shared.generateThumbnail(from: url, at: midpoint) else { return nil }
        if let relative = try? files.saveThumbnail(image, for: segment.id, in: segment.recordingID) {
            updateThumbnailPath(segment.id, path: relative)
            ThumbnailGenerator.shared.store(image, for: segment.id)
        }
        return image
    }

    private func find(_ id: UUID) -> SceneSegment? {
        for list in sessionSegments.values {
            if let segment = list.first(where: { $0.id == id }) {
                return segment
            }
        }
        return nil
    }

    private func replace(_ segment: SceneSegment) {
        guard var list = sessionSegments[segment.recordingID] else {
            sessionSegments[segment.recordingID] = [segment]
            return
        }
        if let index = list.firstIndex(where: { $0.id == segment.id }) {
            list[index] = segment
        } else {
            list.append(segment)
        }
        sessionSegments[segment.recordingID] = list
    }
}
