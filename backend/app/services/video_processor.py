import cv2
import numpy as np
import asyncio
from typing import List, Optional
from .scene_detector import SceneDetector
import base64


class VideoProcessor:
    def __init__(
        self,
        fps: int = 30,
        output_width: int = 1280,
        output_height: int = 720,
        scene_threshold: float = 0.3,
        min_frames_per_scene: int = 3,
        max_frames_per_scene: int = 5,
    ):
        self.fps = fps
        self.output_width = output_width
        self.output_height = output_height
        self.detector = SceneDetector(
            threshold=scene_threshold,
            min_frames=min_frames_per_scene,
            max_frames=max_frames_per_scene,
        )
        self.current_scene_frames: List[np.ndarray] = []
        self.frame_count_in_scene = 0
        self.total_frames = 0
        self.writer: Optional[cv2.VideoWriter] = None
        self.output_path: Optional[str] = None

    def initialize_writer(self, output_path: str):
        self.output_path = output_path
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        self.writer = cv2.VideoWriter(
            output_path, fourcc, self.fps, (self.output_width, self.output_height)
        )

    def process_frame(self, frame: np.ndarray) -> Optional[np.ndarray]:
        frame = cv2.resize(frame, (self.output_width, self.output_height))

        if self.detector.should_keep_frame(frame, self.frame_count_in_scene):
            self.current_scene_frames.append(frame.copy())
            self.frame_count_in_scene += 1

        if self.detector._detect_scene_change(frame):
            self.total_frames += len(self.current_scene_frames)
            processed_frame = (
                self.current_scene_frames[0] if self.current_scene_frames else frame
            )
            self.current_scene_frames = []
            self.frame_count_in_scene = 0
            return processed_frame

        return None

    def finalize(self):
        if self.writer:
            self.writer.release()
        self.detector.reset()
        self.current_scene_frames = []
        self.frame_count_in_scene = 0

    def get_statistics(self) -> dict:
        return {
            "total_frames": self.total_frames,
            "fps": self.fps,
            "output_width": self.output_width,
            "output_height": self.output_height,
        }
