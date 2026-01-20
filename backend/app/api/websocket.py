from fastapi import WebSocket, WebSocketDisconnect
from typing import Dict
import json
import asyncio
import cv2
import base64
import numpy as np
from datetime import datetime
import os
from ..services.video_processor import VideoProcessor
from ..services.scene_detector import SceneDetector


class WebSocketManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}

    async def connect(self, websocket: WebSocket, client_id: str):
        await websocket.accept()
        self.active_connections[client_id] = websocket

    def disconnect(self, client_id: str):
        if client_id in self.active_connections:
            del self.active_connections[client_id]

    async def send_message(self, client_id: str, message: dict):
        if client_id in self.active_connections:
            await self.active_connections[client_id].send_json(message)

    async def broadcast(self, message: dict):
        for connection in self.active_connections.values():
            await connection.send_json(message)


manager = WebSocketManager()


async def websocket_endpoint(websocket: WebSocket, client_id: str):
    await manager.connect(websocket, client_id)

    processor = VideoProcessor(
        fps=30,
        output_width=1280,
        output_height=720,
        scene_threshold=0.3,
        min_frames_per_scene=3,
        max_frames_per_scene=5,
    )

    output_dir = "outputs"
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(
        output_dir, f"output_{client_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.mp4"
    )

    processor.initialize_writer(output_path)

    try:
        while True:
            data = await websocket.receive_json()

            if data.get("type") == "frame":
                frame_data = data.get("data")
                if frame_data:
                    frame = processor.detector.base64_to_frame(frame_data)
                    processed_frame = processor.process_frame(frame)

                    if processed_frame is not None:
                        processed_base64 = processor.detector.frame_to_base64(
                            processed_frame, quality=80
                        )
                        await manager.send_message(
                            client_id,
                            {
                                "type": "processed_frame",
                                "data": processed_base64,
                                "timestamp": datetime.now().isoformat(),
                            },
                        )

            elif data.get("type") == "stop":
                await manager.send_message(
                    client_id,
                    {
                        "type": "completed",
                        "output_path": output_path,
                        "statistics": processor.get_statistics(),
                    },
                )
                break

    except WebSocketDisconnect:
        print(f"Client {client_id} disconnected")
    except Exception as e:
        print(f"Error processing video for client {client_id}: {str(e)}")
        await manager.send_message(client_id, {"type": "error", "message": str(e)})
    finally:
        processor.finalize()
        manager.disconnect(client_id)
