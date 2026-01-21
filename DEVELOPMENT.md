# BikeDashcamAI 开发环境指南

## 使用uv构建本地开发环境

### 1. 安装uv

```bash
# macOS/Linux
curl -LsSf https://astral.sh/uv/install.sh | sh

# 重启终端或运行
source ~/.bashrc
```

### 2. 设置项目环境

```bash
# 运行自动设置脚本
python scripts/setup_dev.py

# 或手动设置
uv venv
source .venv/bin/activate  # Windows: .venv\\Scripts\\activate
uv pip install -e .
uv pip install -e '.[test,dev]'
```

### 3. 开发工具快捷命令

项目提供了便捷的开发工具脚本：

```bash
# 运行测试
python scripts/dev.py test

# 运行测试并生成覆盖率报告
python scripts/dev.py coverage

# 代码格式化和检查
python scripts/dev.py lint

# 类型检查
python scripts/dev.py typecheck

# 启动开发服务器
python scripts/dev.py server

# 生产模式服务器
python scripts/dev.py server --prod

# 安装依赖
python scripts/dev.py install
```

### 4. 常用开发命令

#### 测试相关
```bash
# 运行所有测试
pytest

# 运行特定测试文件
pytest tests/test_api.py

# 运行特定测试类
pytest tests/test_api.py::TestHealthEndpoints

# 运行特定测试方法
pytest tests/test_api.py::TestHealthEndpoints::test_health_check

# 生成覆盖率报告
pytest --cov=backend/app --cov-report=html

# 运行集成测试
pytest -m integration

# 跳过慢速测试
pytest -m "not slow"
```

#### 代码质量
```bash
# 代码格式化
black backend/ tests/

# 导入排序
isort backend/ tests/

# 代码检查
flake8 backend/ tests/

# 类型检查
mypy backend/
```

#### 服务器运行
```bash
# 开发模式（热重载）
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# 生产模式
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### 5. 项目结构

```
BikeDashcamAI/
├── backend/                 # 后端代码
│   └── app/
│       ├── main.py         # FastAPI应用入口
│       ├── api/            # API路由
│       └── services/       # 业务逻辑
├── tests/                  # 测试代码
│   ├── test_api.py        # API测试
│   ├── test_websocket.py  # WebSocket测试
│   ├── test_services.py   # 服务测试
│   ├── test_integration.py # 集成测试
│   └── conftest.py        # 测试配置
├── k8s/                    # Kubernetes配置
├── scripts/               # 开发脚本
│   ├── setup_dev.py       # 环境设置
│   └── dev.py            # 开发工具
├── pyproject.toml         # 项目配置
└── pytest.ini            # pytest配置
```

### 6. 环境变量配置

创建 `.env` 文件（可选）：

```env
RTSP_STREAM_URL=rtsp://10.0.0.75:8554/stream
ENVIRONMENT=development
LOG_LEVEL=INFO
FPS=30
OUTPUT_WIDTH=1280
OUTPUT_HEIGHT=720
SCENE_THRESHOLD=0.3
MIN_FRAMES_PER_SCENE=3
MAX_FRAMES_PER_SCENE=5
PYTHONPATH=/workspace/backend
```

### 7. IDE配置

#### VS Code
推荐安装扩展：
- Python
- Pylance
- Black Formatter
- isort

配置 `.vscode/settings.json`：

```json
{
    "python.defaultInterpreterPath": "./.venv/bin/python",
    "python.formatting.provider": "black",
    "python.linting.enabled": true,
    "python.linting.flake8Enabled": true,
    "python.sortImports.args": ["--profile", "black"],
    "editor.formatOnSave": true,
    "editor.codeActionsOnSave": {
        "source.organizeImports": true
    }
}
```

### 8. 故障排除

#### 依赖安装问题
```bash
# 清理缓存
uv cache clean

# 重新创建环境
rm -rf .venv
uv venv
source .venv/bin/activate
uv pip install -e '.[test,dev]'
```

#### 测试问题
```bash
# 检查Python路径
python -c "import sys; print(sys.path)"

# 检查导入
python -c "from app.main import app; print('OK')"
```

#### 服务连接问题
```bash
# 检查端口占用
lsof -i :8000

# 检查服务状态
curl http://localhost:8000/health
```

### 9. 部署测试

```bash
# 本地测试后端服务
python scripts/dev.py server

# 在另一个终端运行测试
python scripts/dev.py test

# 运行集成测试（需要服务运行）
python scripts/dev.py test -m integration
```

### 10. 代码提交前检查

```bash
# 运行完整检查
python scripts/dev.py lint
python scripts/dev.py typecheck
python scripts/dev.py coverage

# 或使用pre-commit hooks（如果配置）
pre-commit run --all-files
```