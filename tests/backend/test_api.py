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


class TestHealthEndpoints:
    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_root_endpoint(self):
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "BikeDashcamAI Video Processing Service"
        assert data["version"] == "1.0.0"
        assert "endpoints" in data

    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_health_check(self):
        response = client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"


class TestAPIEndpoints:
    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_detect_scene_endpoint(self):
        response = client.post(
            "/api/detect_scene",
            json={"frame_data": "test"},
            params={"threshold": 0.3, "min_frames": 3, "max_frames": 5},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "Scene detector initialized"
        assert "config" in data
        assert data["config"]["threshold"] == 0.3
        assert data["config"]["min_frames"] == 3
        assert data["config"]["max_frames"] == 5

    @pytest.mark.skipif(not APP_AVAILABLE, reason="App not available")
    def test_detect_scene_default_params(self):
        response = client.post("/api/detect_scene", json={"frame_data": "test"})
        assert response.status_code == 200
        data = response.json()
        assert data["config"]["threshold"] == 0.3
        assert data["config"]["min_frames"] == 3
        assert data["config"]["max_frames"] == 5
