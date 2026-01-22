import AVFoundation
import UIKit
import Photos

enum SimpleCameraError: Error {
    case permissionDenied
    case sessionFailed(Error)
    case writerFailed(Error)
    case encoderFailed(Error)
    case highFrameRateUnavailable
    case hdrUnavailable
    case deviceUnavailable
    case unknown
}

enum SimpleRecordingState {
    case idle, recording, paused
}

protocol SimpleCameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: SimpleCameraManager, didChangeState state: SimpleRecordingState)
    func cameraManager(_ manager: SimpleCameraManager, didFailWithError error: SimpleCameraError)
    func cameraManager(_ manager: SimpleCameraManager, didUpdateFrameCount current: Int, total: Int)
    func cameraManager(_ manager: SimpleCameraManager, didUpdateRecordingInfo info: [String: Any])
    func cameraManager(_ manager: SimpleCameraManager, didUpdateStatistics stats: [String: Any])
}

final class SimpleCameraManager: NSObject {
    private(set) var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoInput: AVCaptureDeviceInput?
    
    private var assetWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    
    private(set) var recordingState: SimpleRecordingState = .idle
    weak var delegate: SimpleCameraManagerDelegate?
    
    private let captureQueue = DispatchQueue(label: "com.simplecamera.capture")
    private let processingQueue = DispatchQueue(label: "com.simplecamera.processing")
    
    private var frameCount = 0
    private var savedFrameCount = 0
    private let framesToSkip = 9
    
    private var outputURL: URL?
    
    private var videoDevice: AVCaptureDevice?
    private var isHDREnabled = false
    private var isHighFrameRateEnabled = false
    
    private(set) var currentResolution: String = "4K"
    private(set) var currentFrameRate: Int = 60
    private(set) var isStabilizationEnabled: Bool = true
    private(set) var isHDRSupported: Bool = false
    private(set) var currentBitratePreset: VideoEncoderConfiguration.BitratePreset = .standard
    
    private var recordingStartTime: CMTime?
    private var encodedBytes: Int64 = 0
    private var encodedFrameCount: Int = 0
    private var droppedFrameCount: Int = 0
    private var encodingStartTime: Date?
    
    func checkPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
    
    func getSupportedCapabilities() -> [String: Any] {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return [:]
        }
        
        var capabilities: [String: Any] = [:]
        
