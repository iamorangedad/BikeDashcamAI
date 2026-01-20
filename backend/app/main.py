from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from .api.websocket import websocket_endpoint
from .services.scene_detector import SceneDetector
from .services.video_processor import VideoProcessor


app = FastAPI(title="BikeDashcamAI", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    return {
        "message": "BikeDashcamAI Video Processing Service",
        "version": "1.0.0",
        "endpoints": {"websocket": "/ws/{client_id}", "health": "/health"},
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


@app.websocket("/ws/{client_id}")
async def websocket_video_stream(websocket: WebSocket, client_id: str):
    await websocket_endpoint(websocket, client_id)


@app.post("/api/detect_scene")
async def detect_scene_change(
    frame_data: dict, threshold: float = 0.3, min_frames: int = 3, max_frames: int = 5
):
    detector = SceneDetector(
        threshold=threshold, min_frames=min_frames, max_frames=max_frames
    )
    return {
        "message": "Scene detector initialized",
        "config": {
            "threshold": threshold,
            "min_frames": min_frames,
            "max_frames": max_frames,
        },
    }
