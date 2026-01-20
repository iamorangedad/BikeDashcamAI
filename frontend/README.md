# BikeDashcamAI Frontend

React Native移动应用，用于实时视频拍摄和流传输。

## 功能特性

- **实时相机预览**: 支持前后摄像头切换
- **视频流传输**: 通过WebSocket实时发送视频帧
- **处理结果展示**: 显示后端处理后的视频帧
- **连接状态监控**: 实时显示连接和流状态
- **可配置参数**: 支持自定义帧率、质量等参数

## 安装

```bash
npm install
```

## 运行

```bash
# iOS
npm run ios

# Android
npm run android

# Web
npm run web
```

## 配置

在应用启动时配置：
- WebSocket服务器URL
- 客户端ID
- 相机参数（帧率、质量、分辨率）

## 使用说明

1. 输入WebSocket服务器URL和客户端ID
2. 点击"Connect"连接服务器
3. 连接成功后，点击"Start Streaming"开始视频流传输
4. 处理后的帧将显示在屏幕下方
5. 点击"Stop"停止传输

## 技术栈

- React Native
- Expo
- Expo Camera
- WebSocket
- TypeScript
