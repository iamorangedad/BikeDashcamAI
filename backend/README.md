# BikeDashcamAI Backend

实时视频流处理服务，用于对拍摄的视频进行智能剪辑。

## 功能特性

- **场景变化检测**: 基于帧差异和直方图变化的智能场景检测
- **帧优化**: 每个场景保留3-5帧，减少卡顿
- **WebSocket实时通信**: 支持实时视频流传输和处理
- **自适应处理**: 可配置的参数（阈值、帧数范围等）

## 安装

```bash
pip install -r requirements.txt
```

## 运行

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API端点

- `GET /`: 服务信息
- `GET /health`: 健康检查
- `POST /api/detect_scene`: 初始化场景检测器
- `WS /ws/{client_id}`: WebSocket视频流端点

## WebSocket消息格式

### 客户端发送
```json
{
  "type": "frame",
  "data": "base64_encoded_jpg"
}
```

### 服务端返回
```json
{
  "type": "processed_frame",
  "data": "base64_encoded_jpg",
  "timestamp": "2024-01-19T13:21:00"
}
```
