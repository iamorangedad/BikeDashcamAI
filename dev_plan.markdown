# Code Agent开发指令集

以下是针对各开发模块的详细prompt指令，可用于AI编程助手（如Claude、GitHub Copilot、Cursor等）进行模块化开发。

---

## 模块1: 相机采集系统

### Prompt 1.1: 相机管理器基础框架

```
你是一位资深的iOS开发工程师，需要为自行车运动相机应用开发相机管理模块。

任务要求：
1. 创建CameraManager.swift类，使用AVFoundation框架
2. 实现以下核心功能：
   - 配置相机为后置摄像头，支持4K分辨率60fps
   - 启用视频防抖（cinematicExtended模式）
   - 支持HDR视频录制
   - 实现实时预览层
3. 要求：
   - 使用Swift 5.9+语法
   - 遵循MVVM架构模式
   - 包含完整的错误处理
   - 添加详细的注释
   - 实现相机权限检查和请求

技术规格：
- 目标设备: iPhone 14 Plus及以上
- 最低iOS版本: iOS 17.0
- 视频格式: HEVC (H.265)
- 颜色空间: P3

请提供完整的代码实现，包括：
- 类定义和属性
- 初始化方法
- 相机配置方法
- 开始/停止录制方法
- 错误处理枚举
```

### Prompt 1.2: 视频编码器

```
基于已有的CameraManager，现在需要实现VideoEncoder.swift模块。

任务要求：
1. 使用VideoToolbox框架实现硬件加速的H.265编码
2. 支持多种码率预设：
   - 高质量模式: 35Mbps
   - 标准模式: 25Mbps  
   - 省电模式: 15Mbps
   - 压缩模式: 10Mbps
3. 实现编码参数：
   - Profile: HEVC Main10
   - 关键帧间隔: 2秒
   - B帧支持
4. 提供实时编码统计（当前码率、已编码帧数）

输出要求：
- 完整的VideoEncoder类
- 编码配置结构体
- 回调闭包定义（编码完成、错误处理）
- 内存管理优化（及时释放CMSampleBuffer）
- 性能监控代码

请确保代码可以处理：
- 编码失败重试机制
- 码率动态调整接口
- 编码队列管理
```

### Prompt 1.3: 传感器数据采集

```
创建SensorDataCollector.swift，收集骑行相关的传感器数据。

需要采集的数据：
1. 加速度计数据（100Hz采样率）
2. 陀螺仪数据（100Hz采样率）  
3. GPS位置数据（1Hz采样率）
4. 速度和距离计算
5. 设备方向

实现要求：
1. 使用CoreMotion框架处理IMU数据
2. 使用CoreLocation处理GPS数据
3. 实现数据缓冲和时间戳同步
4. 提供数据导出接口（与视频帧时间戳对齐）
5. 实现数据过滤（移动平均、卡尔曼滤波可选）

数据结构设计：
- 定义SensorFrame结构体，包含所有传感器数据和时间戳
- 实现线程安全的数据队列
- 提供Combine发布者用于数据流

性能要求：
- 后台线程处理，不阻塞主线程
- 内存占用<50MB
- CPU占用<5%
```

---

## 模块2: AI推理引擎

### Prompt 2.1: 模型管理器

```
创建MLModelManager.swift，负责加载和管理Core ML模型。

背景信息：
- 使用已转换好的MobileVLM模型（.mlpackage格式）
- 模型输入: 224x224 RGB图像
- 模型输出: 场景分类logits + 特征向量

实现要求：
1. 单例模式设计，应用启动时预加载模型
2. 使用MLModel的computeUnits配置，优先使用Neural Engine
3. 实现模型预热（warmup）机制
4. 提供批量推理接口（支持多帧并行处理）
5. 内存管理：
   - 使用autoreleasepool包裹推理代码
   - 实现模型卸载方法（低内存警告时）

代码结构：
- 模型加载方法（异步）
- 推理方法（输入UIImage，输出ScenePrediction）
- 性能监控（推理时间统计）
- 错误处理（模型加载失败、推理失败）

性能目标：
- 单帧推理时间: <200ms
- 内存占用: <500MB
- 支持多线程调用（线程安全）
```

### Prompt 2.2: 帧提取器

```
开发FrameExtractor.swift，从视频流中提取关键帧用于AI分析。

功能需求：
1. 从AVCaptureVideoDataOutput的sampleBuffer中提取帧
2. 采样策略：
   - 正常模式：每秒提取3帧
   - 场景变化检测模式：每秒提取4帧
   - 省电模式：每秒提取1帧
3. 图像预处理：
   - 缩放到224x224
   - 归一化到[0,1]
   - RGB格式转换
4. 使用Metal加速图像处理

实现细节：
- 使用CVPixelBuffer直接处理，避免格式转换
- 实现Metal shader进行resize和normalize
- 帧缓冲队列（最多保留10帧）
- 时间戳记录和管理

代码组件：
- FrameExtractor类
- Metal shader代码（.metal文件）
- 预处理配置结构体
- 异步处理队列

性能要求：
- 单帧处理时间: <20ms
- 使用GPU避免CPU负载
```

### Prompt 2.3: 推理引擎编排

```
创建InferenceEngine.swift，作为AI推理的核心调度引擎。

架构设计：
采用生产者-消费者模式：
- 生产者：FrameExtractor提取的帧
- 消费者：模型推理
- 结果处理：场景分类和特征提取

功能实现：
1. 异步推理管道：
   - 帧提取队列
   - 推理队列（并发数=2，利用Neural Engine）
   - 结果处理队列
2. 推理节流（throttle）：
   - 如果推理队列积压>5帧，跳过当前帧
   - 动态调整采样率
3. 结果缓存：
   - 保留最近30秒的推理结果
   - LRU缓存策略
4. 回调机制：
   - 推理完成回调
   - 场景变化检测回调

代码要求：
- 使用Combine框架构建数据流
- 或使用GCD实现异步管道
- 线程安全
- 详细日志记录

性能监控：
- 推理延迟统计
- 队列深度监控
- 内存使用监控
```

