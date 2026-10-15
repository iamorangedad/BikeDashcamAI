import AVFoundation
import UIKit

final class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 80
    }

    func generateThumbnail(
        from videoURL: URL,
        at time: CMTime? = nil,
        size: CGSize = CGSize(width: 320, height: 180)
    ) async throws -> UIImage {
        let key = "\(videoURL.path)#\(time?.seconds ?? -1)#\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        let midpoint = duration.seconds.isFinite ? max(0, duration.seconds / 2) : 0
        let target = time ?? CMTime(seconds: midpoint, preferredTimescale: 600)
        let result = try await generator.image(at: target)
        let image = UIImage(cgImage: result.image)
        cache.setObject(image, forKey: key)
        return image
    }

    func generateThumbnails(for segments: [SceneSegment], videoURL: URL) async -> [UUID: UIImage] {
        var images: [UUID: UIImage] = [:]
        for segment in segments {
            let midpoint = segment.startTime + segment.duration / 2
            let time = CMTime(seconds: midpoint, preferredTimescale: 600)
            if let image = try? await generateThumbnail(from: videoURL, at: time) {
                images[segment.id] = image
                cache.setObject(image, forKey: segment.id.uuidString as NSString)
            }
        }
        return images
    }

    func cachedThumbnail(for segmentID: UUID) -> UIImage? {
        cache.object(forKey: segmentID.uuidString as NSString)
    }

    func store(_ image: UIImage, for segmentID: UUID) {
        cache.setObject(image, forKey: segmentID.uuidString as NSString)
    }

    func clearCache() {
        cache.removeAllObjects()
    }
}
