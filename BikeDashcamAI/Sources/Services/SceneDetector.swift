import CoreLocation
import Foundation

/// 融合视觉相似度、位置、速度和场景类型。没有模型特征时，视觉项视为“未变化”，仍可由停车或位移切开片段。
final class SceneDetector {
    var similarityThreshold: Float = 0.85
    var windowSize = 5

    private let lock = NSLock()
    private var window: [Float] = []
    private var currentScene: SceneType = .other
    private var anchorLocation: CLLocation?
    private var anchorSpeedBand: SpeedBand = .unknown
    private var lastVector: [Float] = []
    private var belowThresholdSince: TimeInterval?
    private var lastChangeTime: TimeInterval = -.greatestFiniteMagnitude
    private var pendingManual = false
    private let minimumSegmentDuration: TimeInterval = 8
    private let confirmationDuration: TimeInterval = 2

    private enum SpeedBand {
        case unknown, stopped, cruising, fast
    }

    func reset() {
        lock.lock()
        window.removeAll()
        currentScene = .other
        anchorLocation = nil
        anchorSpeedBand = .unknown
        lastVector.removeAll()
        belowThresholdSince = nil
        lastChangeTime = -.greatestFiniteMagnitude
        pendingManual = false
        lock.unlock()
    }

    func forceSceneChange() {
        lock.lock()
        pendingManual = true
        lock.unlock()
    }

    func processFrame(
        _ prediction: ScenePrediction,
        location: CLLocation?,
        speed: Double?
    ) -> SceneChangeEvent? {
        lock.lock()
        defer { lock.unlock() }

        let speedKmh = max(0, (speed ?? 0) * 3.6)
        similarityThreshold = speedKmh > 25 ? 0.75 : (speedKmh < 10 ? 0.9 : 0.85)

        if pendingManual, prediction.timestamp - lastChangeTime >= 1 {
            pendingManual = false
            return commitChange(
                at: prediction.timestamp,
                newScene: scene(for: prediction, speed: speed),
                confidence: 1,
                reason: .manual,
                location: location,
                speed: speed
            )
        }

        let visual = cosineSimilarity(lastVector, prediction.featureVector)
        let locationScore = locationSimilarity(location)
        let band = speedBand(speed)
        let speedScore: Float = (anchorSpeedBand == .unknown || band == anchorSpeedBand) ? 1 : 0
        let typeScore: Float = (prediction.confidence >= 0.5 && prediction.sceneType != currentScene) ? 0 : 1
        let similarity = 0.5 * visual + 0.2 * locationScore + 0.2 * speedScore + 0.1 * typeScore

        window.append(similarity)
        if window.count > windowSize {
            window.removeFirst(window.count - windowSize)
        }
        let smoothed = median(window)

        if anchorLocation == nil {
            anchorLocation = location
        }
        if anchorSpeedBand == .unknown {
            anchorSpeedBand = band
        }
        if !prediction.featureVector.isEmpty {
            lastVector = prediction.featureVector
        }

        guard smoothed < similarityThreshold else {
            belowThresholdSince = nil
            return nil
        }
        if belowThresholdSince == nil {
            belowThresholdSince = prediction.timestamp
        }
        let held = prediction.timestamp - (belowThresholdSince ?? prediction.timestamp)
        guard held >= confirmationDuration, prediction.timestamp - lastChangeTime >= minimumSegmentDuration else {
            return nil
        }

        let reason = dominantReason(visual: visual, location: locationScore, speed: speedScore, type: typeScore)
        return commitChange(
            at: prediction.timestamp,
            newScene: scene(for: prediction, speed: speed),
            confidence: 1 - smoothed,
            reason: reason,
            location: location,
            speed: speed
        )
    }

    private func commitChange(
        at timestamp: TimeInterval,
        newScene: SceneType,
        confidence: Float,
        reason: ChangeReason,
        location: CLLocation?,
        speed: Double?
    ) -> SceneChangeEvent {
        let event = SceneChangeEvent(
            timestamp: timestamp,
            previousScene: currentScene,
            newScene: newScene,
            confidence: confidence,
            reason: reason
        )
        currentScene = newScene
        anchorLocation = location
        anchorSpeedBand = speedBand(speed)
        lastChangeTime = timestamp
        belowThresholdSince = nil
        window.removeAll()
        return event
    }

    private func scene(for prediction: ScenePrediction, speed: Double?) -> SceneType {
        if prediction.confidence >= 0.5 {
            return prediction.sceneType
        }
        if speedBand(speed) == .stopped {
            return .parking
        }
        if currentScene == .parking {
            return .other
        }
        return currentScene
    }

    private func dominantReason(visual: Float, location: Float, speed: Float, type: Float) -> ChangeReason {
        let scores: [(ChangeReason, Float)] = [
            (.visual, 1 - visual),
            (.location, 1 - location),
            (.speed, 1 - speed),
            (.sceneType, 1 - type)
        ]
        return scores.max(by: { $0.1 < $1.1 })?.0 ?? .location
    }

    private func locationSimilarity(_ location: CLLocation?) -> Float {
        guard let location, let anchorLocation else { return 1 }
        let distance = location.distance(from: anchorLocation)
        if distance <= 80 { return 1 }
        if distance >= 400 { return 0 }
        return Float(1 - (distance - 80) / 320)
    }

    private func speedBand(_ speed: Double?) -> SpeedBand {
        let metersPerSecond = speed ?? 0
        if metersPerSecond < 1 { return .stopped }
        if metersPerSecond * 3.6 > 25 { return .fast }
        return .cruising
    }

    private func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        var dot: Float = 0
        var leftNorm: Float = 0
        var rightNorm: Float = 0
        for index in lhs.indices {
            dot += lhs[index] * rhs[index]
            leftNorm += lhs[index] * lhs[index]
            rightNorm += rhs[index] * rhs[index]
        }
        let denominator = sqrt(leftNorm) * sqrt(rightNorm)
        guard denominator > 0 else { return 1 }
        return min(1, max(0, dot / denominator))
    }

    private func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 1 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