### Prompt 2.4: 场景分类器

```
实现SceneClassifier.swift，处理模型输出并进行场景分类。

场景类别定义：
enum SceneType: String, Codable {
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

功能需求：
1. 处理模型输出logits，转换为场景类型
2. 计算场景置信度
3. 实现场景相似度计算：
   - 基于特征向量的余弦相似度
   - 阈值配置（默认0.85）
4. 场景变化检测：
   - 滑动窗口平滑（3-5帧）
   - 防止抖动的时间阈值（连续2秒才判定变化）
5. 场景描述生成：
   - 调用模型的文本生成能力（如果支持）
   - 或使用模板生成（"正在骑行经过{场景类型}，环境{光线条件}"）

输出结构：
struct ScenePrediction {
    let sceneType: SceneType
    let confidence: Float
    let featureVector: [Float]
    let timestamp: TimeInterval
    let description: String?
}

实现方法：
- 场景分类方法
- 相似度计算方法
- 变化检测方法
- 描述生成方法
```

---

## 模块3: 场景管理与分段

### Prompt 3.1: 场景检测器

```
开发SceneDetector.swift，实现实时场景变化检测核心算法。

算法设计：
1. 多信号融合检测：
   - 视觉特征相似度（权重0.5）
   - GPS位置变化（权重0.2）
   - 速度变化（权重0.2）
   - 场景类型变化（权重0.1）

2. 滑动窗口平滑：
   - 窗口大小：5帧
   - 使用中值滤波减少噪声
   
3. 自适应阈值：
   - 基于骑行速度动态调整
   - 高速骑行（>25km/h）：阈值降低到0.75
   - 低速骑行（<10km/h）：阈值提高到0.9

实现要求：
1. 实时处理每一帧的推理结果
2. 维护历史窗口数据
3. 检测到场景变化时触发回调
4. 提供手动触发场景切换接口（用户可手动标记）

代码结构：
class SceneDetector {
    // 配置
    var similarityThreshold: Float
    var windowSize: Int
    
    // 方法
    func processFrame(_ prediction: ScenePrediction, 
                     location: CLLocation?, 
                     speed: Double?) -> SceneChangeEvent?
    func forceSceneChange()
    func reset()
}

输出：
struct SceneChangeEvent {
    let timestamp: TimeInterval
    let previousScene: SceneType
    let newScene: SceneType
    let confidence: Float
    let reason: ChangeReason // 视觉/位置/速度/手动
}
```

### Prompt 3.2: 片段管理器

```
创建SegmentManager.swift，管理视频片段的创建、存储和检索。

数据模型：
struct SceneSegment {
    let id: UUID
    let recordingID: UUID  // 所属的骑行记录
    let startTime: TimeInterval
    var endTime: TimeInterval?
    let sceneType: SceneType
    var description: String
    let location: CLLocation?
    let avgSpeed: Double?
    var thumbnailPath: String?
    var videoPath: String
    var isCompressed: Bool
    var compressionRatio: Float?
    let createdAt: Date
}

功能实现：
1. 片段生命周期管理：
   - 创建新片段（场景变化时）
   - 更新当前片段（持续录制时）
   - 结束片段（场景切换或停止录制）
   
2. 存储管理：
   - 视频文件命名：{recordingID}_{segmentID}.mov
   - 缩略图生成（从片段中间帧提取）
   - 文件路径管理
   
3. 数据库操作：
   - 插入新片段记录
   - 更新片段信息
   - 查询片段列表
   - 删除片段
   
4. 内存缓存：
   - 保留当前录制会话的所有片段在内存
   - 提供快速访问接口

类方法：
- func createSegment(for recording: UUID, sceneType: SceneType) -> SceneSegment
- func updateCurrentSegment(description: String?, endTime: TimeInterval?)
- func finalizeSegment(_ segmentID: UUID)
- func getSegments(for recordingID: UUID) -> [SceneSegment]
- func generateThumbnail(for segment: SceneSegment) async -> UIImage?

线程安全要求：
- 使用Actor模式或串行队列
- 数据库操作异步化
```

### Prompt 3.3: 描述生成器

```
实现DescriptionGenerator.swift，为场景片段生成自然语言描述。

生成策略：
1. 如果多模态模型支持文本生成：
   - 调用模型API生成描述
   - 提供上下文（场景类型、时间、天气等）
   
2. 如果仅支持分类，使用模板生成：
   - 时间段模板："上午/下午/傍晚"
   - 场景模板："骑行经过{场景}"
   - 天气模板："阳光明媚/阴天/雨天"（基于光线分析）
   - 速度模板："快速/悠闲地"

模板示例：
"{时间段}{速度}骑行经过{场景}，{天气}，{特殊元素}"
→ "傍晚时分悠闲地骑行经过河边，夕阳西下，景色优美"

实现要求：
1. 支持中英文双语
2. 描述长度控制（30-50字）
3. 避免重复（连续场景描述要有变化）
4. 包含关键信息：
   - 场景类型
   - 时间信息
   - 环境特征
   - 骑行状态（速度、坡度）

代码结构：
class DescriptionGenerator {
    func generate(for segment: SceneSegment, 
                  context: RidingContext) async -> String
    func generateWithTemplate(_ segment: SceneSegment) -> String
    func generateWithModel(_ segment: SceneSegment) async -> String?
}

struct RidingContext {
    let timeOfDay: TimeOfDay  // 早晨/上午/中午/下午/傍晚/夜晚
    let weather: WeatherCondition  // 从光线推断
    let terrain: TerrainType  // 从速度和加速度推断
}
```

---

## 模块4: 智能压缩系统

### Prompt 4.1: 压缩引擎

