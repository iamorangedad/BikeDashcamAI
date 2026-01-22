import AVFoundation
import UIKit
import Photos
import Photos

enum SimpleCameraError: Error {
    case permissionDenied
    case sessionFailed(Error)
    case writerFailed(Error)
    case unknown
}

enum SimpleRecordingState {
    case idle, recording, paused
}

protocol SimpleCameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: SimpleCameraManager, didChangeState state: SimpleRecordingState)
    func cameraManager(_ manager: SimpleCameraManager, didFailWithError error: SimpleCameraError)
    func cameraManager(_ manager: SimpleCameraManager, didUpdateFrameCount current: Int, total: Int)
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
    
    private var recordingStartTime: CMTime?
    private var outputURL: URL?
    
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
    
    func setupSession() throws {
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw SimpleCameraError.permissionDenied
        }
        
        let input = try AVCaptureDeviceInput(device: videoDevice)
        if session.canAddInput(input) {
            session.addInput(input)
            self.videoInput = input
        }
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        output.alwaysDiscardsLateVideoFrames = false
        
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.videoOutput = output
        }
        
        if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .cinematic
        }
        
        self.captureSession = session
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
        recordingState = .recording
        delegate?.cameraManager(self, didChangeState: .recording)
        
        prepareWriter()
    }
    
    func stopRecording() {
        guard recordingState == .recording else { return }
        recordingState = .idle
        
        finishWriting { [weak self] in
            guard let self = self else { return }
            self.delegate?.cameraManager(self, didChangeState: .idle)
        }
    }
    
    private func prepareWriter() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "processed_\(Date().timeIntervalSince1970).mp4"
        outputURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            assetWriter = try AVAssetWriter(outputURL: outputURL!, fileType: .mp4)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 10_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoWriterInput?.expectsMediaDataInRealTime = true
            
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080
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
            
            self.assetWriter?.finishWriting { [weak self] in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.saveToPhotoLibrary(url: self.outputURL!)
                    completion()
                }
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
                        print("Video saved to photo library")
                    } else if let error = error {
                        print("Failed to save video: \(error.localizedDescription)")
                    }
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
}

extension SimpleCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard recordingState == .recording else { return }
        
        guard shouldKeepFrame() else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let presentationTime = CMTime(seconds: Double(savedFrameCount) / 30.0, preferredTimescale: 600)
        
        processingQueue.async { [weak self] in
            guard let self = self,
                  let writerInput = self.videoWriterInput,
                  let adaptor = self.pixelBufferAdaptor,
                  writerInput.isReadyForMoreMediaData else {
                return
            }
            
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) == false {
                print("Failed to append pixel buffer")
            }
        }
    }
}
