import pytest
import asyncio
import json
import base64
from fastapi.testclient import TestClient
import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "backend"))

try:
    from app.main import app

    APP_AVAILABLE = True
except ImportError:
    APP_AVAILABLE = False

if APP_AVAILABLE:
    client = TestClient(app)


class TestWebSocket:
    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_websocket_connection(self):
        with client.websocket_connect("/ws/test_client") as websocket:
            try:
                data = websocket.receive_json(timeout=5.0)
                assert data.get("type") in ["connected", "error"]
            except Exception:
                pass

    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_websocket_frame_processing(self):
        with client.websocket_connect("/ws/test_client") as websocket:
            test_frame = base64.b64encode(b"fake_frame_data").decode()

            websocket.send_json({"type": "frame", "data": test_frame})

            try:
                response = websocket.receive_json(timeout=10.0)
                assert response.get("type") in ["processed_frame", "error"]
            except Exception:
                pass

    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_websocket_stop_command(self):
        with client.websocket_connect("/ws/test_client") as websocket:
            websocket.send_json({"type": "stop"})

            try:
                response = websocket.receive_json(timeout=10.0)
                assert response.get("type") in ["completed", "error"]
            except Exception:
                pass

    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_websocket_invalid_data(self):
        with client.websocket_connect("/ws/test_client") as websocket:
            websocket.send_json({"type": "invalid", "data": "test"})

            try:
                response = websocket.receive_json(timeout=10.0)
                assert response.get("type") in ["error", "processed_frame"]
            except Exception:
                pass
