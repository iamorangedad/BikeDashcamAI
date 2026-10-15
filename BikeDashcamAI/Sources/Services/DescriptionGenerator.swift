import Foundation

/// 没有文本生成模型时，用时间、速度和场景类型拼一段不重复的描述。
final class DescriptionGenerator {
    private var lastDescription = ""

    func generate(for segment: SceneSegment, context: RidingContext) async -> String {
        generateWithTemplate(segment, context: context)
    }

    func generateWithTemplate(_ segment: SceneSegment, context: RidingContext) -> String {
        let text = context.prefersEnglish ? english(segment, context) : chinese(segment, context)
        lastDescription = text
        return text
    }

    private func chinese(_ segment: SceneSegment, _ context: RidingContext) -> String {
        let pace = pacePhrase(speed: context.averageSpeed, english: false)
        let scene = segment.sceneType.rawValue
        let terrain = context.terrain.rawValue
        let candidates = [
            "\(context.timeOfDay.rawValue)时分\(pace)骑行经过\(scene)，\(terrain)",
            "\(context.timeOfDay.rawValue)\(pace)穿过\(scene)，沿途\(terrain)",
            "这段\(context.timeOfDay.rawValue)的路程\(pace)，场景是\(scene)，\(terrain)"
        ]
        return fit(candidates.first { $0 != lastDescription } ?? candidates[0], limit: 50)
    }

    private func english(_ segment: SceneSegment, _ context: RidingContext) -> String {
        let pace = pacePhrase(speed: context.averageSpeed, english: true)
        let scene = englishScene(segment.sceneType)
        let terrain = englishTerrain(context.terrain)
        let when = englishTime(context.timeOfDay)
        let candidates = [
            "\(when), \(pace) through \(scene), \(terrain).",
            "\(pace) ride \(when) across \(scene), \(terrain).",
            "This \(when) section is a \(pace) pass by \(scene), \(terrain)."
        ]
        return fit(candidates.first { $0 != lastDescription } ?? candidates[0], limit: 90)
    }

    private func pacePhrase(speed: Double, english: Bool) -> String {
        let kmh = speed * 3.6
        if english {
            if kmh < 3 { return "a paused" }
            if kmh > 25 { return "a fast" }
            return "an easy"
        }
        if kmh < 3 { return "停下来" }
        if kmh > 25 { return "快速地" }
        return "悠闲地"
    }

    private func englishScene(_ scene: SceneType) -> String {
        switch scene {
        case .urbanRoad: return "an urban road"
        case .parkPath: return "a park path"
        case .mountainTrail: return "a mountain trail"
        case .riverside: return "the riverside"
        case .forestPath: return "a tree-lined road"
        case .bridge: return "a bridge"
        case .tunnel: return "a tunnel"
        case .parking: return "a rest stop"
        case .sunset: return "a sunset view"
        case .other: return "the route"
        }
    }

    private func englishTime(_ time: TimeOfDay) -> String {
        switch time {
        case .morning: return "in the early morning"
        case .forenoon: return "in the morning"
        case .noon: return "around noon"
        case .afternoon: return "in the afternoon"
        case .evening: return "in the evening"
        case .night: return "at night"
        }
    }

    private func englishTerrain(_ terrain: TerrainType) -> String {
        switch terrain {
        case .flat: return "on a steady grade"
        case .climbing: return "while climbing"
        case .descending: return "while descending"
        }
    }

    private func fit(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end])
    }
}
