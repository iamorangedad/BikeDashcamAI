import Foundation
import VideoToolbox
import CoreMedia

struct VideoEncoderConfiguration {
    enum BitratePreset: String, CaseIterable {
        case highQuality = "high_quality"
        case standard = "standard"
        case powerSaving = "power_saving"
        case compression = "compression"

        var bitrate: Int {
            switch self {
            case .highQuality: return 35_000_000
            case .standard: return 25_000_000
            case .powerSaving: return 15_000_000
            case .compression: return 10_000_000
            }
        }

        var description: String {
            switch self {
            case .highQuality: return "高质量 (35Mbps)"
            case .standard: return "标准 (25Mbps)"
            case .powerSaving: return "省电 (15Mbps)"
            case .compression: return "压缩 (10Mbps)"
            }
        }
    }

    var preset: BitratePreset = .standard
    var effectiveBitrate: Int { preset.bitrate }

    static var `default`: VideoEncoderConfiguration { VideoEncoderConfiguration() }
}

struct EncodingStatistics {
    var currentBitrate: Double = 0
    var averageBitrate: Double = 0
    var encodedFrameCount: Int = 0
    var encodedBytes: Int64 = 0
    var encodingDuration: TimeInterval = 0
    var droppedFrameCount: Int = 0

    var fps: Double {
        guard encodingDuration > 0 else { return 0 }
        return Double(encodedFrameCount) / encodingDuration
    }
}

enum VideoEncoderError: LocalizedError {
    case notInitialized
    case creationFailed(OSStatus)
    case encodingFailed(OSStatus)
    case retryLimitExceeded

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "编码器未初始化"
        case .creationFailed(let status): return "创建失败: \(status)"
        case .encodingFailed(let status): return "编码失败: \(status)"
        case .retryLimitExceeded: return "重试次数超限"
        }
    }
}

enum EncodingState: String {
    case idle = "空闲"
    case configuring = "配置中"
    case encoding = "编码中"
    case paused = "已暂停"
    case stopping = "停止中"
    case error = "错误"
}

/// VideoToolbox HEVC 编码器。成片封装在 CameraManager 的 AVAssetWriter 里，
/// 这里只输出编码后的样本，不再把裸码流写成 .mov。
final class VideoEncoder {
    private(set) var configuration: VideoEncoderConfiguration
    private(set) var state: EncodingState = .idle
    private var compressionSession: VTCompressionSession?
    private let encodingQueue = DispatchQueue(label: "com.bikedashcam.videoencoder")
    private(set) var statistics = EncodingStatistics()
    private var retryCount = 0
    private let maxRetryCount = 3
    private var keyFrameCounter = 0
    private var encodingStartTime: Date?
    private var useMain10 = true
    private var needsRebuild = false

    var frameEncodedHandler: ((CMSampleBuffer) -> Void)?
    var errorHandler: ((Error) -> Void)?
    var statisticsHandler: ((EncodingStatistics) -> Void)?

    init(configuration: VideoEncoderConfiguration = .default) {
        self.configuration = configuration
    }

    deinit {
        invalidateSession()
    }

    func configure() throws {
        state = .configuring
        invalidateSession()
        do {
            try makeSession(main10: true)
            useMain10 = true
        } catch {
            try makeSession(main10: false)
            useMain10 = false
        }
        retryCount = 0
        state = .idle
    }

    func startEncoding() throws {
        if compressionSession == nil {
            try configure()
        }
        guard compressionSession != nil else { throw VideoEncoderError.notInitialized }
        guard state != .encoding else { return }
        state = .encoding
        statistics = EncodingStatistics()
        encodingStartTime = Date()
        keyFrameCounter = 0
    }

    func stopEncoding() {
        guard state == .encoding || state == .paused else { return }
        state = .stopping
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        }
        state = .idle
    }

    func pauseEncoding() {
        guard state == .encoding else { return }
        state = .paused
    }

    func resumeEncoding() {
        guard state == .paused else { return }
        state = .encoding
    }

    func encodeFrame(_ sampleBuffer: CMSampleBuffer) {
        if needsRebuild {
            needsRebuild = false
            try? makeSession(main10: useMain10)
        }
        guard state == .encoding, let session = compressionSession else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let forceKeyFrame = keyFrameCounter >= 120
        let sourcePTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let presentationTimeStamp = sourcePTS.isValid ? sourcePTS : CMTime(value: CMTimeValue(statistics.encodedFrameCount), timescale: 600)
        let properties: CFDictionary? = forceKeyFrame
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            : nil
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: CMSampleBufferGetDuration(sampleBuffer),
            frameProperties: properties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        if status != noErr {
            noteEncodingFailure(status)
        }
        keyFrameCounter = forceKeyFrame ? 0 : keyFrameCounter + 1
    }

    func switchPreset(_ preset: VideoEncoderConfiguration.BitratePreset) {
        configuration.preset = preset
        guard let session = compressionSession else { return }
        let bitrate = NSNumber(value: preset.bitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFTypeRef)
    }

    func reset() {
        stopEncoding()
        invalidateSession()
        try? configure()
    }

    private func makeSession(main10: Bool) throws {
        invalidateSession()
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 3840,
            height: 2160,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else {
            throw VideoEncoderError.creationFailed(status)
        }
        compressionSession = session
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        let profile = main10 ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: configuration.effectiveBitrate) as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 2) as CFTypeRef)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 60) as CFTypeRef)
        let prepare = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepare == noErr else {
            invalidateSession()
            throw VideoEncoderError.creationFailed(prepare)
        }
    }

    fileprivate func noteEncodingFailure(_ status: OSStatus) {
        encodingQueue.async { [weak self] in
            guard let self else { return }
            self.retryCount += 1
            if self.retryCount > self.maxRetryCount {
                self.state = .error
                self.needsRebuild = false
                DispatchQueue.main.async {
                    self.errorHandler?(VideoEncoderError.retryLimitExceeded)
                }
                return
            }
            self.needsRebuild = true
            DispatchQueue.main.async {
                self.errorHandler?(VideoEncoderError.encodingFailed(status))
            }
        }
    }

    fileprivate func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        encodingQueue.async { [weak self] in
            guard let self else { return }
            if infoFlags.contains(.frameDropped) {
                self.statistics.droppedFrameCount += 1
            }
            if let buffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                self.statistics.encodedBytes += Int64(CMBlockBufferGetDataLength(buffer))
            }
            self.statistics.encodedFrameCount += 1
            if let start = self.encodingStartTime {
                self.statistics.encodingDuration = Date().timeIntervalSince(start)
            }
            if self.statistics.encodingDuration > 0 {
                self.statistics.averageBitrate = Double(self.statistics.encodedBytes) * 8 / self.statistics.encodingDuration
                self.statistics.currentBitrate = self.statistics.averageBitrate
            }
            let stats = self.statistics
            DispatchQueue.main.async {
                self.frameEncodedHandler?(sampleBuffer)
                self.statisticsHandler?(stats)
            }
        }
    }

    private func invalidateSession() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
}

private func encoderOutputCallback(
    refcon: UnsafeMutableRawPointer?,
    sourceFrameRefcon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard let refcon else { return }
    let encoder = Unmanaged<VideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
    if status != noErr {
        encoder.noteEncodingFailure(status)
        return
    }
    guard let sampleBuffer else { return }
    encoder.handleEncodedFrame(sampleBuffer, infoFlags: infoFlags)
}
