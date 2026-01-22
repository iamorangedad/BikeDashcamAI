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
    
    static var `default`: VideoEncoderConfiguration {
        VideoEncoderConfiguration()
    }
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
    case pausing = "暂停中"
    case paused = "已暂停"
    case stopping = "停止中"
    case error = "错误"
}

final class VideoEncoder {
    private(set) var configuration: VideoEncoderConfiguration
    private(set) var state: EncodingState = .idle
    private var compressionSession: VTCompressionSession?
    private var outputFileURL: URL?
    private var outputFileHandle: FileHandle?
    private let encodingQueue = DispatchQueue(label: "com.bikedashcam.videoencoder")
    private(set) var statistics = EncodingStatistics()
    private var statisticsTimer: Timer?
    private var retryCount: Int = 0
    private let maxRetryCount: Int = 3
    private var keyFrameCounter: Int = 0
    private var frameSequenceNumber: Int64 = 0
    private var encodingStartTime: Date?
    
    var stateUpdateHandler: ((EncodingState) -> Void)?
    var frameEncodedHandler: ((Data, CMTime, Bool) -> Void)?
    var errorHandler: ((Error) -> Void)?
    var statisticsHandler: ((EncodingStatistics) -> Void)?
    var completionHandler: ((URL?, Error?) -> Void)?
    
    init(configuration: VideoEncoderConfiguration = .default) {
        self.configuration = configuration
    }
    
    deinit {
        stopEncoding()
        cleanup()
    }
    
    func configure() throws {
        state = .configuring
        cleanup()
        
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: 3840,
            height: 2160,
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionSessionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let compressionSession = session else {
            state = .idle
            throw VideoEncoderError.creationFailed(status)
        }
        
        self.compressionSession = compressionSession
        self.retryCount = 0
        
        try configureCompressionSession()
        prepareOutputFile()
        
        state = .idle
    }
    
    private func configureCompressionSession() throws {
        guard let session = compressionSession else { return }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel)
        
        let bitrate = NSNumber(value: configuration.effectiveBitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFTypeRef)
        
