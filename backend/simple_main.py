from fastapi import FastAPI
import os

app = FastAPI(title="BikeDashcamAI", version="1.0.0")


@app.get("/")
async def root():
    return {
        "message": "BikeDashcamAI Video Processing Service",
        "version": "1.0.0",
        "node": os.getenv("NODE_NAME", "unknown"),
        "rtsp_url": os.getenv("RTSP_STREAM_URL", "not_set"),
    }


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