```
开发CompressionEngine.swift，实现智能视频压缩核心逻辑。

压缩策略：
1. 相似场景判定：
   - 场景相似度 > 0.85
   - 持续时长 > 10秒
   - 视觉变化小（帧间差异 < 阈值）

2. 压缩方法：
   a) 帧率降低：60fps → 24fps 或 15fps
   b) 码率降低：25Mbps → 10Mbps
   c) 时间压缩：以1.5x-3x速度播放
   
3. 关键帧保留：
   - 每5秒保留1个原始质量关键帧
   - 场景起始和结束各保留2帧
   
4. 可逆性设计：
   - 保留原始片段索引
   - 支持解压还原（重新编码）

实现要求：
1. 实时判断是否需要压缩
2. 平滑过渡（压缩启动/退出时避免突变）
3. 压缩过程中实时反馈进度
4. 支持压缩级别配置：
   - 轻度压缩（1.5x速度，20fps）
   - 中度压缩（2x速度，15fps）
   - 重度压缩（3x速度，12fps）

代码结构：
class CompressionEngine {
    // 配置
    struct CompressionConfig {
        var similarityThreshold: Float = 0.85
        var minDuration: TimeInterval = 10.0
        var targetFrameRate: Float = 20.0
        var targetBitrate: Int = 10_000_000
        var speedMultiplier: Float = 2.0
        var keyFrameInterval: TimeInterval = 5.0
    }
    
    // 方法
    func shouldCompress(segment: SceneSegment, 
                       similarityScore: Float) -> Bool
    func compress(videoURL: URL, 
                 config: CompressionConfig) async throws -> URL
    func decompress(compressedURL: URL) async throws -> URL
}

性能要求：
- 压缩速度 > 2x实时（处理1分钟视频<30秒）
- 存储节省 > 40%
- 视觉质量损失 < 15%（VMAF评分）
```

### Prompt 4.2: 码率控制器

```
创建BitrateController.swift，动态调整视频编码码率。

功能设计：
1. 场景复杂度分析：
   - 高复杂度（快速运动、细节丰富）：30-35Mbps
   - 中等复杂度（正常骑行）：20-25Mbps
   - 低复杂度（静止、简单场景）：12-15Mbps
   - 压缩模式：8-10Mbps

2. 实时调整策略：
   - 每2秒评估一次当前场景复杂度
   - 平滑过渡（使用ease-in-out曲线）
   - 码率变化幅度限制（单次<20%）

3. 复杂度计算：
   - 帧间差异（光流法）
   - 边缘密度
   - 纹理复杂度
   - 运动向量幅度

实现要求：
class BitrateController {
    // 当前码率状态
    private(set) var currentBitrate: Int
    
    // 分析帧复杂度
    func analyzeComplexity(_ frame: CVPixelBuffer) -> Float
    
    // 计算目标码率
    func calculateTargetBitrate(complexity: Float, 
                               mode: RecordingMode) -> Int
    
    // 应用码率变化
    func applyBitrateChange(to encoder: VideoEncoder, 
                           targetBitrate: Int)
}

enum RecordingMode {
    case highQuality    // 固定高码率
    case adaptive       // 自适应
    case compressed     // 压缩模式
    case battery        // 省电模式
}

使用Metal加速：
- 帧差计算
- 边缘检测（Sobel算子）
- 纹理分析
```

### Prompt 4.3: 帧率适配器

```
实现FrameRateAdapter.swift，动态调整视频采集和编码帧率。

适配策略：
1. 根据场景类型调整：
   - 高速运动：60fps（保持流畅）
   - 正常骑行：30fps（平衡质量和性能）
   - 慢速/静止：24fps（电影感）
   - 压缩模式：15fps（节省空间）

2. 平滑切换：
   - 帧率变化时使用帧混合（frame blending）
   - 避免视觉跳变
   
3. 同步音频：
   - 音频采样率保持44.1kHz
   - 时间戳对齐

实现细节：
class FrameRateAdapter {
    private var currentFrameRate: Float = 60.0
    private var targetFrameRate: Float = 60.0
    
    // 设置目标帧率
    func setTargetFrameRate(_ fps: Float, 
                           smooth: Bool = true)
    
    // 判断是否应该保留当前帧
    func shouldKeepFrame(timestamp: CMTime) -> Bool
    
    // 帧混合（从60fps降到30fps时）
    func blendFrames(_ frame1: CVPixelBuffer, 
                    _ frame2: CVPixelBuffer) -> CVPixelBuffer
}

// 帧率切换时间线
struct FrameRateTransition {
    let startTime: TimeInterval
    let duration: TimeInterval
    let fromFPS: Float
    let toFPS: Float
    
    func interpolatedFPS(at time: TimeInterval) -> Float
}

性能要求：
- 帧率切换延迟 < 500ms
- 过渡期间无丢帧
- CPU占用增加 < 10%
```

---

## 模块5: 高光检测系统

### Prompt 5.1: 高光检测器

```
创建HighlightDetector.swift，自动识别骑行中的精彩时刻。

检测维度：
1. 动作高光（基于传感器）：
   - 跳跃检测：加速度Z轴峰值 > 2g
   - 急转弯：角速度 > 120°/s
   - 快速加速：加速度变化率 > 0.5g/s
   - 下坡冲刺：速度 > 40km/h

2. 视觉高光（基于AI）：
   - 美景识别：日落、山景、湖泊
   - 地标建筑：桥梁、塔楼、标志性建筑
   - 特殊场景：隧道、山洞、特殊光影

3. 综合评分：
   - 动作分数（0-50分）
   - 视觉分数（0-50分）
   - 总分 > 60 判定为高光时刻

评分算法：
func calculateScore(motion: MotionData, 
                   scene: ScenePrediction) -> Float {
    var score: Float = 0.0
    
    // 动作评分
    if motion.acceleration.z > 2.0 {
        score += 30.0  // 跳跃
    }
    if motion.angularVelocity > 120.0 {
        score += 25.0  // 急转
    }
    if motion.speed > 40.0 {
        score += 20.0  // 高速
    }
    
    // 视觉评分
    if scene.sceneType == .sunset {
        score += 40.0
    }
    if scene.sceneType == .bridge {
        score += 30.0
    }
    
    return min(score, 100.0)
}

实现要求：
1. 实时评分每一帧
2. 高光时刻自动标记（添加书签）
3. 连续高光合并（间隔<3秒的合并为一个）
4. 高光片段提取（前后各扩展2秒）

输出结构：
struct HighlightMoment {
    let id: UUID
    let timestamp: TimeInterval
    let duration: TimeInterval
    let score: Float
    let type: HighlightType  // 动作/视觉/综合
    let description: String
    let thumbnailPath: String?
}

enum HighlightType {
    case action(ActionType)
    case visual(VisualType)
    case combined
}
```

