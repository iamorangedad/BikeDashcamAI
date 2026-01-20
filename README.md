# BikeDashcamAI

实时视频流智能剪辑系统，通过检测画面差异自动剪辑视频，减少卡顿效果。

## 项目架构

```
BikeDashcamAI/
├── backend/                 # 后端服务
│   ├── app/
│   │   ├── main.py         # FastAPI应用入口
│   │   ├── api/
│   │   │   └── websocket.py # WebSocket端点
│   │   └── services/
│   │       ├── scene_detector.py    # 场景变化检测
│   │       └── video_processor.py   # 视频处理核心
│   ├── requirements.txt
│   └── README.md
├── frontend/                # React Native前端
│   ├── App.tsx            # 主应用
│   ├── src/
│   │   ├── components/
│   │   │   ├── CameraView.tsx       # 相机视图
│   │   │   └── VideoStreamer.tsx    # 视频流发送器
│   │   ├── services/
│   │   │   └── websocket.ts         # WebSocket服务
│   │   └── types/
│   │       └── video.ts             # 类型定义
│   ├── package.json
│   └── README.md
└── README.md
```

## 技术栈

### 后端
- **框架**: FastAPI
- **视频处理**: OpenCV
- **通信**: WebSocket
- **语言**: Python

### 前端
- **框架**: React Native + Expo
- **相机**: Expo Camera
- **通信**: WebSocket
- **语言**: TypeScript

## 核心功能

### 场景变化检测
- 基于帧差异和直方图变化的综合检测
- 可配置的检测阈值
- 自适应帧数保留策略

### 智能帧优化
- 每个场景保留3-5帧关键帧
- 减少冗余帧，降低处理负担
- 保持视频流畅性

### 实时处理
- WebSocket双向通信
- 低延迟视频流传输
- 实时反馈处理结果

## 快速开始

### 后端设置

```bash
cd backend
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 前端设置

```bash
cd frontend
npm install
npm run ios    # iOS
npm run android # Android
npm run web    # Web (仅用于测试)
```

## 使用说明

1. 启动后端服务
2. 启动前端应用
3. 在前端输入WebSocket服务器地址（默认: `ws://localhost:8000/ws/device1`）
4. 点击"Connect"连接服务器
5. 点击"Start Streaming"开始视频流传输
6. 后端自动检测场景变化并优化帧数
7. 查看处理结果和统计信息

## API文档

启动后端后，访问 http://localhost:8000/docs 查看完整API文档。

## 配置参数

### 后端配置 (backend/app/main.py)
- `fps`: 视频帧率 (默认: 30)
- `output_width`: 输出宽度 (默认: 1280)
- `output_height`: 输出高度 (默认: 720)
- `scene_threshold`: 场景检测阈值 (默认: 0.3)
- `min_frames_per_scene`: 每场景最少帧数 (默认: 3)
- `max_frames_per_scene`: 每场景最多帧数 (默认: 5)

### 前端配置 (frontend/App.tsx)
- `frameRate`: 相机帧率 (默认: 30)
- `quality`: 图像质量 (默认: medium)
- `width`: 视频宽度 (默认: 1280)
- `height`: 视频高度 (默认: 720)

## 项目特点

1. **智能剪辑**: 自动识别场景变化，只保留关键帧
2. **实时处理**: 边拍摄边处理，无需等待
3. **跨平台**: 前端支持iOS、Android和Web
4. **可扩展**: 模块化设计，易于添加新功能
5. **高性能**: 优化的视频处理算法

## 性能优化

- 使用OpenCV进行高效视频处理
- WebSocket实现低延迟通信
- 智能帧数减少降低传输和处理负担
- 并发处理多个客户端连接

## 开发计划

- [ ] 支持视频录制和本地保存
- [ ] 添加更多场景检测算法
- [ ] 实现视频回放功能
- [ ] 添加滤镜和特效
- [ ] 支持多路视频流处理

## License

MIT
