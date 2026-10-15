import CoreImage
import CoreMedia
import CoreVideo

/// 从录制流中按固定间隔取出一帧，缩放到 224×224，供后续模型使用。
/// 渲染在调用方队列上同步完成，避免像素缓冲在异步之后被复用。
final class FrameExtractor {
    private let context = CIContext()
    private(set) var renderedCount = 0

    var onImage: ((CGImage, CMTime) -> Void)?

    func render(sampleBuffer: CMSampleBuffer) -> Bool {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return false }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = source.extent
        guard extent.width > 1, extent.height > 1 else { return false }

        let side: CGFloat = 224
        let scale = max(side / extent.width, side / extent.height)
        let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaled.extent
        let crop = CGRect(
            x: scaledExtent.midX - side / 2,
            y: scaledExtent.midY - side / 2,
            width: side,
            height: side
        )

        return autoreleasepool {
            guard let image = context.createCGImage(scaled, from: crop) else { return false }
            renderedCount += 1
            onImage?(image, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            return true
        }
    }
}
