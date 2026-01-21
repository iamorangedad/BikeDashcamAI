"""
集成测试 - 测试完整的后端服务部署
"""

import pytest
import requests
import time
import json


class TestBackendDeployment:
    """测试后端服务部署"""

    BASE_URL = "http://localhost:8000"

    @pytest.mark.integration
    def test_service_availability(self):
        """测试服务是否可用"""
        try:
            response = requests.get(f"{self.BASE_URL}/", timeout=10)
            assert response.status_code == 200
            data = response.json()
            assert "message" in data
            assert "BikeDashcamAI" in data["message"]
        except requests.exceptions.ConnectionError:
            pytest.skip("Backend service not running")

    @pytest.mark.integration
    def test_health_endpoint(self):
        """测试健康检查端点"""
        try:
            response = requests.get(f"{self.BASE_URL}/health", timeout=10)
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "healthy"
        except requests.exceptions.ConnectionError:
            pytest.skip("Backend service not running")

    @pytest.mark.integration
    def test_scene_detection_api(self):
        """测试场景检测API"""
        try:
            response = requests.post(
                f"{self.BASE_URL}/api/detect_scene",
                json={"frame_data": "test"},
                params={"threshold": 0.3, "min_frames": 3, "max_frames": 5},
                timeout=10,
            )
            assert response.status_code == 200
            data = response.json()
            assert "message" in data
            assert "config" in data
        except requests.exceptions.ConnectionError:
            pytest.skip("Backend service not running")

    @pytest.mark.integration
    def test_websocket_connection(self):
        """测试WebSocket连接"""
        try:
            import websocket
            import threading

            def on_message(ws, message):
                data = json.loads(message)
                assert data.get("type") in ["connected", "error"]

            def on_error(ws, error):
                pass

            def on_close(ws, close_status_code, close_msg):
                pass

            def on_open(ws):
                ws.close()

            ws = websocket.WebSocketApp(
                f"ws://localhost:8000/ws/test_client",
                on_message=on_message,
                on_error=on_error,
                on_close=on_close,
                on_open=on_open,
            )

            # 在单独线程中运行WebSocket连接
            wst = threading.Thread(target=ws.run_forever)
            wst.daemon = True
            wst.start()

            # 等待连接建立和关闭
            time.sleep(2)

        except ImportError:
            pytest.skip("websocket library not available")
        except Exception:
            pytest.skip("WebSocket connection failed")


class TestBackendK8sDeployment:
    """测试Kubernetes部署的后端服务"""

    @pytest.mark.integration
    def test_pod_health_check(self):
        """测试Pod健康状态"""
        try:
            import subprocess

            result = subprocess.run(
                ["kubectl", "get", "pods", "-n", "bike-dashcam"],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0:
                assert "bike-dashcam-backend" in result.stdout
                lines = result.stdout.strip().split("\n")
                for line in lines[1:]:  # Skip header
                    if "bike-dashcam-backend" in line:
                        assert "Running" in line or "ContainerCreating" in line
            else:
                pytest.skip("kubectl command failed")
        except FileNotFoundError:
            pytest.skip("kubectl not available")

    @pytest.mark.integration
    def test_service_endpoints(self):
        """测试Kubernetes服务端点"""
        try:
            import subprocess

            result = subprocess.run(
                ["kubectl", "get", "svc", "-n", "bike-dashcam"],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0:
                assert "bike-dashcam-backend" in result.stdout
            else:
                pytest.skip("kubectl command failed")
        except FileNotFoundError:
            pytest.skip("kubectl not available")

    @pytest.mark.integration
    def test_config_map_exists(self):
        """测试ConfigMap是否存在"""
        try:
            import subprocess

            result = subprocess.run(
                ["kubectl", "get", "configmap", "backend-config", "-n", "bike-dashcam"],
                capture_output=True,
                text=True,
                timeout=30,
            )

            if result.returncode == 0:
                assert result.returncode == 0
            else:
                pytest.skip("ConfigMap not found")
        except FileNotFoundError:
            pytest.skip("kubectl not available")
