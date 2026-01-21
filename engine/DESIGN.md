# 视频搜索引擎系统架构设计

## 1. 系统概述

端到端的 MVP 智能视频搜索引擎，支持自然语言查询，返回匹配的视频片段和时间戳。

## 2. 技术架构

### 2.1 数据准备模块
- 数据集：MSR-VTT 或 ActivityNet
- 数据处理：
  - 视频分帧：每秒提取 8-16 帧
  - 片段分割：5-10 秒为单位的滑动窗口
  - 数据预处理：归一化、Resize 到统一尺寸

### 2.2 模型层

#### 2.2.1 视频帧特征提取 (SigLIP)
- 模型：SigLIP (Sigmoid Loss for Language Image Pre-training)
- 输入：视频帧图像 (224x224)
- 输出：768 维或更大维度特征向量
- 特点：多模态文本-图像联合训练

#### 2.2.2 时序特征提取 (TimeSformer)
- 模型：TimeSformer (Video Transformer)
- 输入：视频帧序列 (16帧，每帧 224x224)
- 输出：时序感知特征向量
- 特点：自注意力机制捕获时间依赖

#### 2.2.3 特征融合
- 加权融合策略：
  ```python
  fused_feature = α * siglip_features + β * timesformer_features
  ```
  - α, β 为可学习权重或固定超参数
  - 归一化到单位长度

### 2.3 索引层 (Milvus)

#### 2.3.1 向量库配置
- Collection 结构：
  - video_id: 视频标识符
  - start_time: 片段起始时间戳
  - end_time: 片段结束时间戳
  - feature_vector: 融合后的特征向量 (1024 维)
  - metadata: 额外元数据（如场景标签）

#### 2.3.2 索引类型
- 索引算法：HNSW (Hierarchical Navigable Small World)
- 参数：
  - M: 16 (连接数)
  - efConstruction: 200 (构建时的搜索深度)
  - ef: 64 (查询时的搜索深度)
- 度量：余弦相似度或内积

### 2.4 服务层

#### 2.4.1 TensorRT 优化
- SigLIP → TensorRT Engine
- TimeSformer → TensorRT Engine
- 特征融合 → TensorRT Plugin

#### 2.4.2 Triton Inference Server
- 模型仓库结构：
  ```
  models/
    ├── siglip/
    │   └── 1/
    │       ├── model.plan
    │       └── config.pbtxt
    ├── timesformer/
    │   └── 1/
    │       ├── model.plan
    │       └── config.pbtxt
    └── fusion/
        └── 1/
            ├── model.plan
            └── config.pbtxt
  ```
- 推理链：
  1. 客户端请求 → Triton
  2. Triton 调用 SigLIP 提取帧特征
  3. Triton 调用 TimeSformer 提取时序特征
  4. Triton 调用融合模块
  5. 返回融合特征

#### 2.4.3 性能优化
- 动态批处理 (Dynamic Batching)
- 模型并发 (Model Ensemble)
- GPU 内存管理

### 2.5 应用层 (API 服务)

#### 2.5.1 API 接口
- 框架：FastAPI
- 端点设计：

  **POST /search**
  ```json
  {
    "query": "一只狗在草地上接飞盘",
    "top_k": 10,
    "threshold": 0.7
  }
  ```
  **响应：**
  ```json
  {
    "results": [
      {
        "video_id": "Video_03.mp4",
        "start_time": "00:15",
        "end_time": "00:20",
        "score": 0.92,
        "thumbnail": "/thumbnails/video3_15_20.jpg"
      }
    ],
    "latency_ms": 125
  }
  ```

  **POST /index**
  ```json
  {
    "video_path": "/data/videos/new_video.mp4",
    "video_id": "Video_100"
  }
  ```

  **GET /health**
  健康检查

#### 2.5.2 查询流程
1. 用户输入自然语言查询
2. 使用文本编码器（如 CLIP Text Encoder）将查询转换为向量
3. 在 Milvus 中进行向量搜索
4. 返回 Top-K 结果和时间戳

#### 2.5.3 文本编码器
- 模型：CLIP Text Encoder 或 SigLIP Text Tower
- 输出：与视频特征相同维度的文本向量

### 2.6 评估模块

#### 2.6.1 评估指标
- **R@10 (Recall at 10)**: 前10个结果中正确结果的比例
- **R@5, R@1**: 不同阈值的召回率
- **mAP (mean Average Precision)**: 平均精度均值
- **Latency**: 平均推理延迟
  - 单个查询延迟
  - 批量查询延迟

#### 2.6.2 评估数据集
- 使用 MSR-VTT 的测试集
- 预定义的文本查询对

