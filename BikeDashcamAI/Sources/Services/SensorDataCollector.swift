import Foundation
import CoreMotion
import CoreLocation
import Combine

struct SensorFrame: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    
    let accelerationX: Double
    let accelerationY: Double
    let accelerationZ: Double
    
    let gyroscopeX: Double
    let gyroscopeY: Double
    let gyroscopeZ: Double
    
    var latitude: Double?
    var longitude: Double?
    var altitude: Double?
    var speed: Double?
    var course: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    
    var roll: Double?
    var pitch: Double?
    var yaw: Double?
    
    var totalDistance: Double?
    var currentSpeed: Double?
}

struct MotionData {
    let timestamp: TimeInterval
    let acceleration: CMAcceleration
    let rotationRate: CMRotationRate
    let magneticField: CMMagneticField?
    let attitude: CMAttitude?
}

struct GPSData {
    let timestamp: TimeInterval
    let location: CLLocation
}

struct SensorStatistics {
    var totalDistance: Double = 0
    var maxSpeed: Double = 0
    var averageSpeed: Double = 0
    var totalDuration: TimeInterval = 0
    var sampleCount: Int = 0
    var averageAcceleration: Double = 0
    var maxAcceleration: Double = 0
}

enum SensorError: LocalizedError {
    case motionManagerUnavailable
    case locationManagerUnavailable
    case permissionDenied
    case headingUnavailable
    case notStarted
    
    var errorDescription: String? {
        switch self {
        case .motionManagerUnavailable: return "运动传感器不可用"
        case .locationManagerUnavailable: return "位置服务不可用"
        case .permissionDenied: return "权限被拒绝"
        case .headingUnavailable: return "方向信息不可用"
        case .notStarted: return "传感器收集器未启动"
        }
    }
}

final class SensorDataCollector: NSObject {
    static let shared = SensorDataCollector()
    
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0
    
    private(set) var isCollecting = false
    
    private let dataQueue = DispatchQueue(label: "com.bikedashcam.sensordata.queue", attributes: .concurrent)
    private var sensorFrames: [SensorFrame] = []
    private let maxBufferSize = 10000
    
    private var imuDataBuffer: [MotionData] = []
    private let imuBufferSize = 1000
    
    private var lastIMUTimestamp: TimeInterval = 0
    private let imuUpdateInterval: TimeInterval = 1.0 / 100.0
    
    private var statistics = SensorStatistics()
    
    private var motionDataSubject = PassthroughSubject<MotionData, Never>()
    private var gpsDataSubject = PassthroughSubject<GPSData, Never>()
    private var sensorFrameSubject = PassthroughSubject<SensorFrame, Never>()
    private var statisticsSubject = PassthroughSubject<SensorStatistics, Never>()
    
