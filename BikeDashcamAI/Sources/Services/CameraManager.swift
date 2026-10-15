import AVFoundation
import Photos
import UIKit

enum CameraError: LocalizedError {
    case permissionDenied
    case deviceUnavailable
    case sessionConfigurationFailed(String)
    case writerFailed(String)
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "相机权限被拒绝"
        case .deviceUnavailable: return "找不到后置相机"
        case .sessionConfigurationFailed(let message): return "相机配置失败: \(message)"
        case .writerFailed(let message): return "视频写入失败: \(message)"
        case .notRecording: return "当前没有正在进行的录制"
        }
    }
}

enum RecordingState {
    case idle, preparing, recording, paused, stopping
}

struct CaptureConfiguration {
    var width: Int = 0
    var height: Int = 0
    var frameRate: Int = 30
    var stabilization: Bool = false
    var hdrSupported: Bool = false
    var hdrEnabled: Bool = false
    var colorSpace: String = "sRGB"
    var bitratePreset: VideoEncoderConfiguration.BitratePreset = .standard
}

struct RecordingStatistics {
    var encodedFrames: Int = 0
    var droppedFrames: Int = 0
    var sampledFrames: Int = 0
    var fileBytes: Int64 = 0
    var duration: TimeInterval = 0
}

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didChangeState state: RecordingState)
    func cameraManager(_ manager: CameraManager, didFailWithError error: CameraError)
    func cameraManager(_ manager: CameraManager, didUpdateConfiguration configuration: CaptureConfiguration)
    func cameraManager(_ manager: CameraManager, didUpdateStatistics statistics: RecordingStatistics)
}

/// 后置相机采集。成片由 AVAssetWriter 封装为 HEVC MOV，每一帧都写入；
/// 另外按 3fps 抽取 224×224 画面，不丢掉成片帧。
final class CameraManager: NSObject {
    private(set) var captureSession: AVCaptureSession?
    private(set) var configuration = CaptureConfiguration()
    let frameExtractor = FrameExtractor()

    weak var delegate: CameraManagerDelegate?

    private let captureQueue = DispatchQueue(label: "com.bikedashcam.camera.capture")
    private let processingQueue = DispatchQueue(label: "com.bikedashcam.camera.process")
    private let stateLock = NSLock()
    private var state: RecordingState = .idle

    private var videoOutput: AVCaptureVideoDataOutput?
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var sampleInFlight = false
    private var lastSamplePTS = CMTime.invalid

    private var timebaseStart: CMTime?
    private var pauseBeganPTS: CMTime?
    private var accumulatedPause = CMTime.zero
    private var lastMediaPTS: CMTime?

    private var recordingStartedAt: Date?
    private var pauseBeganAt: Date?
    private var pausedAccumulated: TimeInterval = 0

    private var encodedFrameCount = 0
    private var droppedFrameCount = 0
    private var sampledFrameCount = 0
    private var statisticsTimer: DispatchSourceTimer?
    private var statisticsWanted = false
    private var activeFrameRate = 30
    private var startCompletion: ((Error?) -> Void)?
    private var stopCompletion: ((Result<URL, Error>) -> Void)?

    private let sampleInterval = CMTime(value: 1, timescale: 3)

