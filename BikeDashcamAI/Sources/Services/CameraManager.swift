import AVFoundation
import UIKit

enum CameraError: LocalizedError {
    case permissionDenied
    case permissionRestricted
    case sessionConfigurationFailed(Error)
    case deviceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "相机权限被拒绝"
        case .permissionRestricted: return "相机权限受限"
        case .sessionConfigurationFailed(let error): return "配置失败: \(error.localizedDescription)"
        case .deviceUnavailable: return "设备不可用"
        }
    }
}

enum RecordingState {
    case idle, preparing, recording, paused, stopping
    var description: String {
        switch self {
        case .idle: return "空闲"
        case .preparing: return "准备中"
        case .recording: return "录制中"
        case .paused: return "已暂停"
        case .stopping: return "停止中"
        }
    }
}

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didUpdateRecordingState state: RecordingState)
    func cameraManager(_ manager: CameraManager, didEncounterError error: CameraError)
}

final class CameraManager: NSObject {
    private(set) var captureSession: AVCaptureSession?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureMovieFileOutput?
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?
    private(set) var recordingState: RecordingState = .idle
    private(set) var isCinematicStabilizationEnabled: Bool = true
    private(set) var isHDREnabled: Bool = false
    weak var delegate: CameraManagerDelegate?
    
    private let captureQueue = DispatchQueue(label: "com.bikedashcam.camera")
    
    override init() {
        super.init()
    }
    
    func setupPreviewLayer(in view: UIView) {
        DispatchQueue.main.async {
            self.previewLayer?.removeFromSuperlayer()
            guard let session = self.captureSession else { return }
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            self.previewLayer = layer
        }
    }
    
    func checkVideoPermissionStatus() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }
    
    func checkAndRequestPermission() async -> AVAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: return .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            return granted ? .authorized : .denied
        default: return status
        }
    }
    
    func configureSession() async throws {
        let status = await checkAndRequestPermission()
        guard status == .authorized else {
            throw CameraError.permissionDenied
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            captureQueue.async {
                do {
                    let session = AVCaptureSession()
                    session.beginConfiguration()
                    session.sessionPreset = .high
                    
                    guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        continuation.resume(throwing: CameraError.deviceUnavailable)
                        return
                    }
                    
                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if session.canAddInput(videoInput) {
                        session.addInput(videoInput)
                        self.videoInput = videoInput
                    }
                    
                    let movieOutput = AVCaptureMovieFileOutput()
                    if session.canAddOutput(movieOutput) {
                        session.addOutput(movieOutput)
                        self.videoOutput = movieOutput
                    }
                    
                    if let connection = movieOutput.connection(with: .video), connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .cinematicExtended
                    }
                    
                    session.commitConfiguration()
                    self.captureSession = session
                    
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        continuation.resume(throwing: CameraError.sessionConfigurationFailed(error))
                    }
                }
            }
        }
    }
    
    func startSession() {
        captureQueue.async {
            self.captureSession?.startRunning()
        }
    }
    
    func stopSession() {
        captureQueue.async {
            self.captureSession?.stopRunning()
        }
    }
    
    func startRecording(to outputURL: URL) {
        guard recordingState == .idle else { return }
        recordingState = .preparing
        
        captureQueue.async {
            guard let movieOutput = self.videoOutput else { return }
            movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            self.recordingState = .recording
        }
    }
    
    func stopRecording() {
        guard recordingState == .recording else { return }
        recordingState = .stopping
        
        captureQueue.async {
            self.videoOutput?.stopRecording()
        }
    }
    
    func pauseRecording() {
        guard recordingState == .recording else { return }
        recordingState = .paused
    }
    
    func resumeRecording() {
        guard recordingState == .paused else { return }
        recordingState = .recording
    }
    
    func switchCameraPosition() -> Bool {
        guard let currentInput = videoInput, let session = captureSession else { return false }
        
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return false }
        
        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            session.beginConfiguration()
            session.removeInput(currentInput)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                videoInput = newInput
                session.commitConfiguration()
                return true
            }
            session.addInput(currentInput)
            session.commitConfiguration()
            return false
        } catch {
            return false
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        recordingState = .idle
        if let error = error {
            delegate?.cameraManager(self, didEncounterError: .sessionConfigurationFailed(error))
        }
    }
}