    var motionPublisher: AnyPublisher<MotionData, Never> {
        motionDataSubject.eraseToAnyPublisher()
    }
    
    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsDataSubject.eraseToAnyPublisher()
    }
    
    var sensorFramePublisher: AnyPublisher<SensorFrame, Never> {
        sensorFrameSubject.eraseToAnyPublisher()
    }
    
    var statisticsPublisher: AnyPublisher<SensorStatistics, Never> {
        statisticsSubject.eraseToAnyPublisher()
    }
    
    override init() {
        super.init()
        motionQueue.name = "com.bikedashcam.sensordata.motion"
        motionQueue.maxConcurrentOperationCount = 1
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 10
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = 1.0
        }
    }
    
    func checkPermissions() async -> (motion: Bool, location: Bool) {
        var motionAuthorized = true
        var locationAuthorized = false
        
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationAuthorized = true
        case .notDetermined:
            locationAuthorized = await requestLocationPermission()
        default:
            locationAuthorized = false
        }
        
        return (motionAuthorized, locationAuthorized)
    }
    
    private func requestMotionPermission() async -> Bool {
        return true
    }
    
    private func requestLocationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            locationManager.requestWhenInUseAuthorization()
            continuation.resume(returning: locationManager.authorizationStatus == .authorizedWhenInUse || 
                               locationManager.authorizationStatus == .authorizedAlways)
        }
    }
    
    func startCollection() {
        guard !isCollecting else { return }
        
        resetStatistics()
        
        imuDataBuffer.removeAll()
        sensorFrames.removeAll()
        totalDistance = 0
        lastLocation = nil
        lastIMUTimestamp = 0
        
        startMotionUpdates()
        startLocationUpdates()
        
        isCollecting = true
    }
    
    func stopCollection() {
        guard isCollecting else { return }
        
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        stopLocationUpdates()
        
        isCollecting = false
        
        publishFinalStatistics()
    }
    
    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable, motionManager.isGyroAvailable else {
            return
        }
        
        motionManager.accelerometerUpdateInterval = imuUpdateInterval
        motionManager.gyroUpdateInterval = imuUpdateInterval
        motionManager.magnetometerUpdateInterval = imuUpdateInterval
        
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let accelerometerData = data, error == nil else { return }
            self.handleAccelerometerData(accelerometerData)
        }
        
        motionManager.startGyroUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let gyroData = data, error == nil else { return }
            self.handleGyroData(gyroData)
        }
        
        if motionManager.isMagnetometerAvailable {
            motionManager.magnetometerUpdateInterval = imuUpdateInterval
            motionManager.startMagnetometerUpdates(to: motionQueue) { [weak self] data, error in
                guard let self = self, let magnetometerData = data, error == nil else { return }
                self.handleMagnetometerData(magnetometerData)
            }
        }
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = imuUpdateInterval
            motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                guard let self = self, let motionData = data, error == nil else { return }
                self.handleDeviceMotionData(motionData)
            }
        }
    }
    
    private func startLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    private func stopLocationUpdates() {
        locationManager.allowsBackgroundLocationUpdates = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
    }
    
    private func handleAccelerometerData(_ data: CMAccelerometerData) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard currentTimestamp - lastIMUTimestamp >= imuUpdateInterval else { return }
        lastIMUTimestamp = currentTimestamp
        
        let motionData = MotionData(
            timestamp: currentTimestamp,
            acceleration: data.acceleration,
            rotationRate: CMRotationRate(x: 0, y: 0, z: 0),
            magneticField: nil,
            attitude: nil
        )
        
        dataQueue.async { [weak self] in
            self?.imuDataBuffer.append(motionData)
            if let buffer = self?.imuDataBuffer, buffer.count > (self?.imuBufferSize ?? 1000) {
                self?.imuDataBuffer.removeFirst()
            }
        }
        
        motionDataSubject.send(motionData)
    }
    
    private func handleGyroData(_ data: CMGyroData) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard currentTimestamp - lastIMUTimestamp >= imuUpdateInterval else { return }
        lastIMUTimestamp = currentTimestamp
        
        dataQueue.async { [weak self] in
            guard let self = self, var lastMotion = self.imuDataBuffer.last else { return }
            
            let updatedMotion = MotionData(
                timestamp: currentTimestamp,
                acceleration: lastMotion.acceleration,
                rotationRate: data.rotationRate,
                magneticField: lastMotion.magneticField,
                attitude: lastMotion.attitude
            )
            
            if let index = self.imuDataBuffer.indices.last {
                self.imuDataBuffer[index] = updatedMotion
            }
        }
    }
    
    private func handleMagnetometerData(_ data: CMMagnetometerData) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard currentTimestamp - lastIMUTimestamp >= imuUpdateInterval else { return }
        lastIMUTimestamp = currentTimestamp
        
        dataQueue.async { [weak self] in
            guard let self = self, var lastMotion = self.imuDataBuffer.last else { return }
            
            let updatedMotion = MotionData(
                timestamp: currentTimestamp,
                acceleration: lastMotion.acceleration,
                rotationRate: lastMotion.rotationRate,
                magneticField: data.magneticField,
                attitude: lastMotion.attitude
            )
            
            if let index = self.imuDataBuffer.indices.last {
                self.imuDataBuffer[index] = updatedMotion
            }
        }
    }
    
    private func handleDeviceMotionData(_ data: CMDeviceMotion) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard currentTimestamp - lastIMUTimestamp >= imuUpdateInterval else { return }
        lastIMUTimestamp = currentTimestamp
        
        let motionData = MotionData(
            timestamp: currentTimestamp,
            acceleration: CMAcceleration(x: data.userAcceleration.x, y: data.userAcceleration.y, z: data.userAcceleration.z),
            rotationRate: data.rotationRate,
            magneticField: nil,
            attitude: data.attitude
        )
        
        dataQueue.async { [weak self] in
            self?.imuDataBuffer.append(motionData)
            if let buffer = self?.imuDataBuffer, buffer.count > (self?.imuBufferSize ?? 1000) {
                self?.imuDataBuffer.removeFirst()
            }
            
            self?.motionDataSubject.send(motionData)
        }
    }
    
    private func handleGPSData(_ location: CLLocation) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        let gpsData = GPSData(timestamp: currentTimestamp, location: location)
        gpsDataSubject.send(gpsData)
        
        dataQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let lastLocation = self.lastLocation {
                let distance = location.distance(from: lastLocation)
                if location.horizontalAccuracy <= 20 && lastLocation.horizontalAccuracy <= 20 {
                    self.totalDistance += distance
                }
            }
            self.lastLocation = location
            
            self.updateStatistics(speed: location.speed >= 0 ? location.speed : 0,
                                 acceleration: self.calculateTotalAcceleration())
            
            self.createSensorFrame(gpsData: gpsData)
        }
    }
    
    private func calculateTotalAcceleration() -> Double {
        guard let lastMotion = imuDataBuffer.last else { return 0 }
        let acceleration = sqrt(
            lastMotion.acceleration.x * lastMotion.acceleration.x +
            lastMotion.acceleration.y * lastMotion.acceleration.y +
            lastMotion.acceleration.z * lastMotion.acceleration.z
        )
        return acceleration
    }
    
    private func createSensorFrame(gpsData: GPSData) {
        guard let lastMotion = imuDataBuffer.last else { return }
        
        let frame = SensorFrame(
            timestamp: gpsData.timestamp,
            accelerationX: lastMotion.acceleration.x,
            accelerationY: lastMotion.acceleration.y,
            accelerationZ: lastMotion.acceleration.z,
            gyroscopeX: lastMotion.rotationRate.x,
            gyroscopeY: lastMotion.rotationRate.y,
            gyroscopeZ: lastMotion.rotationRate.z,
            latitude: gpsData.location.coordinate.latitude,
            longitude: gpsData.location.coordinate.longitude,
            altitude: gpsData.location.altitude,
            speed: gpsData.location.speed >= 0 ? gpsData.location.speed : nil,
            course: gpsData.location.course >= 0 ? gpsData.location.course : nil,
            horizontalAccuracy: gpsData.location.horizontalAccuracy,
            verticalAccuracy: gpsData.location.verticalAccuracy,
            roll: lastMotion.attitude?.roll,
            pitch: lastMotion.attitude?.pitch,
            yaw: lastMotion.attitude?.yaw,
            totalDistance: totalDistance,
            currentSpeed: gpsData.location.speed >= 0 ? gpsData.location.speed : nil
        )
        
        dataQueue.async(flags: .barrier) { [weak self] in
            self?.sensorFrames.append(frame)
            if let frames = self?.sensorFrames, frames.count > (self?.maxBufferSize ?? 10000) {
                self?.sensorFrames.removeFirst()
            }
        }
        
        sensorFrameSubject.send(frame)
    }
    
    private func updateStatistics(speed: Double, acceleration: Double) {
        statistics.totalDistance = totalDistance
        statistics.maxSpeed = max(statistics.maxSpeed, speed)
        statistics.sampleCount += 1
        
        if statistics.totalDuration == 0 {
            statistics.totalDuration = Date().timeIntervalSince1970 - (sensorFrames.first?.timestamp ?? Date().timeIntervalSince1970)
        }
        
        let runningAverage = statistics.averageSpeed
        statistics.averageSpeed = runningAverage + (speed - runningAverage) / Double(statistics.sampleCount)
        
        statistics.averageAcceleration = (statistics.averageAcceleration * Double(statistics.sampleCount - 1) + acceleration) / Double(statistics.sampleCount)
        statistics.maxAcceleration = max(statistics.maxAcceleration, acceleration)
        
        statisticsSubject.send(statistics)
    }
    
    private func publishFinalStatistics() {
        statisticsSubject.send(statistics)
    }
    
    private func resetStatistics() {
        statistics = SensorStatistics()
    }
    
    func getSensorFrames() -> [SensorFrame] {
        var frames: [SensorFrame] = []
        dataQueue.sync {
            frames = self.sensorFrames
        }
        return frames
    }
    
    func getSensorFramesAligned(withTimestamps timestamps: [TimeInterval]) -> [SensorFrame] {
        let frames = getSensorFrames()
        guard !frames.isEmpty, !timestamps.isEmpty else { return [] }
        
        var alignedFrames: [SensorFrame] = []
        
        for timestamp in timestamps {
            if let closestFrame = frames.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }) {
                alignedFrames.append(closestFrame)
            }
        }
        
        return alignedFrames
    }
    
    func getCurrentSpeed() -> Double {
        return lastLocation?.speed ?? 0
    }
    
    func getTotalDistance() -> Double {
        return totalDistance
    }
    
    func getCurrentStatistics() -> SensorStatistics {
        return statistics
    }
    
    func clearBuffer() {
        dataQueue.async(flags: .barrier) { [weak self] in
            self?.sensorFrames.removeAll()
            self?.imuDataBuffer.removeAll()
        }
    }
}

