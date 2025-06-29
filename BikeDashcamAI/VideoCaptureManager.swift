import AVFoundation
import UIKit
import CoreImage
import Vision

class VideoCaptureManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isSessionRunning = false
    @Published var error: String?
    
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var audioDeviceInput: AVCaptureDeviceInput?
    
    private let sessionQueue = DispatchQueue(label: "session.queue")
    private let videoDataQueue = DispatchQueue(label: "video.data.queue")
    private let audioDataQueue = DispatchQueue(label: "audio.data.queue")
    
    // Video processing
    private var currentVideoBuffer: CMSampleBuffer?
    private var videoFrames: [CMSampleBuffer] = []
    private let maxBufferSize = 300 // 10 seconds at 30fps
    
    // AI Analysis
    private let aiAnalyzer = AIAnalyzer()
    private var analysisResults: [VideoAnalysisResult] = []
    
    // Callbacks
    var onFrameCaptured: ((CMSampleBuffer) -> Void)?
    var onAnalysisResult: ((VideoAnalysisResult) -> Void)?
    var onRecordingComplete: ((URL) -> Void)?
    
    override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        session.beginConfiguration()
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            error = "Failed to get video device"
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
            }
        } catch {
            self.error = "Failed to add video input: \(error.localizedDescription)"
            return
        }
        
        // Add audio input
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
            error = "Failed to get audio device"
            return
        }
        
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                audioDeviceInput = audioInput
            }
        } catch {
            self.error = "Failed to add audio input: \(error.localizedDescription)"
            return
        }
        
        // Configure video output
        videoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        // Configure audio output
        audioOutput.setSampleBufferDelegate(self, queue: audioDataQueue)
        
        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        }
        
        // Configure movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = self?.session.isRunning ?? false
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = self?.session.isRunning ?? false
            }
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let videoName = "bike_dashcam_\(Date().timeIntervalSince1970).mov"
        let videoURL = documentsPath.appendingPathComponent(videoName)
        
        sessionQueue.async { [weak self] in
            self?.movieOutput.startRecording(to: videoURL, recordingDelegate: self)
            DispatchQueue.main.async {
                self?.isRecording = true
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        sessionQueue.async { [weak self] in
            self?.movieOutput.stopRecording()
            DispatchQueue.main.async {
                self?.isRecording = false
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
    
    private func processVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        // Store frame for analysis
        videoFrames.append(sampleBuffer)
        
        // Keep only recent frames
        if videoFrames.count > maxBufferSize {
            videoFrames.removeFirst()
        }
        
        // Analyze frame for interesting content
        aiAnalyzer.analyzeFrame(sampleBuffer) { [weak self] result in
            DispatchQueue.main.async {
                self?.onAnalysisResult?(result)
            }
        }
        
        // Notify frame capture
        onFrameCaptured?(sampleBuffer)
    }
    
    func getRecentFrames() -> [CMSampleBuffer] {
        return videoFrames
    }
    
    func clearBuffers() {
        videoFrames.removeAll()
        analysisResults.removeAll()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension VideoCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == videoOutput {
            processVideoFrame(sampleBuffer)
        }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate
extension VideoCaptureManager: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle audio if needed
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
extension VideoCaptureManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.error = "Recording failed: \(error.localizedDescription)"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.onRecordingComplete?(outputFileURL)
        }
    }
}

// MARK: - Video Analysis Result
struct VideoAnalysisResult {
    let timestamp: TimeInterval
    let confidence: Float
    let eventType: VideoEventType
    let boundingBox: CGRect?
    
    enum VideoEventType {
        case motion
        case object
        case scene
        case action
    }
} 