        let maxKeyFrameInterval = NSNumber(value: 120)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxKeyFrameInterval as CFTypeRef)
        
        let status = VTCompressionSessionPrepareToEncodeFrames(session)
        guard status == noErr else {
            throw VideoEncoderError.creationFailed(status)
        }
    }
    
    private func prepareOutputFile() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).mp4"
        outputFileURL = documentsPath.appendingPathComponent(fileName)
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: outputFileURL!.path) {
            try? fileManager.removeItem(at: outputFileURL!)
        }
        
        fileManager.createFile(atPath: outputFileURL!.path, contents: nil, attributes: nil)
        
        do {
            outputFileHandle = try FileHandle(forWritingTo: outputFileURL!)
        } catch {
            print("文件创建失败: \(error)")
        }
    }
    
    func startEncoding() throws {
        guard compressionSession != nil else {
            throw VideoEncoderError.notInitialized
        }
        
        if state == .encoding { return }
        
        state = .encoding
        statistics = EncodingStatistics()
        encodingStartTime = Date()
        keyFrameCounter = 0
        frameSequenceNumber = 0
        
        startStatisticsTimer()
    }
    
    func stopEncoding() {
        guard state == .encoding || state == .paused else { return }
        
        state = .stopping
        stopStatisticsTimer()
        
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finalizeEncoding()
        }
    }
    
    func pauseEncoding() {
        guard state == .encoding else { return }
        state = .paused
    }
    
    func resumeEncoding() {
        guard state == .paused else { return }
        state = .encoding
    }
    
    func encodeFrame(_ sampleBuffer: CMSampleBuffer, isKeyFrame: Bool = false) {
        guard state == .encoding, let session = compressionSession else { return }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        frameSequenceNumber += 1
        let forceKeyFrame = isKeyFrame || keyFrameCounter >= 120
        let presentationTimeStamp = CMTimeMake(value: frameSequenceNumber, timescale: 600)
        
        var callbackFlags = VTEncodeInfoFlags()
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimeStamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &callbackFlags
        )
        
        if status != noErr {
            handleEncodingError(status)
        }
        
        keyFrameCounter = forceKeyFrame ? 0 : keyFrameCounter + 1
    }
    
    func switchPreset(_ preset: VideoEncoderConfiguration.BitratePreset) {
        configuration.preset = preset
        
        guard let session = compressionSession else { return }
        let bitrate = NSNumber(value: preset.bitrate)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFTypeRef)
    }
    
    private let compressionSessionCallback: VTCompressionOutputCallback = { (
        refCon: UnsafeMutableRawPointer?,
        sourceFrameRefcon: UnsafeMutableRawPointer?,
        status: OSStatus,
        infoFlags: VTEncodeInfoFlags,
        sampleBuffer: CMSampleBuffer?
    ) in
        guard let refCon = refCon else { return }
        let encoder = Unmanaged<VideoEncoder>.fromOpaque(refCon).takeUnretainedValue()
        
        if status != noErr {
            encoder.handleEncodingError(status)
            return
        }
        
        guard let buffer = sampleBuffer else { return }
        encoder.handleEncodedFrame(buffer, infoFlags: infoFlags)
    }
    
    private func handleEncodedFrame(_ sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        encodingQueue.async { [weak self] in
            guard let self = self else { return }
            
            if infoFlags.contains(.frameDropped) {
                DispatchQueue.main.async {
                    self.statistics.droppedFrameCount += 1
                }
            }
            
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
            
            var lengthAtOffset: Int = 0
            var totalLength: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            
            let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
            
            guard status == kCMBlockBufferNoErr, let data = dataPointer else { return }
            
            let encodedData = Data(bytes: data, count: totalLength)
            
            self.updateStatistics(with: encodedData.count)
            self.writeToFile(encodedData)
            
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let isKeyFrame = !infoFlags.contains(.frameDropped)
            
            DispatchQueue.main.async {
                self.frameEncodedHandler?(encodedData, timestamp, isKeyFrame)
            }
        }
    }
    
    private func handleEncodingError(_ status: OSStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let error = VideoEncoderError.encodingFailed(status)
            
            if self.retryCount < self.maxRetryCount {
                self.retryCount += 1
                do {
                    try self.configure()
                    try self.startEncoding()
                } catch {
                    self.errorHandler?(error)
                    self.state = .idle
                }
            } else {
                self.errorHandler?(VideoEncoderError.retryLimitExceeded)
                self.state = .idle
                self.stopEncoding()
            }
        }
    }
    
    private func writeToFile(_ data: Data) {
        guard let handle = outputFileHandle else { return }
        try? handle.write(contentsOf: data)
    }
    
    private func startStatisticsTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statisticsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateStatisticsDisplay()
            }
        }
    }
    
    private func stopStatisticsTimer() {
        statisticsTimer?.invalidate()
        statisticsTimer = nil
    }
    
    private func updateStatistics(with byteCount: Int) {
        statistics.encodedFrameCount += 1
        statistics.encodedBytes += Int64(byteCount)
        
        if let startTime = encodingStartTime {
            statistics.encodingDuration = Date().timeIntervalSince(startTime)
        }
        
        if statistics.encodingDuration > 0 {
            statistics.averageBitrate = Double(statistics.encodedBytes) * 8 / statistics.encodingDuration
        }
    }
    
    private func updateStatisticsDisplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statisticsHandler?(self.statistics)
        }
    }
    
    private func finalizeEncoding() {
        outputFileHandle?.closeFile()
        outputFileHandle = nil
        
        if let url = outputFileURL {
            completionHandler?(url, nil)
        }
        
        state = .idle
        outputFileURL = nil
    }
    
    private func cleanup() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        
        outputFileHandle?.closeFile()
        outputFileHandle = nil
        stopStatisticsTimer()
        statistics = EncodingStatistics()
    }
    
    func reset() {
        stopEncoding()
        cleanup()
        
        do {
            try configure()
        } catch {
            state = .idle
        }
    }
    
    func getOutputFileURL() -> URL? {
        return outputFileURL
    }
}