extension SensorDataCollector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        handleGPSData(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        dataQueue.async { [weak self] in
            guard let self = self, var lastFrame = self.sensorFrames.last else { return }
            
            let updatedFrame = SensorFrame(
                timestamp: newHeading.timestamp.timeIntervalSince1970,
                accelerationX: lastFrame.accelerationX,
                accelerationY: lastFrame.accelerationY,
                accelerationZ: lastFrame.accelerationZ,
                gyroscopeX: lastFrame.gyroscopeX,
                gyroscopeY: lastFrame.gyroscopeY,
                gyroscopeZ: lastFrame.gyroscopeZ,
                latitude: lastFrame.latitude,
                longitude: lastFrame.longitude,
                altitude: lastFrame.altitude,
                speed: lastFrame.speed,
                course: newHeading.magneticHeading > 0 ? newHeading.magneticHeading : lastFrame.course,
                horizontalAccuracy: lastFrame.horizontalAccuracy,
                verticalAccuracy: lastFrame.verticalAccuracy,
                roll: lastFrame.roll,
                pitch: lastFrame.pitch,
                yaw: lastFrame.yaw,
                totalDistance: lastFrame.totalDistance,
                currentSpeed: lastFrame.currentSpeed
            )
            
            if let index = self.sensorFrames.indices.last {
                self.sensorFrames[index] = updatedFrame
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isCollecting {
                startLocationUpdates()
            }
        case .denied, .restricted:
            print("Location permission denied")
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}
