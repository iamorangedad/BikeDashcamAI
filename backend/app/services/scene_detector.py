import base64
import cv2
import numpy as np
from typing import Optional, Tuple


class SceneDetector:
    def __init__(
        self, threshold: float = 0.3, min_frames: int = 3, max_frames: int = 5
    ):
        self.threshold = threshold
        self.min_frames = min_frames
        self.max_frames = max_frames
        self.prev_frame: Optional[np.ndarray] = None
        self.prev_hist: Optional[np.ndarray] = None

    def _calculate_frame_difference(
        self, frame1: np.ndarray, frame2: np.ndarray
    ) -> float:
        gray1 = cv2.cvtColor(frame1, cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(frame2, cv2.COLOR_BGR2GRAY)
        diff = cv2.absdiff(gray1, gray2)
        return np.mean(diff) / 255.0

    def _calculate_histogram_difference(
        self, frame1: np.ndarray, frame2: np.ndarray
    ) -> float:
        hist1 = cv2.calcHist(
            [frame1], [0, 1, 2], None, [8, 8, 8], [0, 256, 0, 256, 0, 256]
        )
        hist2 = cv2.calcHist(
            [frame2], [0, 1, 2], None, [8, 8, 8], [0, 256, 0, 256, 0, 256]
        )
        hist1 = cv2.normalize(hist1, hist1).flatten()
        hist2 = cv2.normalize(hist2, hist2).flatten()
        return cv2.compareHist(hist1, hist2, cv2.HISTCMP_CORREL)

    def _detect_scene_change(self, current_frame: np.ndarray) -> bool:
        if self.prev_frame is None:
            self.prev_frame = current_frame.copy()
            self.prev_hist = cv2.calcHist(
                [current_frame], [0, 1, 2], None, [8, 8, 8], [0, 256, 0, 256, 0, 256]
            )
            return False

        frame_diff = self._calculate_frame_difference(self.prev_frame, current_frame)
        hist_diff = self._calculate_histogram_difference(self.prev_frame, current_frame)

        scene_changed = frame_diff > self.threshold and hist_diff < 0.8

        if scene_changed:
            self.prev_frame = current_frame.copy()
            self.prev_hist = cv2.calcHist(
                [current_frame], [0, 1, 2], None, [8, 8, 8], [0, 256, 0, 256, 0, 256]
            )

        return scene_changed

    def should_keep_frame(
        self, current_frame: np.ndarray, frame_count_in_scene: int
    ) -> bool:
        scene_changed = self._detect_scene_change(current_frame)

        if scene_changed:
            return frame_count_in_scene < self.max_frames

        return frame_count_in_scene < self.min_frames

    def reset(self):
        self.prev_frame = None
        self.prev_hist = None

    def base64_to_frame(self, base64_str: str) -> np.ndarray:
        img_data = base64.b64decode(base64_str)
        nparr = np.frombuffer(img_data, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        return frame

    def frame_to_base64(self, frame: np.ndarray, quality: int = 85) -> str:
        _, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
        return base64.b64encode(buffer).decode("utf-8")
