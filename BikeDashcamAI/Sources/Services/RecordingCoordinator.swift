import Foundation

final class RecordingCoordinator {
    private let cameraManager: CameraManager
    private let videoEncoder: VideoEncoder
    private let sensorCollector: SensorDataCollector
    
    init(cameraManager: CameraManager, videoEncoder: VideoEncoder, sensorCollector: SensorDataCollector) {
        self.cameraManager = cameraManager
        self.videoEncoder = videoEncoder
        self.sensorCollector = sensorCollector
    }
    
    func startRecording() throws {
        try videoEncoder.startEncoding()
        sensorCollector.startCollection()
    }
    
    func stopRecording() {
        videoEncoder.stopEncoding()
        sensorCollector.stopCollection()
    }
}
