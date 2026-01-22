import pytest
import asyncio
import numpy as np
import base64
import sys
import os

sys.path.append(os.path.join(os.path.dirname(__file__), "..", "backend"))

try:
    from app.services.scene_detector import SceneDetector
    from app.services.video_processor import VideoProcessor

    SERVICES_AVAILABLE = True
except ImportError:
    SERVICES_AVAILABLE = False


class TestSceneDetector:
    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def setup_method(self):
        self.detector = SceneDetector(threshold=0.3, min_frames=3, max_frames=5)

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_detector_initialization(self):
        assert self.detector.threshold == 0.3
        assert self.detector.min_frames == 3
        assert self.detector.max_frames == 5

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_frame_to_base64_conversion(self):
        test_frame = np.zeros((100, 100, 3), dtype=np.uint8)
        base64_str = self.detector.frame_to_base64(test_frame)

        assert isinstance(base64_str, str)
        assert len(base64_str) > 0

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_base64_to_frame_conversion(self):
        test_frame = np.zeros((100, 100, 3), dtype=np.uint8)
        base64_str = self.detector.frame_to_base64(test_frame)
        decoded_frame = self.detector.base64_to_frame(base64_str)

        assert decoded_frame is not None
        assert decoded_frame.shape == test_frame.shape

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_scene_detection(self):
        frame1 = np.zeros((100, 100, 3), dtype=np.uint8)
        frame2 = np.ones((100, 100, 3), dtype=np.uint8) * 255

        is_scene_change = self.detector.detect_scene_change(frame1, frame2)
        assert isinstance(is_scene_change, bool)


class TestVideoProcessor:
    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def setup_method(self):
        self.processor = VideoProcessor(
            fps=30,
            output_width=1280,
            output_height=720,
            scene_threshold=0.3,
            min_frames_per_scene=3,
            max_frames_per_scene=5,
        )

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_processor_initialization(self):
        assert self.processor.fps == 30
        assert self.processor.output_width == 1280
        assert self.processor.output_height == 720
        assert self.processor.scene_threshold == 0.3

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_frame_processing(self):
        test_frame = np.zeros((720, 1280, 3), dtype=np.uint8)
        processed_frame = self.processor.process_frame(test_frame)

        assert processed_frame is not None
        assert processed_frame.shape == (720, 1280, 3)

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_statistics(self):
        stats = self.processor.get_statistics()
        assert isinstance(stats, dict)
        assert "frames_processed" in stats
        assert "scene_changes" in stats

    @pytest.mark.skipif(not SERVICES_AVAILABLE, reason="Services not available")
    def test_finalize(self):
        self.processor.finalize()
        assert True