### Prompt 5.2: 运动分析器

```
实现MotionAnalyzer.swift，深度分析传感器数据识别骑行动作。

分析功能：
1. 跳跃检测：
   - 识别离地时刻（加速度突然减小）
   - 计算腾空时间
   - 估算跳跃高度
   
2. 转弯分析：
   - 识别左转/右转
   - 计算转弯角度
   - 评估转弯激烈程度
   
3. 加速/减速检测：
   - 加速度变化率
   - 速度区间统计
   
4. 颠簸路况检测：
   - 高频振动分析
   - 路面质量评分

算法实现：
class MotionAnalyzer {
    // 跳跃检测
    func detectJump(accelerationHistory: [Vector3]) -> JumpEvent? {
        // 1. 寻找加速度骤降（离地）
        // 2. 寻找加速度骤升（落地）
        // 3. 计算腾空时间和高度
    }
    
    // 转弯检测
    func detectTurn(gyroHistory: [Vector3]) -> TurnEvent? {
        // 1. 角速度积分计算转向角度
        // 2. 识别转弯起止点
        // 3. 分类左转/右转
    }
    
    // 路况分析
    func analyzeRoadCondition(accelerationHistory: [Vector3]) -> RoadQuality {
        // FFT分析高频振动
        // 统计振动幅度和频率
    }
}

数据结构：
struct JumpEvent {
    let takeoffTime: TimeInterval
    let landingTime: TimeInterval
    let airTime: TimeInterval
    let estimatedHeight: Float  // 单位：米
}

struct TurnEvent {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let angle: Float  // 单位：度
    let direction: TurnDirection  // 左/右
    let maxAngularVelocity: Float
}

性能要求：
- 检测延迟 < 100ms
- 假阳性率 < 5%
- CPU占用 < 3%
```

### Prompt 5.3: 书签管理器

```
开发BookmarkManager.swift，管理用户和系统生成的书签。

书签类型：
1. 自动书签（系统生成）：
   - 高光时刻
   - 场景切换点
   - 特殊事件（跳跃、急转等）
   
2. 手动书签（用户创建）：
   - 语音指令触发
   - 按钮点击
   - 支持添加语音备注

功能实现：
class BookmarkManager {
    // 添加书签
    func addBookmark(at timestamp: TimeInterval, 
                    type: BookmarkType,
                    description: String?,
                    voiceNote: URL?) -> Bookmark
    
    // 批量添加（高光检测）
    func addHighlights(_ moments: [HighlightMoment]) -> [Bookmark]
    
    // 查询书签
    func getBookmarks(for recordingID: UUID,
                     filter: BookmarkFilter?) -> [Bookmark]
    
    // 删除书签
    func deleteBookmark(_ id: UUID)
    
    // 导出书签（用于视频编辑）
    func exportBookmarks(for recordingID: UUID) -> [VideoMarker]
}

数据模型：
struct Bookmark {
    let id: UUID
    let recordingID: UUID
    let timestamp: TimeInterval
    let type: BookmarkType
    let description: String
    let voiceNoteURL: URL?
    let thumbnailPath: String?
    let createdAt: Date
    var isUserCreated: Bool
}

enum BookmarkType {
    case highlight(HighlightType)
    case sceneChange(SceneType)
    case userMarked
    case jump
    case turn
    case custom(String)
}

// 视频编辑器兼容格式
struct VideoMarker {
    let timecode: String  // HH:MM:SS:FF
    let name: String
    let color: MarkerColor
}
```

---

## 模块6: 用户界面层

### Prompt 6.1: 拍摄视图控制器

```
创建RecordingViewController.swift，实现主拍摄界面。

UI布局要求：
1. 全屏相机预览层
2. 顶部HUD（半透明背景）：
   - 当前速度
   - 骑行时长
   - 已录制大小
   - 电池电量
3. 中央场景指示器：
   - 显示当前识别的场景
   - 场景切换时有过渡动画
   - 压缩模式指示灯
4. 底部控制栏：
   - 录制按钮（红色圆点）
   - 暂停/恢复
   - 手动标记按钮
   - 设置按钮

交互逻辑：
1. 录制控制：
   - 点击开始录制
- 长按录制按钮快速标记
   - 双击停止录制
   
2. 场景指示：
   - 场景变化时闪烁提示
   - 显示场景置信度
   
3. 实时反馈：
   - 每秒更新速度和距离
   - 存储空间不足警告
   - 设备过热提示

代码结构：
class RecordingViewController: UIViewController {
    // UI组件
    @IBOutlet weak var previewLayer: UIView!
    @IBOutlet weak var hudView: HUDOverlayView!
    @IBOutlet weak var sceneIndicator: SceneIndicatorView!
    @IBOutlet weak var recordButton: UIButton!
    
    // 管理器
    private let cameraManager: CameraManager
    private let sceneDetector: SceneDetector
    private let segmentManager: SegmentManager
    
    // 状态
    private var isRecording = false
    private var currentSegment: SceneSegment?
    
    // 方法
    @IBAction func recordButtonTapped(_ sender: UIButton)
    @IBAction func manualMarkButtonTapped(_ sender: UIButton)
    func updateHUD()
    func handleSceneChange(_ event: SceneChangeEvent)
}

请使用SwiftUI或UIKit实现，包含：
- 完整的视图层次
- 自动布局约束
- 动画效果
- 深色模式适配
```

