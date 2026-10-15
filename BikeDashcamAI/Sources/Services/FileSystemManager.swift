import Foundation
import UIKit

/// 按骑行记录组织视频、缩略图和元数据目录。
final class FileSystemManager {
    static let shared = FileSystemManager()

    let documentsURL: URL
    let recordingsURL: URL
    let tempURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        documentsURL = documents
        recordingsURL = documents.appendingPathComponent("Recordings", isDirectory: true)
        tempURL = documents.appendingPathComponent("Temp", isDirectory: true)
    }

    func createRecordingDirectory(for recordingID: UUID) throws -> URL {
        let root = recordingRoot(recordingID)
        for name in ["segments", "thumbnails", "bookmarks"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    func recordingRoot(_ recordingID: UUID) -> URL {
        recordingsURL.appendingPathComponent(recordingID.uuidString, isDirectory: true)
    }

    func segmentVideoURL(recordingID: UUID, segmentID: UUID) -> URL {
        recordingRoot(recordingID)
            .appendingPathComponent("segments", isDirectory: true)
            .appendingPathComponent("\(segmentID.uuidString).mov")
    }

    func metadataURL(recordingID: UUID) -> URL {
        recordingRoot(recordingID).appendingPathComponent("metadata.json")
    }

    func sensorsURL(recordingID: UUID) -> URL {
        recordingRoot(recordingID).appendingPathComponent("sensors.json")
    }

    func thumbnailURL(recordingID: UUID, segmentID: UUID) -> URL {
        recordingRoot(recordingID)
            .appendingPathComponent("thumbnails", isDirectory: true)
            .appendingPathComponent("\(segmentID.uuidString).jpg")
    }

    func getSegmentDirectory(for recordingID: UUID) throws -> URL {
        let url = recordingRoot(recordingID).appendingPathComponent("segments", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func getThumbnailDirectory(for recordingID: UUID) throws -> URL {
        let url = recordingRoot(recordingID).appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func saveThumbnail(_ image: UIImage, for segmentID: UUID, in recordingID: UUID) throws -> String {
        _ = try getThumbnailDirectory(for: recordingID)
        let url = thumbnailURL(recordingID: recordingID, segmentID: segmentID)
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return "thumbnails/\(segmentID.uuidString).jpg"
    }

    func getThumbnailURL(segmentID: UUID, recordingID: UUID) -> URL? {
        let url = thumbnailURL(recordingID: recordingID, segmentID: segmentID)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func deleteSegmentFiles(_ segmentID: UUID, in recordingID: UUID) throws {
        let video = segmentVideoURL(recordingID: recordingID, segmentID: segmentID)
        let thumbnail = thumbnailURL(recordingID: recordingID, segmentID: segmentID)
        if FileManager.default.fileExists(atPath: video.path) {
            try FileManager.default.removeItem(at: video)
        }
        if FileManager.default.fileExists(atPath: thumbnail.path) {
            try FileManager.default.removeItem(at: thumbnail)
        }
    }

    func calculateStorageUsage(for recordingID: UUID) throws -> Int64 {
        try directorySize(recordingRoot(recordingID))
    }

    func getTotalStorageUsage() throws -> Int64 {
        try directorySize(recordingsURL)
    }

    func deleteRecording(_ recordingID: UUID) throws {
        let root = recordingRoot(recordingID)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    func availableCapacity() -> Int64 {
        let values = try? documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func directorySize(_ url: URL) throws -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(at: file)
        }
        return total
    }

    func cleanupTempFiles() throws {
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    }
}
