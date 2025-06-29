import AVFoundation
import UIKit
import CoreImage

class VideoProcessor: NSObject, ObservableObject {
    @Published var isProcessing = false
    @Published var progress: Float = 0.0
    @Published var error: String?
    
    private let composition = AVMutableComposition()
    private let videoComposition = AVMutableVideoComposition()
    private let audioMix = AVMutableAudioMix()
    
    private let processingQueue = DispatchQueue(label: "video.processing.queue", qos: .userInitiated)
    private let exportSession = AVAssetExportSession.self
    
    // Video segments for real-time editing
    private var videoSegments: [VideoSegment] = []
    private var currentSegment: VideoSegment?
    
    // AI analysis results for intelligent editing
    private var analysisResults: [VideoAnalysisResult] = []
    
    // Callbacks
    var onSegmentCreated: ((VideoSegment) -> Void)?
    var onProcessingComplete: ((URL) -> Void)?
    var onProgressUpdate: ((Float) -> Void)?
    
    override init() {
        super.init()
        setupComposition()
    }
    
    private func setupComposition() {
        composition = AVMutableComposition()
        videoComposition = AVMutableVideoComposition()
        audioMix = AVMutableAudioMix()
    }
    
    // MARK: - Real-time Video Processing
    
    func addFrame(_ sampleBuffer: CMSampleBuffer, analysisResult: VideoAnalysisResult) {
        processingQueue.async { [weak self] in
            self?.processFrame(sampleBuffer, analysisResult: analysisResult)
        }
    }
    
    private func processFrame(_ sampleBuffer: CMSampleBuffer, analysisResult: VideoAnalysisResult) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        
        // Determine if this frame should be included in current segment
        let shouldInclude = shouldIncludeFrame(analysisResult)
        
        if shouldInclude {
            // Add frame to current segment or create new segment
            if currentSegment == nil {
                currentSegment = VideoSegment(startTime: timestamp, confidence: analysisResult.confidence)
            }
            
            currentSegment?.addFrame(sampleBuffer, analysisResult: analysisResult)
        } else {
            // Finalize current segment if it exists
            if let segment = currentSegment {
                finalizeSegment(segment)
                currentSegment = nil
            }
        }
        
        // Store analysis result
        analysisResults.append(analysisResult)
        
        // Clean up old analysis results (keep last 10 seconds)
        cleanupOldResults(currentTime: timestamp)
    }
    
    private func shouldIncludeFrame(_ analysisResult: VideoAnalysisResult) -> Bool {
        // Include frame if confidence is above threshold
        let confidenceThreshold: Float = 0.3
        
        // Different thresholds for different event types
        switch analysisResult.eventType {
        case .motion:
            return analysisResult.confidence > confidenceThreshold * 0.8
        case .object:
            return analysisResult.confidence > confidenceThreshold * 0.6
        case .scene:
            return analysisResult.confidence > confidenceThreshold * 1.2
        case .action:
            return analysisResult.confidence > confidenceThreshold * 0.5
        }
    }
    
    private func finalizeSegment(_ segment: VideoSegment) {
        // Only keep segments that are long enough and have good content
        let minSegmentDuration: TimeInterval = 0.5 // 500ms minimum
        let minAverageConfidence: Float = 0.2
        
        if segment.duration >= minSegmentDuration && segment.averageConfidence >= minAverageConfidence {
            videoSegments.append(segment)
            onSegmentCreated?(segment)
        }
    }
    
    private func cleanupOldResults(currentTime: TimeInterval) {
        let cutoffTime = currentTime - 10.0 // Keep last 10 seconds
        analysisResults = analysisResults.filter { $0.timestamp >= cutoffTime }
    }
    
    // MARK: - Video Composition
    
    func createFinalVideo(completion: @escaping (URL?) -> Void) {
        guard !videoSegments.isEmpty else {
            completion(nil)
            return
        }
        
        isProcessing = true
        progress = 0.0
        
        processingQueue.async { [weak self] in
            self?.composeVideo { url in
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    completion(url)
                }
            }
        }
    }
    
    private func composeVideo(completion: @escaping (URL?) -> Void) {
        // Create composition tracks
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(nil)
            return
        }
        
        var currentTime = CMTime.zero
        
        // Add segments to composition
        for (index, segment) in videoSegments.enumerated() {
            guard let asset = segment.createAsset() else { continue }
            
            let duration = CMTime(seconds: segment.duration, preferredTimescale: 600)
            
            // Add video track
            if let segmentVideoTrack = try? asset.tracks(withMediaType: .video).first {
                try? videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                               of: segmentVideoTrack,
                                               at: currentTime)
            }
            
            // Add audio track
            if let segmentAudioTrack = try? asset.tracks(withMediaType: .audio).first {
                try? audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration),
                                               of: segmentAudioTrack,
                                               at: currentTime)
            }
            
            currentTime = CMTimeAdd(currentTime, duration)
            
            // Update progress
            let progress = Float(index + 1) / Float(videoSegments.count)
            DispatchQueue.main.async {
                self.progress = progress
                self.onProgressUpdate?(progress)
            }
        }
        
        // Configure video composition
        configureVideoComposition(videoTrack: videoTrack)
        
        // Export final video
        exportVideo(completion: completion)
    }
    
    private func configureVideoComposition(videoTrack: AVMutableCompositionTrack) {
        videoComposition.renderSize = CGSize(width: 1920, height: 1080)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderScale = 1.0
        
        // Add video composition instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
    }
    
    private func exportVideo(completion: @escaping (URL?) -> Void) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = documentsPath.appendingPathComponent("edited_video_\(Date().timeIntervalSince1970).mov")
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(nil)
            return
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.audioMix = audioMix
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                if exportSession.status == .completed {
                    completion(outputURL)
                    self.onProcessingComplete?(outputURL)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Utility Methods
    
    func clearSegments() {
        videoSegments.removeAll()
        currentSegment = nil
        analysisResults.removeAll()
    }
    
    func getSegmentCount() -> Int {
        return videoSegments.count
    }
    
    func getTotalDuration() -> TimeInterval {
        return videoSegments.reduce(0) { $0 + $1.duration }
    }
}

// MARK: - Video Segment
class VideoSegment {
    let startTime: TimeInterval
    private var frames: [CMSampleBuffer] = []
    private var analysisResults: [VideoAnalysisResult] = []
    
    var duration: TimeInterval {
        guard let firstFrame = frames.first,
              let lastFrame = frames.last else { return 0 }
        
        let start = CMSampleBufferGetPresentationTimeStamp(firstFrame).seconds
        let end = CMSampleBufferGetPresentationTimeStamp(lastFrame).seconds
        return end - start
    }
    
    var averageConfidence: Float {
        guard !analysisResults.isEmpty else { return 0 }
        let total = analysisResults.reduce(0) { $0 + $1.confidence }
        return total / Float(analysisResults.count)
    }
    
    init(startTime: TimeInterval, confidence: Float) {
        self.startTime = startTime
    }
    
    func addFrame(_ sampleBuffer: CMSampleBuffer, analysisResult: VideoAnalysisResult) {
        frames.append(sampleBuffer)
        analysisResults.append(analysisResult)
    }
    
    func createAsset() -> AVAsset? {
        // Create a temporary asset from the frames
        // This is a simplified implementation
        // In a real app, you would write frames to a temporary file
        return nil
    }
} 