### Prompt 6.2: HUD叠加视图

```
实现HUDOverlayView.swift，显示骑行实时数据。

显示元素：
1. 左上角：
   - 当前速度（大号字体，km/h）
   - 平均速度（小号字体）
   
2. 右上角：
   - 录制时长（HH:MM:SS）
   - 存储占用（GB）
   
3. 底部小地图（可选）：
   - 骑行轨迹
   - 当前位置标记

设计要求：
1. 半透明黑色背景（alpha: 0.6）
2. 白色文字，高对比度
3. 使用SF Symbols图标
4. 支持横竖屏自动调整
5. 可点击展开详细统计

动画效果：
- 速度变化时数字滚动动画
- 新书签添加时脉冲效果
- 警告信息淡入淡出

SwiftUI实现：
struct HUDOverlayView: View {
    @ObservedObject var viewModel: HUDViewModel
    
    var body: some View {
        ZStack {
            // 顶部栏
            VStack {
                HStack {
                    // 速度显示
                    VStack(alignment: .leading) {
                        Text("\(viewModel.currentSpeed, specifier: "%.1f")")
                            .font(.system(size: 48, weight: .bold))
                        Text("平均 \(viewModel.avgSpeed, specifier: "%.1f") km/h")
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    // 时间和存储
                    VStack(alignment: .trailing) {
                        Text(viewModel.duration)
                            .font(.title2)
                        Text("\(viewModel.storageUsed, specifier: "%.2f") GB")
                            .font(.caption)
                    }
                }
                .padding()
                .background(.black.opacity(0.6))
                
                Spacer()
            }
            
            // 警告消息
            if let warning = viewModel.warning {
                WarningBanner(message: warning)
            }
        }
    }
}

ViewModel：
class HUDViewModel: ObservableObject {
    @Published var currentSpeed: Double = 0.0
    @Published var avgSpeed: Double = 0.0
    @Published var duration: String = "00:00:00"
    @Published var storageUsed: Double = 0.0
    @Published var warning: String?
    
    func update(with sensorData: SensorFrame)
}
```

### Prompt 6.3: 场景指示器视图

```
创建SceneIndicatorView.swift，美观地显示当前场景信息。

UI设计：
1. 中央卡片式设计
2. 毛玻璃效果背景
3. 显示内容：
   - 场景图标（SF Symbol或自定义）
   - 场景名称
   - AI置信度（进度环）
   - 场景描述（可选展开）

交互：
- 点击展开完整描述
- 向下滑动隐藏
- 场景切换时卡片翻转动画

SwiftUI实现：
struct SceneIndicatorView: View {
    @Binding var scene: SceneType
    @Binding var confidence: Float
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 12) {
            // 场景图标
            Image(systemName: scene.iconName)
                .font(.system(size: 40))
                .foregroundColor(.white)
            
            // 场景名称
            Text(scene.rawValue)
                .font(.headline)
                .foregroundColor(.white)
            
            // 置信度环
            CircularProgressView(progress: confidence)
                .frame(width: 60, height: 60)
            
            // 展开的描述
            if isExpanded {
                Text(scene.description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .onTapGesture {
            withAnimation(.spring()) {
                isExpanded.toggle()
            }
        }
        .rotation3DEffect(
            .degrees(scene.hashValue % 2 == 0 ? 0 : 360),
            axis: (x: 0, y: 1, z: 0)
        )
    }
}

// 场景切换动画
extension SceneType {
    var iconName: String {
        switch self {
        case .urbanRoad: return "car.fill"
        case .parkPath: return "tree.fill"
        case .mountainTrail: return "mountain.2.fill"
        case .riverside: return "water.waves"
        // ... 其他场景
        default: return "location.fill"
        }
    }
}
```

---

## 模块7: 数据持久化

### Prompt 7.1: 数据库管理器

```
实现DatabaseManager.swift，使用SQLite管理所有持久化数据。

数据库Schema设计：

-- 骑行记录表
CREATE TABLE recordings (
    id TEXT PRIMARY KEY,
    start_time REAL NOT NULL,
    end_time REAL,
    total_distance REAL,
    avg_speed REAL,
    max_speed REAL,
    total_duration REAL,
    total_ascent REAL,  -- 总爬升
    total_descent REAL, -- 总下降
    created_at TEXT NOT NULL,
    thumbnail_path TEXT
);

-- 场景片段表
CREATE TABLE scene_segments (
    id TEXT PRIMARY KEY,
    recording_id TEXT NOT NULL,
    start_time REAL NOT NULL,
    end_time REAL,
    scene_type TEXT NOT NULL,
    description TEXT,
    location_lat REAL,
    location_lon REAL,
    avg_speed REAL,
    video_path TEXT NOT NULL,
    thumbnail_path TEXT,
    is_compressed INTEGER DEFAULT 0,
    compression_ratio REAL,
    created_at TEXT NOT NULL,
    FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
);

-- 书签表
CREATE TABLE bookmarks (
    id TEXT PRIMARY KEY,
    recording_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    type TEXT NOT NULL,
    description TEXT,
    voice_note_path TEXT,
    thumbnail_path TEXT,
    is_user_created INTEGER DEFAULT 0,
    created_at TEXT NOT NULL,
    FOREIGN KEY(recording_id) REFERENCES recordings(id) ON DELETE CASCADE
);

-- 索引
CREATE INDEX idx_segments_recording ON scene_segments(recording_id);
CREATE INDEX idx_bookmarks_recording ON bookmarks(recording_id);
CREATE INDEX idx_recordings_date ON recordings(created_at DESC);

实现要求：
1. 使用SQLite.swift或GRDB框架
2. 提供类型安全的查询接口
3. 支持事务
4. 数据迁移机制（版本升级）
5. 查询性能优化

代码结构：
class DatabaseManager {
    static let shared = DatabaseManager()
    private let db: Connection
    
    // 初始化和迁移
    init() throws
    func migrate() throws
    
    // Recording操作
    func createRecording(_ recording: Recording) throws -> Recording
    func updateRecording(_ recording: Recording) throws
    func getRecording(id: UUID) throws -> Recording?
    func getAllRecordings(limit: Int?, offset: Int?) throws -> [Recording]
    func deleteRecording(id: UUID) throws
    
    // Segment操作
    func createSegment(_ segment: SceneSegment) throws -> SceneSegment
    func updateSegment(_ segment: SceneSegment) throws
    func getSegments(forRecording id: UUID) throws -> [SceneSegment]
    func deleteSegment(id: UUID) throws
    
    // Bookmark操作
    func createBookmark(_ bookmark: Bookmark) throws -> Bookmark
    func getBookmarks(forRecording id: UUID) throws -> [Bookmark]
    func deleteBookmark(id: UUID) throws
    
    // 统计查询
    func getTotalStats() throws -> RidingStats
}

struct RidingStats {
    let totalRecordings: Int
    let totalDistance: Double
    let totalDuration: TimeInterval
    let avgSpeed: Double
}
```

