from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from routers import search, index
from schemas import HealthResponse
import os


@asynccontextmanager
async def lifespan(app: FastAPI):
    startup_message()
    yield
    shutdown_message()


def startup_message():
    print("=" * 50)
    print("🚀 视频搜索引擎 API 启动中...")
    print(f"📁 Milvus Host: {os.getenv('MILVUS_HOST', 'milvus-standalone')}")
    print(f"🔌 Milvus Port: {os.getenv('MILVUS_PORT', '19530')}")
    print(f"🧠 Triton URL: {os.getenv('TRITON_URL', 'triton:8001')}")
    print(f"💾 Redis URL: {os.getenv('REDIS_URL', 'redis://redis:6379')}")
    print("=" * 50)


def shutdown_message():
    print("🛑 视频搜索引擎 API 已关闭")


app = FastAPI(
    title="智能视频搜索引擎 API",
    description="基于语义的端到端视频搜索服务",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(search.router, prefix="/api/v1", tags=["搜索"])
app.include_router(index.router, prefix="/api/v1", tags=["索引"])


@app.get("/health", response_model=HealthResponse)
async def health_check():
    return HealthResponse(
        status="healthy",
        services={
            "api": "running",
            "milvus": "connected",
            "triton": "connected",
            "redis": "connected",
        },
    )


@app.get("/")
async def root():
    return {
        "message": "欢迎使用智能视频搜索引擎",
        "version": "1.0.0",
        "docs": "/docs",
        "health": "/health",
    }
