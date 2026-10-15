import Foundation
import CoreMotion
import CoreLocation
import Combine

struct SensorFrame: Identifiable, Codable {
    let id: UUID
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

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        accelerationX: Double,
        accelerationY: Double,
        accelerationZ: Double,
        gyroscopeX: Double,
        gyroscopeY: Double,
        gyroscopeZ: Double,
        latitude: Double? = nil,
        longitude: Double? = nil,
        altitude: Double? = nil,
        speed: Double? = nil,
        course: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil,
        roll: Double? = nil,
        pitch: Double? = nil,
        yaw: Double? = nil,
        totalDistance: Double? = nil,
        currentSpeed: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.accelerationX = accelerationX
        self.accelerationY = accelerationY
        self.accelerationZ = accelerationZ
        self.gyroscopeX = gyroscopeX
        self.gyroscopeY = gyroscopeY
        self.gyroscopeZ = gyroscopeZ
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.course = course
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.roll = roll
        self.pitch = pitch
        self.yaw = yaw
        self.totalDistance = totalDistance
        self.currentSpeed = currentSpeed
    }
}

struct MotionData {
    let timestamp: TimeInterval
    let acceleration: CMAcceleration
    let rotationRate: CMRotationRate
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

final class SensorDataCollector: NSObject {
    static let shared = SensorDataCollector()

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let locationManager = CLLocationManager()
    private let isolation = DispatchQueue(label: "com.bikedashcam.sensordata")

    private var lastLocation: CLLocation?
    private var totalDistance: Double = 0
    private var latestMotion: MotionData?
    private var latestGPS: GPSData?
    private var latestCourse: Double?
    private var accelWindow: [Double] = []
    private var sensorFrames: [SensorFrame] = []
    private let maxBufferSize = 30_000
    private var lastExportedAt: TimeInterval = 0
    private var lastGPSAcceptedAt: TimeInterval = 0
    private var collectionStartedAt: Date?
    private var collecting = false
    private var statistics = SensorStatistics()
    private var publishTimer: DispatchSourceTimer?
    private var locationWaiters: [CheckedContinuation<Bool, Never>] = []

    private let motionDataSubject = PassthroughSubject<MotionData, Never>()
    private let gpsDataSubject = PassthroughSubject<GPSData, Never>()
    private let sensorFrameSubject = PassthroughSubject<SensorFrame, Never>()
    private let statisticsSubject = PassthroughSubject<SensorStatistics, Never>()

    var motionPublisher: AnyPublisher<MotionData, Never> { motionDataSubject.eraseToAnyPublisher() }
    var gpsPublisher: AnyPublisher<GPSData, Never> { gpsDataSubject.eraseToAnyPublisher() }
    var sensorFramePublisher: AnyPublisher<SensorFrame, Never> { sensorFrameSubject.eraseToAnyPublisher() }
    var statisticsPublisher: AnyPublisher<SensorStatistics, Never> { statisticsSubject.eraseToAnyPublisher() }

    var isCollecting: Bool {
        isolation.sync { collecting }
    }

