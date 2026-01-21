"""
测试配置文件
配置测试环境和共享的fixtures
"""

import pytest
import asyncio
import sys
import os

# 添加backend目录到Python路径
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "backend"))


@pytest.fixture(scope="session")
def event_loop():
    """创建一个事件循环用于异步测试"""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
def sample_frame_data():
    """生成示例帧数据用于测试"""
    import base64

    return base64.b64encode(b"fake_frame_data").decode()


@pytest.fixture
def websocket_client():
    """创建WebSocket客户端fixture"""
    try:
        from fastapi.testclient import TestClient
        from app.main import app

        return TestClient(app)
    except ImportError:
        return None


@pytest.fixture
def api_client():
    """创建API客户端fixture"""
    try:
        from fastapi.testclient import TestClient
        from app.main import app

        return TestClient(app)
    except ImportError:
        return None


@pytest.fixture
def scene_detector_config():
    """场景检测器配置"""
    return {"threshold": 0.3, "min_frames": 3, "max_frames": 5}


@pytest.fixture
def video_processor_config():
    """视频处理器配置"""
    return {
        "fps": 30,
        "output_width": 1280,
        "output_height": 720,
        "scene_threshold": 0.3,
        "min_frames_per_scene": 3,
        "max_frames_per_scene": 5,
    }