#### 2.6.3 评估脚本
- 批量查询测试集
- 计算各项指标
- 生成评估报告

## 3. 系统工作流程

### 3.1 离线索引流程
```
视频数据集 → 视频分帧 → SigLIP 提取帧特征 → TimeSformer 提取时序特征
   ↓                                              ↓
片段分割 ← 特征融合 ← 加权组合 ← 归一化
   ↓
Milvus 向量库 (HNSW 索引)
```

### 3.2 在线查询流程
```
自然语言查询 → 文本编码器 → 文本向量
                                        ↓
                          Milvus 向量检索 (余弦相似度)
                                        ↓
              Top-K 结果 → 过滤阈值 → 返回 (视频ID + 时间戳)
```

## 4. 部署架构

### 4.1 Docker 容器化
```
┌─────────────────────────────────────┐
│   Docker Compose                    │
│   ┌─────────────┐  ┌─────────────┐ │
│   │ Triton      │  │ Milvus      │ │
│   │ Inference   │  │ Vector DB   │ │
│   │ Server      │  │             │ │
│   └─────────────┘  └─────────────┘ │
│   ┌─────────────┐  ┌─────────────┐ │
│   │ FastAPI     │  │ Redis       │ │
│   │ App Server  │  │ Cache       │ │
│   └─────────────┘  └─────────────┘ │
└─────────────────────────────────────┘
```

### 4.2 资源需求
- GPU: NVIDIA RTX 3090 或更高 (推理优化)
- 内存: 32GB+
- 存储: 500GB+ (视频数据 + 向量索引)

## 5. 目录结构

```
BikeDashcamAI/engine/
├── README.md
├── DESIGN.md (本文件)
├── requirements.txt
├── docker-compose.yml
├── data/
│   ├── raw/              # 原始视频数据集
│   ├── processed/        # 处理后的视频帧
│   └── features/         # 提取的特征向量
├── models/
│   ├── siglip/
│   │   ├── export.py     # 导出 TensorRT
│   │   └── infer.py      # 推理脚本
│   ├── timesformer/
│   │   ├── export.py
│   │   └── infer.py
│   └── fusion/
│       ├── fusion.py     # 特征融合逻辑
│       └── export.py
├── triton/
│   ├── models/
│   │   ├── siglip/1/
│   │   ├── timesformer/1/
│   │   └── fusion/1/
│   └── config/
├── milvus/
│   ├── connection.py     # Milvus 连接管理
│   ├── collection.py     # Collection 操作
│   └── search.py         # 搜索逻辑
├── api/
│   ├── main.py           # FastAPI 主程序
│   ├── routers/
│   │   ├── search.py
│   │   └── index.py
│   └── schemas.py        # Pydantic 模型
├── evaluation/
│   ├── metrics.py        # 评估指标计算
│   ├── test_queries.json # 测试查询集
│   └── evaluate.py       # 评估脚本
└── scripts/
    ├── download_data.py  # 下载数据集
    ├── extract_frames.py # 视频分帧
    ├── build_index.py    # 构建向量索引
    └── benchmark.py      # 性能测试
```

## 6. 开发计划

### Phase 1: 数据准备 (Week 1)
- 下载 MSR-VTT 数据集
- 实现视频分帧脚本
- 数据预处理流水线

### Phase 2: 模型实现 (Week 2-3)
- 实现 SigLIP 特征提取
- 实现 TimeSformer 时序特征提取
- 实现特征融合逻辑

### Phase 3: TensorRT 优化 (Week 4)
- 导出 SigLIP 到 TensorRT
- 导出 TimeSformer 到 TensorRT
- 部署到 Triton Server

### Phase 4: 索引层 (Week 5)
- 搭建 Milvus 向量库
- 构建 HNSW 索引
- 实现批量索引

### Phase 5: 应用层 (Week 6)
- 实现 FastAPI 服务
- 集成文本编码器
- 实现查询接口

### Phase 6: 评估 (Week 7)
- 实现 R@10, mAP 指标
- 性能基准测试
- 优化和调优

## 7. 性能目标

- 索引吞吐量: > 100 视频片段/秒
- 查询延迟: < 200ms (单次查询)
- R@10: > 60% (MSR-VTT 测试集)
- mAP: > 40% (MSR-VTT 测试集)
- 并发查询: 支持 10+ 并发

## 8. 技术栈总结

- 深度学习: PyTorch, HuggingFace Transformers
- 模型优化: TensorRT, ONNX
- 推理服务: NVIDIA Triton Inference Server
- 向量数据库: Milvus
- API 框架: FastAPI, Uvicorn
- 容器化: Docker, Docker Compose
- 数据处理: FFmpeg, OpenCV
- 评估: scikit-learn, NumPy