    override init() {
        super.init()
        motionQueue.name = "com.bikedashcam.sensordata.motion"
        motionQueue.maxConcurrentOperationCount = 1
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .fitness
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    func checkPermissions() async -> (motion: Bool, location: Bool) {
        let motion = motionManager.isDeviceMotionAvailable || motionManager.isAccelerometerAvailable
        let location = await ensureLocationAuthorization()
        return (motion, location)
    }

    func startCollection() {
        isolation.async {
            guard !self.collecting else { return }
            self.collecting = true
            self.collectionStartedAt = Date()
            self.statistics = SensorStatistics()
            self.sensorFrames.removeAll()
            self.totalDistance = 0
            self.lastLocation = nil
            self.latestMotion = nil
            self.latestGPS = nil
            self.accelWindow.removeAll()
            self.lastExportedAt = 0
            self.lastGPSAcceptedAt = 0
            self.startMotionUpdates()
            self.startLocationUpdates()
            self.startPublishTimer()
        }
    }

    func stopCollection() {
        isolation.async {
            guard self.collecting else { return }
            self.collecting = false
            self.publishTimer?.cancel()
            self.publishTimer = nil
            self.motionManager.stopDeviceMotionUpdates()
            self.motionManager.stopAccelerometerUpdates()
            self.motionManager.stopGyroUpdates()
            DispatchQueue.main.async {
                self.locationManager.stopUpdatingLocation()
                self.locationManager.stopUpdatingHeading()
                self.locationManager.allowsBackgroundLocationUpdates = false
            }
            self.refreshStatistics()
            self.statisticsSubject.send(self.statistics)
        }
    }

    func getSensorFrames() -> [SensorFrame] {
        isolation.sync { sensorFrames }
    }

    func frames(from start: TimeInterval, to end: TimeInterval) -> [SensorFrame] {
        isolation.sync {
            sensorFrames.filter { $0.timestamp >= start && $0.timestamp <= end }
        }
    }

    func getSensorFramesAligned(withTimestamps timestamps: [TimeInterval]) -> [SensorFrame] {
        let frames = getSensorFrames()
        guard !frames.isEmpty else { return [] }
        return timestamps.map { timestamp in
            frames.min(by: { abs($0.timestamp - timestamp) < abs($1.timestamp - timestamp) }) ?? frames[0]
        }
    }

    func getCurrentSpeed() -> Double {
        isolation.sync { latestGPS?.location.speed ?? 0 }
    }

    func getTotalDistance() -> Double {
        isolation.sync { totalDistance }
    }

    func getCurrentStatistics() -> SensorStatistics {
        isolation.sync { statistics }
    }

    func clearBuffer() {
        isolation.async {
            self.sensorFrames.removeAll()
        }
    }

    private func ensureLocationAuthorization() async -> Bool {
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                isolation.async {
                    self.locationWaiters.append(continuation)
                    DispatchQueue.main.async {
                        self.locationManager.requestWhenInUseAuthorization()
                    }
                }
            }
        @unknown default:
            return false
        }
    }