### Prompt 7.2: 文件系统管理器

```
创建FileSystemManager.swift，管理视频文件和缩略图的存储。

目录结构设计：
Documents/
├── Recordings/
│   ├── {recording_id}/
│   │   ├── segments/
│   │   │   ├── {segment_id}.mov
│   │   │   ├── {segment_id}_compressed.mov
│   │   │   └── ...
│   │   ├── thumbnails/
│   │   │   ├── {segment_id}.jpg
│   │   │   └── ...
│   │   ├── bookmarks/
│   │   │   ├── {bookmark_id}_voice.m4a
│   │   │   └── ...
│   │   └── metadata.json
│   └── ...
└── Temp/
    └── current_recording/

功能实现：
class FileSystemManager {
    static let shared = FileSystemManager()
    
    private let documentsURL: URL
    private let recordingsURL: URL
    private let tempURL: URL
    
    // 目录管理
    func createRecordingDirectory(for recordingID: UUID) throws -> URL
    func getSegmentDirectory(for recordingID: UUID) throws -> URL
    func getThumbnailDirectory(for recordingID: UUID) throws -> URL
    
    // 文件操作
    func saveSegmentVideo(_ data: Data, 
                         for segmentID: UUID,
                         in recordingID: UUID) throws -> URL
    
    func saveSegmentVideo(from tempURL: URL,
                         for segmentID: UUID,
                         in recordingID: UUID) throws -> URL
    
    func saveThumbnail(_ image: UIImage,
                      for segmentID: UUID,
                      in recordingID: UUID) throws -> URL
    
    func saveVoiceNote(_ audioURL: URL,
                      for bookmarkID: UUID,
                      in recordingID: UUID) throws -> URL
    
    // 文件检索
    func getSegmentVideoURL(segmentID: UUID, 
                           recordingID: UUID) -> URL?
    
    func getThumbnailURL(segmentID: UUID,
                        recordingID: UUID) -> URL?
    
    // 文件删除
    func deleteRecording(_ recordingID: UUID) throws
    func deleteSegment(_ segmentID: UUID, 
                      in recordingID: UUID) throws
    
    // 存储管理
    func calculateStorageUsage(for recordingID: UUID) throws -> Int64
    func getTotalStorageUsage() throws -> Int64
    func cleanupTempFiles() throws
    
    // 导出
    func exportRecording(_ recordingID: UUID, 
                        to destinationURL: URL) async throws
}

文件命名规范：
- 视频片段：{segmentID}.mov
- 压缩视频：{segmentID}_compressed.mov
- 缩略图：{segmentID}.jpg
- 语音备注：{bookmarkID}_voice.m4a
```

### Prompt 7.3: 缩略图生成器

```
实现ThumbnailGenerator.swift，从视频中提取缩略图。

功能需求：
1. 从视频中间帧提取缩略图
2. 支持批量生成
3. 异步处理不阻塞主线程
4. 缓存机制避免重复生成
5. 支持自定义尺寸

实现细节：
class ThumbnailGenerator {
    static let shared = ThumbnailGenerator()
    
    // 缓存
    private let imageCache = NSCache<NSString, UIImage>()
    
    // 单个缩略图生成
    func generateThumbnail(from videoURL: URL,
                          at time: CMTime? = nil,
                          size: CGSize = CGSize(width: 320, height: 180)) async throws -> UIImage {
        // 1. 创建AVAsset
        // 2. 创建AVAssetImageGenerator
        // 3. 提取指定时间的帧（默认中间）
        // 4. 缩放到目标尺寸
        // 5. 缓存结果
    }
    
    // 批量生成
    func generateThumbnails(for segments: [SceneSegment]) async throws -> [UUID: UIImage] {
        // 并发生成，最大并发数=4
    }
    
    // 从缓存获取
    func getCachedThumbnail(for segmentID: UUID) -> UIImage? {
        return imageCache.object(forKey: segmentID.uuidString as NSString)
    }
    
    // 清除缓存
    func clearCache()
}

使用AVFoundation：
let asset = AVAsset(url: videoURL)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = size

let time = time ?? CMTime(seconds: asset.duration.seconds / 2, 
                         preferredTimescale: 600)

let cgImage = try await generator.image(at: time).image
let thumbnail = UIImage(cgImage: cgImage)

性能优化：
- 使用CGImageSourceCreateThumbnailAtIndex快速生成
- 限制并发数避免内存压力
- LRU缓存策略
```

---

## 模块8: 视频编辑与导出

### Prompt 8.1: 时间线视图控制器

