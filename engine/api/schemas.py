from typing import List, Optional
from pydantic import BaseModel, Field


class SearchResult(BaseModel):
    video_id: str = Field(..., description="视频标识符")
    start_time: str = Field(..., description="起始时间戳，格式为 MM:SS")
    end_time: str = Field(..., description="结束时间戳，格式为 MM:SS")
    score: float = Field(..., ge=0.0, le=1.0, description="相似度分数")
    thumbnail: Optional[str] = Field(None, description="缩略图路径")


class SearchRequest(BaseModel):
    query: str = Field(..., min_length=1, description="自然语言查询文本")
    top_k: int = Field(10, ge=1, le=100, description="返回结果数量")
    threshold: float = Field(0.5, ge=0.0, le=1.0, description="相似度阈值")


class SearchResponse(BaseModel):
    results: List[SearchResult]
    query: str
    latency_ms: float
    total_results: int


class IndexRequest(BaseModel):
    video_path: str = Field(..., description="视频文件路径")
    video_id: str = Field(..., description="视频标识符")
    metadata: Optional[dict] = Field(None, description="额外元数据")


class IndexResponse(BaseModel):
    status: str
    video_id: str
    message: str
    fragments_indexed: int


class HealthResponse(BaseModel):
    status: str
    services: dict
