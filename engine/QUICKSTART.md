# 快速入门指南

## 环境准备

### 1. 安装 Docker 和 Docker Compose

```bash
# macOS
brew install docker docker-compose

# Ubuntu
sudo apt-get update
sudo apt-get install docker.io docker-compose
```

### 2. 克隆项目

```bash
git clone <repository-url>
cd engine
```

### 3. 配置环境变量

```bash
cp .env.example .env
# 根据实际情况修改 .env 文件
```

## 快速启动

### 1. 启动所有服务

```bash
docker-compose up -d
```

这将启动以下服务：
- Milvus 向量数据库
- MinIO 对象存储
- Redis 缓存
- Triton 推理服务器
- FastAPI 应用服务

### 2. 检查服务状态

```bash
docker-compose ps
```

### 3. 查看 API 文档

在浏览器中打开:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## 数据准备

### 1. 下载 MSR-VTT 数据集

```bash
mkdir -p data/raw
cd data/raw
# 下载 MSR-VTT 数据集
wget http://msvtt.org/...
unzip trainval_video.zip
cd ../..
```

### 2. 视频分帧

```bash
python scripts/extract_frames.py \
    --video-dir data/raw/ \
    --output-dir data/processed/frames \
    --fps 10
```

### 3. 创建 Milvus 集合

```bash
python -c "from milvus.connection import connect_to_milvus, create_video_fragment_collection; connect_to_milvus(); create_video_fragment_collection()"
```

## 模型导出

### 1. 导出 SigLIP 模型

```bash
python models/siglip/export.py
```

这将生成:
- `siglip.onnx`: ONNX 格式模型
- `siglip.plan`: TensorRT 引擎

### 2. 导出 TimeSformer 模型

```bash
python models/timesformer/export.py
```

### 3. 导出融合模型

```bash
python models/fusion/fusion.py
```

### 4. 将模型部署到 Triton

```bash
# 将生成的 .plan 文件复制到 Triton 模型目录
cp models/siglip/siglip.plan triton/models/siglip/1/model.plan
cp models/timesformer/timesformer.plan triton/models/timesformer/1/model.plan
cp models/fusion/fusion.plan triton/models/fusion/1/model.plan

# 重启 Triton 服务
docker-compose restart triton
```

## API 使用示例

### 搜索视频

```bash
curl -X POST "http://localhost:8000/api/v1/search" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "一只狗在草地上接飞盘",
    "top_k": 10,
    "threshold": 0.7
  }'
```

### 健康检查

```bash
curl http://localhost:8000/health
```

## 评估系统

### 1. 运行评估

```bash
cd evaluation
python evaluate.py
```

这将:
- 加载测试查询
- 执行搜索
- 计算评估指标（R@10, mAP, 延迟等）
- 生成评估报告

### 2. 查看评估结果

```bash
cat evaluation_results.json
```

## 常用命令

### 查看日志

```bash
# 所有服务日志
docker-compose logs -f

# 特定服务日志
docker-compose logs -f api
docker-compose logs -f triton
docker-compose logs -f milvus-standalone
```

### 停止服务

```bash
docker-compose down
```

### 重启服务

```bash
docker-compose restart api
```

### 进入容器

```bash
docker-compose exec api bash
docker-compose exec triton bash
```

## 性能测试

### 使用 Apache Bench 进行压测

```bash
# 安装 ab
brew install httpie  # macOS
sudo apt-get install apache2-utils  # Ubuntu

# 测试搜索接口
ab -n 1000 -c 10 -p search_payload.json -T application/json \
  http://localhost:8000/api/v1/search
```

## 故障排查

### Milvus 连接失败

```bash
# 检查 Milvus 状态
docker-compose logs milvus-standalone

# 检查端口
netstat -an | grep 19530
```

### Triton 模型加载失败

```bash
# 检查模型文件
ls -l triton/models/*/1/

# 检查 Triton 日志
docker-compose logs triton
```

### API 响应慢

```bash
# 检查 GPU 使用情况
nvidia-smi

# 检查 API 日志
docker-compose logs api
```

## 下一步

1. 准备更多视频数据
2. 调整模型参数
3. 优化性能
4. 添加更多评估指标
5. 部署到生产环境

## 参考文档

- [FastAPI 文档](https://fastapi.tiangolo.com/)
- [Milvus 文档](https://milvus.io/docs)
- [Triton 文档](https://developer.nvidia.com/triton-inference-server)
- [TensorRT 文档](https://docs.nvidia.com/deeplearning/tensorrt/)