        let formats = device.formats
        var supports4K = false
        var supports60fps = false
        
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dimensions.width >= 3840 && dimensions.height >= 2160 {
                supports4K = true
                let duration = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0
                if duration >= 60 {
                    supports60fps = true
                }
            }
        }
        
        capabilities["4KSupport"] = supports4K
        capabilities["HDRSupport"] = false
        capabilities["60fpsSupport"] = supports60fps
        capabilities["stabilizationSupport"] = true
        
        return capabilities
    }
    
    func getAvailableBitratePresets() -> [String] {
        return VideoEncoderConfiguration.BitratePreset.allCases.map { $0.description }
    }
    
    func setBitratePreset(_ preset: VideoEncoderConfiguration.BitratePreset) {
        currentBitratePreset = preset
        let info = getCurrentRecordingInfo()
        delegate?.cameraManager(self, didUpdateRecordingInfo: info)
    }
    
    func setupSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .hd4K3840x2160
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw SimpleCameraError.deviceUnavailable
        }
        videoDevice = device
        
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
            self.videoInput = input
        }
        
        try configureDeviceForHighFrameRate(device: device)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        output.alwaysDiscardsLateVideoFrames = false
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.videoOutput = output
        }
        
        if let connection = output.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .cinematicExtended
                isStabilizationEnabled = true
            }
        }
        
        self.captureSession = session
    }
    
    private func configureDeviceForHighFrameRate(device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        
        let formats = device.formats
        var selectedFormat: AVCaptureDevice.Format?
        var selectedFrameRate: Int = 30
        
        for format in formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            if dimensions.width >= 3840 && dimensions.height >= 2160 {
                let maxRate = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
                if maxRate >= 60 {
                    selectedFormat = format
                    selectedFrameRate = 60
                    break
                } else if selectedFormat == nil {
                    selectedFormat = format
                    selectedFrameRate = Int(maxRate)
                }
            }
        }
        
        if let format = selectedFormat {
            device.activeFormat = format
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(selectedFrameRate))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(selectedFrameRate))
            isHighFrameRateEnabled = selectedFrameRate >= 60
            currentFrameRate = selectedFrameRate
        }
        
        device.unlockForConfiguration()
    }
    
    func enableHDR(_ enable: Bool) {
        isHDREnabled = enable
        
        let info = getCurrentRecordingInfo()
        delegate?.cameraManager(self, didUpdateRecordingInfo: info)
    }
    
    func getCurrentRecordingInfo() -> [String: Any] {
        return [
            "resolution": currentResolution,
            "frameRate": currentFrameRate,
            "stabilization": isStabilizationEnabled,
            "hdrEnabled": isHDREnabled,
            "hdrSupported": isHDRSupported,
            "highFrameRate": isHighFrameRateEnabled,
            "bitratePreset": currentBitratePreset.rawValue,
            "bitrate": currentBitratePreset.bitrate / 1_000_000
        ]
    }
    
    func startSession() {
        captureQueue.async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    func stopSession() {
        captureQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
        }
    }
    
    func startRecording() {
        guard recordingState == .idle else { return }
        
        frameCount = 0
        savedFrameCount = 0
        encodedBytes = 0
        encodedFrameCount = 0
        droppedFrameCount = 0
        recordingState = .recording
        encodingStartTime = Date()
        
        delegate?.cameraManager(self, didChangeState: .recording)
        
        prepareWriter()
    }
    
    func stopRecording() {
        guard recordingState == .recording else { return }
        recordingState = .idle
        
        finishWriting { [weak self] in
            guard let self = self else { return }
            if let url = self.outputURL {
                self.saveToPhotoLibrary(url: url)
            }
            self.delegate?.cameraManager(self, didChangeState: .idle)
        }
    }
    
    private func prepareWriter() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "recording_\(Date().timeIntervalSince1970).mov"
        outputURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL!, fileType: .mov)
            
            let bitrate = currentBitratePreset.bitrate
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: 3840,
                AVVideoHeightKey: 2160,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitrate,
                    AVVideoMaxKeyFrameIntervalKey: 120,
                    AVVideoAllowFrameReorderingKey: true
                ]
            ]
            
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 3840,
                kCVPixelBufferHeightKey as String: 2160
            ]
            
            pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput!,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            if let writerInput = videoWriterInput, let adaptor = pixelBufferAdaptor {
                if assetWriter?.canAdd(writerInput) == true {
                    assetWriter?.add(writerInput)
                }
            }
            
            assetWriter?.startWriting()
            recordingStartTime = CMTime(seconds: 0, preferredTimescale: 600)
            assetWriter?.startSession(atSourceTime: recordingStartTime!)
            
        } catch {
            delegate?.cameraManager(self, didFailWithError: .writerFailed(error))
        }
    }
    
    private func finishWriting(completion: @escaping () -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.videoWriterInput?.markAsFinished()
            
            self.assetWriter?.finishWriting {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    private func shouldKeepFrame() -> Bool {
        frameCount += 1
        let shouldKeep = frameCount % (framesToSkip + 1) == 0
        if shouldKeep {
            savedFrameCount += 1
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraManager(self, didUpdateFrameCount: self.savedFrameCount, total: self.frameCount)
            }
        }
        return shouldKeep
    }
    
    private func updateStatistics() {
        guard let startTime = encodingStartTime else { return }
        
        let duration = Date().timeIntervalSince(startTime)
        if duration > 0 {
            let averageBitrate = Double(encodedBytes) * 8 / duration
            let fps = Double(encodedFrameCount) / duration
            
            let stats: [String: Any] = [
                "averageBitrate": averageBitrate / 1_000_000,
                "fps": fps,
                "encodedFrames": encodedFrameCount,
                "droppedFrames": droppedFrameCount,
                "encodedBytes": Double(encodedBytes) / 1_000_000
            ]
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.cameraManager(self, didUpdateStatistics: stats)
            }
        }
    }
    
    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else { return }
            
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("Video saved to photo library: \(url.lastPathComponent)")
                    } else if let error = error {
                        print("Failed to save video: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

extension SimpleCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recordingState == .recording else { return }
        
        guard shouldKeepFrame() else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedFrameCount += 1
            return
        }
        
        let presentationTime = CMTime(seconds: Double(savedFrameCount) / 30.0, preferredTimescale: 600)
        
        processingQueue.async { [weak self] in
            guard let self = self,
                  let writerInput = self.videoWriterInput,
                  let adaptor = self.pixelBufferAdaptor,
                  writerInput.isReadyForMoreMediaData else {
                return
            }
            
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                self.encodedFrameCount += 1
                let estimatedBytesPerFrame = Double(self.currentBitratePreset.bitrate) / 30.0 / 8.0
                self.encodedBytes += Int64(estimatedBytesPerFrame)
                self.updateStatistics()
            } else {
                self.droppedFrameCount += 1
            }
        }
    }
}