```
创建TimelineViewController.swift，展示可编辑的视频时间线。

UI布局：
1. 顶部预览窗口（16:9）
2. 中间时间线轨道：
   - 按场景分段显示
   - 每个片段显示缩略图
   - 书签标记点
   - 高光片段高亮显示
3. 底部工具栏：
   - 播放/暂停
   - 跳转到上/下一个场景
   - 添加/删除片段
   - 导出按钮

交互功能：
1. 片段操作：
   - 点击选中片段
   - 拖动调整边界
   - 长按删除
   - 双击播放预览
   
2. 播放控制：
   - 拖动播放头
   - 倍速播放（0.5x, 1x, 2x）
   - 帧步进（逐帧查看）
   
3. 编辑功能：
   - 分割片段
   - 合并相邻片段
   - 调整片段顺序
   - 修改场景描述

代码结构：
class TimelineViewController: UIViewController {
    // UI组件
    @IBOutlet weak var previewView: VideoPreviewView!
    @IBOutlet weak var timelineView: TimelineTrackView!
    @IBOutlet weak var toolbarView: UIView!
    
    // 数据
    private var recording: Recording
    private var segments: [SceneSegment] = []
    private var player: AVPlayer?
    
    // 状态
    private var selectedSegment: SceneSegment?
    private var playbackRate: Float = 1.0
    
    // 方法
    func loadRecording(_ id: UUID)
    func playSegment(_ segment: SceneSegment)
    func splitSegment(_ segment: SceneSegment, at time: TimeInterval)
    func mergeSegments(_ segment1: SceneSegment, _ segment2: SceneSegment)
    func deleteSegment(_ segment: SceneSegment)
    func exportVideo()
}

使用SwiftUI实现时间线：
struct TimelineTrackView: View {
    @Binding var segments: [SceneSegment]
    @Binding var selectedID: UUID?
    @Binding var playheadPosition: TimeInterval
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    SegmentThumbnailView(segment: segment)
                        .frame(width: segmentWidth(segment))
                        .border(selectedID == segment.id ? Color.blue : Color.clear, width: 3)
                        .onTapGesture {
                            selectedID = segment.id
                        }
                }
            }
            .overlay(
                PlayheadView(position: playheadPosition)
            )
        }
    }
    
    func segmentWidth(_ segment: SceneSegment) -> CGFloat {
        let duration = segment.endTime - segment.startTime
        return CGFloat(duration) * 10  // 10 points per second
    }
}
```

### Prompt 8.2: 精华集锦生成器

```
实现HighlightGenerator.swift，自动生成精彩片段集锦。

生成策略：
1. 场景评分系统：
   - 高光分数（0-100）
   - 场景独特性（避免重复相似场景）
   - 视觉质量（清晰度、曝光）
   - 时长适中（3-10秒最佳）

2. 选片逻辑：
   - Top 10高分片段
   - 至少包含3种不同场景类型
   - 总时长控制在60-90秒
   - 保持叙事连贯性（按时间顺序）

3. 转场效果：
   - 场景相似：淡入淡出
   - 场景差异大：交叉溶解
   - 动作片段：快切

4. 配乐（可选）：
   - 根据骑行节奏选择BGM
   - 音频自动对齐

实现代码：
class HighlightGenerator {
    struct GenerationConfig {
        var targetDuration: TimeInterval = 75.0  // 目标时长
        var minSegmentDuration: TimeInterval = 3.0
        var maxSegmentDuration: TimeInterval = 10.0
        var minSceneVariety: Int = 3
        var includeAudio: Bool = true
    }
    
    func generateHighlight(from recording: Recording,
                          config: GenerationConfig = .init()) async throws -> URL {
        // 1. 加载所有片段和书签
        let segments = try await loadSegments(recording)
        let highlights = try await loadHighlights(recording)
        
        // 2. 评分和筛选
        let scoredSegments = scoreSegments(segments, highlights: highlights)
        let selected = selectSegments(scoredSegments, config: config)
        
        // 3. 合成视频
        let composition = createComposition(segments: selected)
        
        // 4. 添加转场
        addTransitions(to: composition)
        
        // 5. 添加配乐（可选）
        if config.includeAudio {
            addBackgroundMusic(to: composition)
        }
        
        // 6. 导出
        return try await export(composition)
    }
    
    private func scoreSegments(_ segments: [SceneSegment],
                              highlights: [HighlightMoment]) -> [(SceneSegment, Float)] {
        segments.map { segment in
            var score: Float = 0.0
            
            // 高光分数
            let containedHighlights = highlights.filter {
                $0.timestamp >= segment.startTime && $0.timestamp <= segment.endTime
            }
            score += containedHighlights.map { $0.score }.reduce(0, +)
            
            // 场景独特性
            if segment.sceneType == .sunset || segment.sceneType == .bridge {
                score += 20.0
            }
            
            // 时长适中
            let duration = segment.endTime - segment.startTime
            if duration >= 3.0 && duration <= 10.0 {
                score += 15.0
            }
            
            return (segment, score)
        }
    }
    
    private func selectSegments(_ scored: [(SceneSegment, Float)],
                               config: GenerationConfig) -> [SceneSegment] {
        // 按分数排序
        let sorted = scored.sorted { $0.1 > $1.1 }
        
        var selected: [SceneSegment] = []
        var totalDuration: TimeInterval = 0
        var sceneTypes: Set<SceneType> = []
        
        for (segment, _) in sorted {
            // 检查时长限制
            let segmentDuration = segment.endTime - segment.startTime
            if totalDuration + segmentDuration > config.targetDuration {
                continue
            }
            
            // 添加片段
            selected.append(segment)
            totalDuration += segmentDuration
            sceneTypes.insert(segment.sceneType)
            
            // 检查是否满足条件
            if totalDuration >= config.targetDuration * 0.8 &&
               sceneTypes.count >= config.minSceneVariety {
                break
            }
        }
        
        // 按时间顺序排序
        return selected.sorted { $0.startTime < $1.startTime }
    }
    
    private func createComposition(segments: [SceneSegment]) -> AVMutableComposition {
        // 使用AVFoundation创建合成
    }
}
```