    private func startMotionUpdates() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] data, _ in
                guard let self, let data else { return }
                let motion = MotionData(
                    timestamp: Date().timeIntervalSince1970,
                    acceleration: CMAcceleration(
                        x: data.userAcceleration.x,
                        y: data.userAcceleration.y,
                        z: data.userAcceleration.z
                    ),
                    rotationRate: data.rotationRate,
                    attitude: data.attitude
                )
                self.isolation.async {
                    self.latestMotion = motion
                    self.noteAcceleration(motion)
                }
            }
            return
        }

        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 100.0
        motionManager.startAccelerometerUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.isolation.async {
                let previous = self.latestMotion
                self.latestMotion = MotionData(
                    timestamp: Date().timeIntervalSince1970,
                    acceleration: data.acceleration,
                    rotationRate: previous?.rotationRate ?? CMRotationRate(x: 0, y: 0, z: 0),
                    attitude: previous?.attitude
                )
                if let motion = self.latestMotion {
                    self.noteAcceleration(motion)
                }
            }
        }
        guard motionManager.isGyroAvailable else { return }
        motionManager.gyroUpdateInterval = 1.0 / 100.0
        motionManager.startGyroUpdates(to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.isolation.async {
                let previous = self.latestMotion
                self.latestMotion = MotionData(
                    timestamp: Date().timeIntervalSince1970,
                    acceleration: previous?.acceleration ?? CMAcceleration(x: 0, y: 0, z: 0),
                    rotationRate: data.rotationRate,
                    attitude: previous?.attitude
                )
            }
        }
    }

    private func startLocationUpdates() {
        DispatchQueue.main.async {
            if self.locationManager.authorizationStatus == .authorizedAlways {
                self.locationManager.allowsBackgroundLocationUpdates = true
            }
            self.locationManager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                self.locationManager.startUpdatingHeading()
            }
        }
    }

    private func startPublishTimer() {
        let timer = DispatchSource.makeTimerSource(queue: isolation)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            self?.publishLatestFrame()
        }
        timer.resume()
        publishTimer = timer
    }

    private func noteAcceleration(_ motion: MotionData) {
        let magnitude = sqrt(
            motion.acceleration.x * motion.acceleration.x +
            motion.acceleration.y * motion.acceleration.y +
            motion.acceleration.z * motion.acceleration.z
        )
        accelWindow.append(magnitude)
        if accelWindow.count > 5 {
            accelWindow.removeFirst()
        }
    }

    private func smoothedAcceleration() -> Double {
        guard !accelWindow.isEmpty else { return 0 }
        return accelWindow.reduce(0, +) / Double(accelWindow.count)
    }

    private func publishLatestFrame() {
        guard collecting, let motion = latestMotion else { return }
        let frame = makeFrame(motion: motion, timestamp: Date().timeIntervalSince1970)
        sensorFrameSubject.send(frame)
        if frame.timestamp - lastExportedAt >= 1 {
            sensorFrames.append(frame)
            if sensorFrames.count > maxBufferSize {
                sensorFrames.removeFirst(sensorFrames.count - maxBufferSize)
            }
            lastExportedAt = frame.timestamp
            refreshStatistics()
            statisticsSubject.send(statistics)
        }
    }

    private func makeFrame(motion: MotionData, timestamp: TimeInterval) -> SensorFrame {
        let gps = latestGPS?.location
        let speed = (gps?.speed ?? -1) >= 0 ? gps?.speed : nil
        return SensorFrame(
            timestamp: timestamp,
            accelerationX: motion.acceleration.x,
            accelerationY: motion.acceleration.y,
            accelerationZ: motion.acceleration.z,
            gyroscopeX: motion.rotationRate.x,
            gyroscopeY: motion.rotationRate.y,
            gyroscopeZ: motion.rotationRate.z,
            latitude: gps?.coordinate.latitude,
            longitude: gps?.coordinate.longitude,
            altitude: gps?.altitude,
            speed: speed,
            course: latestCourse ?? (gps?.course ?? -1 >= 0 ? gps?.course : nil),
            horizontalAccuracy: gps?.horizontalAccuracy,
            verticalAccuracy: gps?.verticalAccuracy,
            roll: motion.attitude?.roll,
            pitch: motion.attitude?.pitch,
            yaw: motion.attitude?.yaw,
            totalDistance: totalDistance,
            currentSpeed: speed
        )
    }

    private func refreshStatistics() {
        let duration = collectionStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        statistics.totalDuration = duration
        statistics.totalDistance = totalDistance
        statistics.sampleCount = sensorFrames.count
        statistics.averageSpeed = duration > 1 ? totalDistance / duration : statistics.averageSpeed
        let smoothed = smoothedAcceleration()
        if statistics.sampleCount > 0 {
            statistics.averageAcceleration += (smoothed - statistics.averageAcceleration) / Double(statistics.sampleCount)
        }
        statistics.maxAcceleration = max(statistics.maxAcceleration, smoothed)
    }

    private func accept(location: CLLocation) {
        let timestamp = location.timestamp.timeIntervalSince1970
        guard timestamp - lastGPSAcceptedAt >= 0.9 else { return }
        lastGPSAcceptedAt = timestamp
        if let lastLocation, location.horizontalAccuracy <= 20, lastLocation.horizontalAccuracy <= 20 {
            totalDistance += location.distance(from: lastLocation)
        }
        lastLocation = location
        let gps = GPSData(timestamp: timestamp, location: location)
        latestGPS = gps
        gpsDataSubject.send(gps)
        if location.speed >= 0 {
            statistics.maxSpeed = max(statistics.maxSpeed, location.speed)
        }
    }

    private func resumeLocationWaiters(authorized: Bool) {
        let waiters = locationWaiters
        locationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: authorized) }
    }
}

extension SensorDataCollector: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        isolation.async {
            guard self.collecting else { return }
            self.accept(location: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        isolation.async {
            self.latestCourse = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        isolation.async {
            guard status != .notDetermined else { return }
            let authorized = status == .authorizedAlways || status == .authorizedWhenInUse
            self.resumeLocationWaiters(authorized: authorized)
            guard self.collecting, authorized else { return }
            self.startLocationUpdates()
        }
    }

}