    var recordingState: RecordingState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state
    }

    private(set) var lastStatistics = RecordingStatistics()

    var recordingDuration: TimeInterval {
        stateLock.lock()
        defer { stateLock.unlock() }
        return durationWhileLocked()
    }

    private func durationWhileLocked(now: Date = Date()) -> TimeInterval {
        guard let start = recordingStartedAt else { return 0 }
        let livePause = pauseBeganAt.map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(start) - pausedAccumulated - livePause)
    }

    func checkPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func setupSession() throws {
        guard captureSession == nil else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.deviceUnavailable
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.sessionConfigurationFailed("无法添加相机输入")
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            throw CameraError.sessionConfigurationFailed("无法添加视频输出")
        }
        session.addOutput(output)
        videoOutput = output

        let choice = try configure(device: device)
        if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematicExtended
            configuration.stabilization = true
        } else {
            configuration.stabilization = false
        }

        captureSession = session
        configuration.width = Int(choice.width)
        configuration.height = Int(choice.height)
        configuration.frameRate = choice.frameRate
        activeFrameRate = choice.frameRate
        configuration.hdrSupported = choice.hdrSupported
        configuration.hdrEnabled = false
        configuration.colorSpace = choice.colorSpace

        DispatchQueue.main.async {
            self.delegate?.cameraManager(self, didUpdateConfiguration: self.configuration)
        }
    }

    func startSession() {
        captureQueue.async {
            guard let session = self.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stopSession() {
        captureQueue.async {
            self.captureSession?.stopRunning()
        }
    }

    func setBitratePreset(_ preset: VideoEncoderConfiguration.BitratePreset) {
        configuration.bitratePreset = preset
        DispatchQueue.main.async {
            self.delegate?.cameraManager(self, didUpdateConfiguration: self.configuration)
        }
    }

    func startRecording(to url: URL, completion: ((Error?) -> Void)? = nil) {
        stateLock.lock()
        guard state == .idle else {
            stateLock.unlock()
            DispatchQueue.main.async {
                completion?(CameraError.writerFailed("录制已在进行"))
            }
            return
        }
        state = .preparing
        startCompletion = completion
        stateLock.unlock()
        publishState(.preparing)

        let begin = {
            let transform = self.videoTransform()
            self.captureQueue.async {
                self.startWriter(url: url, transform: transform)
            }
        }
        if Thread.isMainThread {
            begin()
        } else {
            DispatchQueue.main.async(execute: begin)
        }
    }

    private func startWriter(url: URL, transform: CGAffineTransform) {
        do {
            try prepareWriter(url: url, transform: transform)
            resetCounters()
            stateLock.lock()
            recordingStartedAt = Date()
            pauseBeganAt = nil
            pausedAccumulated = 0
            state = .recording
            stateLock.unlock()
            startStatisticsTimer()
            publishState(.recording)
            finishStart(nil)
        } catch {
            teardownWriter()
            stateLock.lock()
            state = .idle
            stateLock.unlock()
            publishState(.idle)
            let error = CameraError.writerFailed(error.localizedDescription)
            publishError(error)
            finishStart(error)
        }
    }

    private func finishStart(_ error: Error?) {
        let completion = startCompletion
        startCompletion = nil
        DispatchQueue.main.async {
            completion?(error)
        }
    }

    func pauseRecording() {
        stateLock.lock()
        guard state == .recording else {
            stateLock.unlock()
            return
        }
        state = .paused
        if pauseBeganAt == nil {
            pauseBeganAt = Date()
        }
        stateLock.unlock()
        publishState(.paused)
    }

    func resumeRecording() {
        stateLock.lock()
        guard state == .paused else {
            stateLock.unlock()
            return
        }
        if let began = pauseBeganAt {
            pausedAccumulated += Date().timeIntervalSince(began)
            pauseBeganAt = nil
        }
        state = .recording
        stateLock.unlock()
        publishState(.recording)
    }

    func stopRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        stateLock.lock()
        guard state == .recording || state == .paused else {
            stateLock.unlock()
            DispatchQueue.main.async {
                completion(.failure(CameraError.notRecording))
            }
            return
        }
        if let began = pauseBeganAt {
            pausedAccumulated += Date().timeIntervalSince(began)
            pauseBeganAt = nil
        }
        state = .stopping
        stateLock.unlock()
        publishState(.stopping)

        captureQueue.async {
            self.stopCompletion = completion
            self.videoWriterInput?.markAsFinished()
            guard let writer = self.assetWriter, let url = self.outputURL else {
                self.finishStop(.failure(CameraError.writerFailed("写入器不存在")))
                return
            }
            writer.finishWriting {
                self.stopStatisticsTimer()
                if let error = writer.error {
                    self.finishStop(.failure(CameraError.writerFailed(error.localizedDescription)))
                } else {
                    self.saveToPhotoLibrary(url)
                    self.finishStop(.success(url))
                }
            }
        }
    }

    func statisticsSnapshot() -> RecordingStatistics {
        stateLock.lock()
        let url = outputURL
        let encoded = encodedFrameCount
        let dropped = droppedFrameCount
        let sampled = sampledFrameCount
        let duration = durationWhileLocked()
        stateLock.unlock()
        let bytes = url.map { FileSystemManager.shared.fileSize(at: $0) } ?? 0
        return RecordingStatistics(
            encodedFrames: encoded,
            droppedFrames: dropped,
            sampledFrames: sampled,
            fileBytes: bytes,
            duration: duration
        )
    }

    private struct FormatChoice {
        var format: AVCaptureDevice.Format
        var frameRate: Int
        var width: Int32
        var height: Int32
        var hdrSupported: Bool
        var colorSpace: String
    }

    private func configure(device: AVCaptureDevice) throws -> FormatChoice {
        guard let choice = bestFormat(for: device) else {
            throw CameraError.sessionConfigurationFailed("没有可用的视频格式")
        }
        try device.lockForConfiguration()
        device.activeFormat = choice.format
        let duration = CMTime(value: 1, timescale: CMTimeScale(choice.frameRate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if choice.format.supportedColorSpaces.contains(.P3_D65) {
            device.activeColorSpace = .P3_D65
        }
        device.unlockForConfiguration()
        return choice
    }

    /// 优先 4K60，其次 4K，再退到最高像素。数据输出保持 8-bit，避免未验证的 HDR 10-bit 写盘失败。
    private func bestFormat(for device: AVCaptureDevice) -> FormatChoice? {
        var bestScore = Int.min
        var best: FormatChoice?
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let ranges = format.videoSupportedFrameRateRanges
            guard let maxRate = ranges.map(\.maxFrameRate).max(), maxRate >= 24 else { continue }
            let target = ranges.contains { $0.minFrameRate <= 60 && $0.maxFrameRate >= 60 } ? 60 : Int(maxRate.rounded(.down))
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)
            let pixels = width * height
            var score = pixels
            if width >= 3840 && height >= 2160 { score += 2_000_000_000 }
            if target >= 60 { score += 1_000_000_000 }
            if format.supportedColorSpaces.contains(.P3_D65) { score += 50 }
            guard score > bestScore else { continue }
            bestScore = score
            let colorSpace = format.supportedColorSpaces.contains(.P3_D65) ? "P3" : "sRGB"
            best = FormatChoice(
                format: format,
                frameRate: target,
                width: dimensions.width,
                height: dimensions.height,
                hdrSupported: format.isVideoHDRSupported,
                colorSpace: colorSpace
            )
        }
        return best
    }

    private func prepareWriter(url: URL, transform: CGAffineTransform) throws {
        teardownWriter()
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let bitrate = configuration.bitratePreset.bitrate
        let frameRate = max(activeFrameRate, 1)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: configuration.width,
            AVVideoHeightKey: configuration.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: frameRate * 2,
                AVVideoAllowFrameReorderingKey: true
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        input.transform = transform
        guard writer.canAdd(input) else {
            throw CameraError.writerFailed("无法添加视频输入")
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw CameraError.writerFailed(writer.error?.localizedDescription ?? "startWriting 失败")
        }
        assetWriter = writer
        videoWriterInput = input
        setOutputURL(url)
        sessionStarted = false
        timebaseStart = nil
        pauseBeganPTS = nil
        accumulatedPause = .zero
        lastMediaPTS = nil
        lastSamplePTS = .invalid
        sampleInFlight = false
    }

    private func videoTransform() -> CGAffineTransform {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation
        switch orientation {
        case .landscapeLeft:
            return .identity
        case .landscapeRight:
            return CGAffineTransform(rotationAngle: .pi)
        case .portraitUpsideDown:
            return CGAffineTransform(rotationAngle: -.pi / 2)
        default:
            return CGAffineTransform(rotationAngle: .pi / 2)
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer, state current: RecordingState) {
        guard let input = videoWriterInput, let writer = assetWriter, writer.status == .writing else {
            dropFrame()
            return
        }
        if current == .paused {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if pauseBeganPTS == nil { pauseBeganPTS = pts }
            return
        }
        guard input.isReadyForMoreMediaData else {
            dropFrame()
            return
        }

        let timed = retimed(sampleBuffer)
        if !sessionStarted {
            writer.startSession(atSourceTime: .zero)
            sessionStarted = true
        }
        if input.append(timed) {
            stateLock.lock()
            encodedFrameCount += 1
            stateLock.unlock()
        } else {
            dropFrame()
        }
    }

    private func retimed(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if timebaseStart == nil { timebaseStart = pts }
        if let began = pauseBeganPTS {
            accumulatedPause = CMTimeAdd(accumulatedPause, CMTimeSubtract(pts, began))
            pauseBeganPTS = nil
        }
        let start = timebaseStart ?? pts
        var mediaPTS = CMTimeSubtract(CMTimeSubtract(pts, start), accumulatedPause)
        if let lastMediaPTS, CMTimeCompare(mediaPTS, lastMediaPTS) <= 0 {
            let step = CMTime(value: 1, timescale: CMTimeScale(max(activeFrameRate, 1)))
            mediaPTS = CMTimeAdd(lastMediaPTS, step)
        }
        lastMediaPTS = mediaPTS
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: mediaPTS,
            decodeTimeStamp: .invalid
        )
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &copy
        )
        if status == noErr, let copy { return copy }
        return sampleBuffer
    }

    private func sampleIfDue(_ sampleBuffer: CMSampleBuffer) {
        guard !sampleInFlight else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastSamplePTS.isValid {
            let elapsed = CMTimeSubtract(pts, lastSamplePTS)
            guard CMTimeCompare(elapsed, sampleInterval) >= 0 else { return }
        }
        lastSamplePTS = pts
        sampleInFlight = true
        processingQueue.async { [weak self, sampleBuffer] in
            let rendered = self?.frameExtractor.render(sampleBuffer: sampleBuffer) ?? false
            self?.captureQueue.async {
                guard let self else { return }
                self.sampleInFlight = false
                if rendered {
                    self.stateLock.lock()
                    self.sampledFrameCount += 1
                    self.stateLock.unlock()
                }
            }
        }
    }

    private func dropFrame() {
        stateLock.lock()
        droppedFrameCount += 1
        stateLock.unlock()
    }

    private func resetCounters() {
        stateLock.lock()
        encodedFrameCount = 0
        droppedFrameCount = 0
        sampledFrameCount = 0
        stateLock.unlock()
    }

    private func startStatisticsTimer() {
        stateLock.lock()
        statisticsWanted = true
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let wanted = self.statisticsWanted
            self.stateLock.unlock()
            guard wanted else { return }
            self.statisticsTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in
                self?.publishStatistics()
            }
            timer.resume()
            self.statisticsTimer = timer
        }
    }

    private func stopStatisticsTimer() {
        stateLock.lock()
        statisticsWanted = false
        stateLock.unlock()
        let stop = {
            self.statisticsTimer?.cancel()
            self.statisticsTimer = nil
        }
        if Thread.isMainThread {
            stop()
        } else {
            DispatchQueue.main.async(execute: stop)
        }
    }

    private func publishStatistics() {
        let stats = statisticsSnapshot()
        delegate?.cameraManager(self, didUpdateStatistics: stats)
    }

    private func saveToPhotoLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }

    private func finishStop(_ result: Result<URL, Error>) {
        let stats = statisticsSnapshot()
        let completion = stopCompletion
        stopCompletion = nil
        teardownWriter()
        stateLock.lock()
        state = .idle
        recordingStartedAt = nil
        stateLock.unlock()
        DispatchQueue.main.async {
            self.lastStatistics = stats
            self.delegate?.cameraManager(self, didChangeState: .idle)
            self.delegate?.cameraManager(self, didUpdateStatistics: stats)
            completion?(result)
        }
    }

    private func teardownWriter() {
        videoWriterInput = nil
        assetWriter = nil
        setOutputURL(nil)
        sessionStarted = false
    }

    private func setOutputURL(_ url: URL?) {
        stateLock.lock()
        outputURL = url
        stateLock.unlock()
    }

    private func publishState(_ state: RecordingState) {
        DispatchQueue.main.async {
            self.delegate?.cameraManager(self, didChangeState: state)
        }
    }

    private func publishError(_ error: CameraError) {
        DispatchQueue.main.async {
            self.delegate?.cameraManager(self, didFailWithError: error)
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let current = recordingState
        guard current == .recording || current == .paused else { return }
        if current == .recording {
            sampleIfDue(sampleBuffer)
        }
        append(sampleBuffer, state: current)
    }
}
