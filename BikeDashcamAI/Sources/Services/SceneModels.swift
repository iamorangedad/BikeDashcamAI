import CoreLocation
import Foundation

enum SceneType: String, Codable, CaseIterable {
    case urbanRoad = "城市道路"
    case parkPath = "公园小径"
    case mountainTrail = "山地越野"
    case riverside = "河边骑行"
    case forestPath = "林荫道路"
    case bridge = "桥梁"
    case tunnel = "隧道"
    case parking = "停车休息"
    case sunset = "日落景观"
    case other = "其他场景"
}

enum ChangeReason: String, Codable {
    case visual
    case location
    case speed
    case sceneType
    case manual
}

struct ScenePrediction {
    let sceneType: SceneType
    let confidence: Float
    let featureVector: [Float]
    let timestamp: TimeInterval
    let description: String?
}

struct SceneChangeEvent {
    let timestamp: TimeInterval
    let previousScene: SceneType
    let newScene: SceneType
    let confidence: Float
    let reason: ChangeReason
}

struct SceneSegment: Identifiable, Codable {
    let id: UUID
    let recordingID: UUID
    let startTime: TimeInterval
    var endTime: TimeInterval?
    var sceneType: SceneType
    var description: String
    var latitude: Double?
    var longitude: Double?
    var avgSpeed: Double?
    var thumbnailPath: String?
    var videoPath: String
    var isCompressed: Bool
    var compressionRatio: Float?
    let createdAt: Date

    var duration: TimeInterval {
        max(0, (endTime ?? startTime) - startTime)
    }

    var location: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }
}

struct RideRecording: Identifiable, Codable {
    let id: UUID
    var startTime: TimeInterval
    var endTime: TimeInterval?
    var totalDistance: Double
    var avgSpeed: Double
    var maxSpeed: Double
    var totalDuration: TimeInterval
    var totalAscent: Double
    var totalDescent: Double
    var createdAt: Date
    var thumbnailPath: String?
    var videoPath: String
}

struct Bookmark: Identifiable, Codable {
    let id: UUID
    let recordingID: UUID
    let timestamp: TimeInterval
    var type: String
    var description: String?
    var voiceNotePath: String?
    var thumbnailPath: String?
    var isUserCreated: Bool
    let createdAt: Date
}

struct RidingStats {
    let totalRecordings: Int
    let totalDistance: Double
    let totalDuration: TimeInterval
    let avgSpeed: Double
}

enum TimeOfDay: String {
    case morning = "早晨"
    case forenoon = "上午"
    case noon = "中午"
    case afternoon = "下午"
    case evening = "傍晚"
    case night = "夜晚"
}

enum WeatherCondition: String {
    case sunny = "阳光明媚"
    case cloudy = "天空阴沉"
    case rainy = "下着雨"
    case unknown = ""
}

enum TerrainType: String {
    case flat = "路面平稳"
    case climbing = "持续爬升"
    case descending = "一路下坡"
}

struct RidingContext {
    let timeOfDay: TimeOfDay
    let weather: WeatherCondition
    let terrain: TerrainType
    let averageSpeed: Double
    let prefersEnglish: Bool

    static func make(date: Date, averageSpeed: Double, ascent: Double, descent: Double) -> RidingContext {
        let hour = Calendar.current.component(.hour, from: date)
        let timeOfDay: TimeOfDay
        switch hour {
        case 5..<8: timeOfDay = .morning
        case 8..<11: timeOfDay = .forenoon
        case 11..<13: timeOfDay = .noon
        case 13..<17: timeOfDay = .afternoon
        case 17..<20: timeOfDay = .evening
        default: timeOfDay = .night
        }
        let terrain: TerrainType
        if ascent > descent + 8 {
            terrain = .climbing
        } else if descent > ascent + 8 {
            terrain = .descending
        } else {
            terrain = .flat
        }
        let english = Locale.preferredLanguages.first?.hasPrefix("en") == true
        return RidingContext(
            timeOfDay: timeOfDay,
            weather: .unknown,
            terrain: terrain,
            averageSpeed: averageSpeed,
            prefersEnglish: english
        )
    }
}

extension Notification.Name {
    static let rideLibraryDidChange = Notification.Name("com.bikedashcam.rideLibraryDidChange")
}
