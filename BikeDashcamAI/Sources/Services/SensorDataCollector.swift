import Foundation
import CoreMotion
import CoreLocation
import Combine

struct IMUData {
    var timestamp: TimeInterval
    var acceleration: CMAcceleration
    var rotationRate: CMRotationRate
    var magneticField: CMMagneticField
}

struct GPSData {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: CLLocationSpeed
    var course: CLLocationDirection
    var horizontalAccuracy: CLLocationAccuracy
    var verticalAccuracy: CLLocationAccuracy
    var timestamp: Date
}

enum SensorError: LocalizedError {
    case motionManagerUnavailable
    case locationManagerUnavailable
    case permissionDenied
    case headingUnavailable
    
    var errorDescription: String? {
        switch self {
        case .motionManagerUnavailable: return "运动传感器不可用"
        case .locationManagerUnavailable: return "位置服务不可用"
        case .permissionDenied: return "权限被拒绝"
        case .headingUnavailable: return "方向信息不可用"
        }
    }
}

final class SensorDataCollector: NSObject {
    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    
    private let locationManager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0
    
    private(set) var isCollecting = false
    
    private var imuDataSubject = PassthroughSubject<IMUData, Never>()
    private var gpsDataSubject = PassthroughSubject<GPSData, Never>()
    
    var imuPublisher: AnyPublisher<IMUData, Never> {
        imuDataSubject.eraseToAnyPublisher()
    }
    
    var gpsPublisher: AnyPublisher<GPSData, Never> {
        gpsDataSubject.eraseToAnyPublisher()
    }
    
    var currentSpeed: Double = 0
    var totalDistanceTraveled: Double = 0
    
    override init() {
        super.init()
        motionQueue.name = "com.bikedashcam.sensordata"
        motionQueue.maxConcurrentOperationCount = 1
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.activityType = .otherNavigation
        
        if CLLocationManager.headingAvailable() {
            locationManager.headingFilter = kCLHeadingFilterNone
        }
    }
    
    func startCollection() {
        guard !isCollecting else { return }
        
        requestPermissions()
        startMotionUpdates()
        startLocationUpdates()
        
        isCollecting = true
        totalDistance = 0
        lastLocation = nil
    }
    
    func stopCollection() {
        guard isCollecting else { return }
        
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        motionManager.stopDeviceMotionUpdates()
        
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        
        isCollecting = false
    }
    
    private func requestPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func startMotionUpdates() {
        guard motionManager.isAccelerometerAvailable,
              motionManager.isGyroAvailable,
              motionManager.isMagnetometerAvailable else {
            return
        }
        
        motionManager.accelerometerUpdateInterval = 1.0 / 100.0
        motionManager.gyroUpdateInterval = 1.0 / 100.0
        motionManager.magnetometerUpdateInterval = 1.0 / 100.0
        
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let accelerometerData = data, error == nil else { return }
            self.handleAccelerometerData(accelerometerData)
        }
        
        motionManager.startGyroUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let gyroData = data, error == nil else { return }
            self.handleGyroData(gyroData)
        }
        
        motionManager.startMagnetometerUpdates(to: motionQueue) { [weak self] data, error in
            guard let self = self, let magnetometerData = data, error == nil else { return }
            self.handleMagnetometerData(magnetometerData)
        }
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
            motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] data, error in
                guard let self = self, let motionData = data, error == nil else { return }
                self.handleDeviceMotionData(motionData)
            }
        }
    }
    
    private func startLocationUpdates() {
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
    }
    
    private var latestAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    private var latestRotationRate: CMRotationRate = CMRotationRate(x: 0, y: 0, z: 0)
    private var latestMagneticField: CMMagneticField = CMMagneticField(x: 0, y: 0, z: 0)
    private var lastIMUTimestamp: TimeInterval = 0
    
    private func handleAccelerometerData(_ data: CMAccelerometerData) {
        latestAcceleration = data.acceleration
    }
    
    private func handleGyroData(_ data: CMGyroData) {
        latestRotationRate = data.rotationRate
    }
    
    private func handleMagnetometerData(_ data: CMMagnetometerData) {
        latestMagneticField = data.magneticField
    }
    
    private func handleDeviceMotionData(_ data: CMDeviceMotion) {
        let currentTimestamp = Date().timeIntervalSince1970
        
        guard currentTimestamp - lastIMUTimestamp >= 0.01 else { return }
        lastIMUTimestamp = currentTimestamp
        
        let imuData = IMUData(
            timestamp: currentTimestamp,
            acceleration: latestAcceleration,
            rotationRate: latestRotationRate,
            magneticField: latestMagneticField
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.imuDataSubject.send(imuData)
        }
    }
    
    private func handleGPSData(_ location: CLLocation) {
        if let lastLocation = lastLocation {
            let distance = location.distance(from: lastLocation)
            if location.horizontalAccuracy <= 20 && lastLocation.horizontalAccuracy <= 20 {
                totalDistance += distance
            }
        }
        lastLocation = location
        
        currentSpeed = location.speed >= 0 ? location.speed : 0
        totalDistanceTraveled = totalDistance
        
        let gpsData = GPSData(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            speed: location.speed,
            course: location.course,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.timestamp
        )
        
        DispatchQueue.main.async { [weak self] in
            self?.gpsDataSubject.send(gpsData)
        }
    }
    
    func getCurrentSpeed() -> Double {
        return currentSpeed
    }
    
    func getTotalDistance() -> Double {
        return totalDistanceTraveled
    }
}

extension SensorDataCollector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        handleGPSData(location)
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