### Prompt 8.3: 视频导出管理器

```
创建ExportManager.swift，处理视频导出和分享。

导出格式选项：
1. 质量预设：
   - 原始质量（保持编码参数）
   - 高质量（H.265, 25Mbps, 1080p/60fps）
   - 标准质量（H.265, 15Mbps, 1080p/30fps）
   - 分享质量（H.265, 8Mbps, 720p/30fps）

2. 导出内容：
   - 完整骑行
   - 选定片段
   - 精华集锦
   - 单个场景

3. 元数据嵌入：
   - GPS轨迹
   - 速度数据
   - 场景标签
   - 创建时间

实现代码：
class ExportManager {
    enum ExportPreset {
        case original
        case high
        case standard
        case share
        
        var videoSettings: [String: Any] {
            switch self {
            case .original:
                return [AVVideoCodecKey: AVVideoCodecType.hevc,
                       AVVideoWidthKey: 3840,
                       AVVideoHeightKey: 2160]
            case .high:
                return [AVVideoCodecKey: AVVideoCodecType.hevc,
                       AVVideoWidthKey: 1920,
                       AVVideoHeightKey: 1080,
                       AVVideoCompressionPropertiesKey: [
                           AVVideoAverageBitRateKey: 25_000_000,
                           AVVideoExpectedSourceFrameRateKey: 60
                       ]]
            // ... 其他预设
            }
        }
    }
    
    struct ExportOptions {
        var preset: ExportPreset = .high
        var includeAudio: Bool = true
        var embedMetadata: Bool = true
        var watermark: UIImage?
        var outputFormat: UTType = .mpeg4Movie
    }
    
    func export(recording: Recording,
               segments: [SceneSegment]? = nil,
               options: ExportOptions = .init(),
               progressHandler: ((Float) -> Void)? = nil) async throws -> URL {
        
        // 1. 创建导出会话
        let composition = try createComposition(recording, segments: segments)
        
        // 2. 添加元数据
        if options.embedMetadata {
            addMetadata(to: composition, recording: recording)
        }
        
        // 3. 添加水印
        if let watermark = options.watermark {
            addWatermark(watermark, to: composition)
        }
        
        // 4. 配置导出
        let exporter = AVAssetExportSession(asset: composition,
                                           presetName: AVAssetExportPresetHEVCHighestQuality)!
        exporter.outputFileType = .mp4
        exporter.outputURL = generateOutputURL()
        exporter.videoComposition = createVideoComposition(options: options)
        
        // 5. 执行导出
        return try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                switch exporter.status {
                case .completed:
                    continuation.resume(returning: exporter.outputURL!)
                case .failed:
                    continuation.resume(throwing: exporter.error!)
                case .cancelled:
                    continuation.resume(throwing: ExportError.cancelled)
                default:
                    break
                }
            }
            
            // 进度更新
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                progressHandler?(exporter.progress)
                if exporter.status != .exporting {
                    timer.invalidate()
                }
            }
        }
    }
    
    // 分享到社交媒体
    func shareToSocialMedia(videoURL: URL,
                           platforms: [SocialPlatform]) async throws {
        // 使用UIActivityViewController或特定平台SDK
    }
}

enum SocialPlatform {
    case wechat
    case weibo
    case instagram
    case youtube
}
```

---

## 通用开发指令模板

### 代码审查Prompt

```
请审查以下Swift代码，关注：

1. **性能**：
   - 是否有内存泄漏风险（循环引用）
   - 是否有不必要的主线程阻塞
   - 是否有过度的内存分配

2. **架构**：
   - 是否遵循MVVM/MVP模式
   - 职责是否单一
   - 是否易于测试

3. **Swift最佳实践**：
   - 是否正确使用可选值
   - 是否使用现代Swift特性（async/await, Combine等）
   - 错误处理是否完善

4. **iOS适配**：
   - 是否考虑不同设备尺寸
   - 是否支持深色模式
   - 是否考虑无障碍访问

请提供具体的改进建议和重构代码。

[粘贴代码]
```

### 性能优化Prompt

```
以下代码在真机测试中出现性能问题：
- 场景：[描述使用场景]
- 问题：[CPU占用过高/内存溢出/帧率下降]
- 设备：iPhone 14 Plus

请分析性能瓶颈并提供优化方案：
1. 识别热点代码
2. 提出优化策略
3. 提供优化后的代码
4. 说明预期的性能提升

[粘贴代码]
```

### 单元测试Prompt

```
为以下类编写完整的单元测试：

测试要求：
1. 使用XCTest框架
2. 覆盖所有公开方法
3. 包含边界条件测试
4. Mock外部依赖
5. 测试异步代码（使用expectation）
6. 测试错误处理

请提供：
- 完整的测试类
- 测试用例说明
- Mock对象实现
- 测试数据准备代码

[粘贴需要测试的类]
```

---

## 集成测试场景Prompt

```
创建集成测试脚本，测试以下端到端场景：

场景：完整的录制-编辑-导出流程

步骤：
1. 启动应用并请求权限
2. 开始录制（模拟30分钟骑行）
3. 模拟场景变化（5次）
4. 模拟高光时刻（3次）
5. 停止录制
6. 打开时间线编辑器
7. 生成精华集锦
8. 导出视频

验证点：
- 所有场景正确分段
- 高光检测准确
- 视频文件完整性
- 内存使用稳定
- 无崩溃或卡顿

请使用XCUITest编写自动化测试代码。
```

---

这套完整的Code Agent指令集涵盖了项目的所有核心模块，每个prompt都包含：
- 清晰的功能需求
- 技术规格说明
- 代码结构建议
- 性能要求
- 实现示例

开发时可以按模块顺序使用这些prompt，确保AI助手生成符合项目规范的高质量代码。