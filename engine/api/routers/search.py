from fastapi import APIRouter, HTTPException
from schemas import SearchRequest, SearchResponse, SearchResult
from transformers import CLIPProcessor, CLIPModel
import torch
from pymilvus import connections, Collection
import time
import os

router = APIRouter()

# 初始化模型
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
text_encoder = CLIPModel.from_pretrained("openai/clip-vit-base-patch32").to(device)
text_processor = CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")

# Milvus 连接
MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-standalone")
MILVUS_PORT = os.getenv("MILVUS_PORT", "19530")

connections.connect(host=MILVUS_HOST, port=MILVUS_PORT)
collection = Collection("video_fragments")
collection.load()


def encode_text(query: str) -> torch.Tensor:
    """将文本查询编码为向量"""
    inputs = text_processor(text=[query], return_tensors="pt", padding=True).to(device)
    with torch.no_grad():
        text_features = text_encoder.get_text_features(**inputs)
    text_features = text_features / text_features.norm(dim=-1, keepdim=True)
    return text_features.cpu().numpy()


def search_similar_fragments(text_vector, top_k: int, threshold: float):
    """在 Milvus 中搜索相似的视频片段"""
    search_params = {"metric_type": "IP", "params": {"nprobe": 10}}
    results = collection.search(
        data=[text_vector.tolist()[0]],
        anns_field="feature_vector",
        param=search_params,
        limit=top_k,
        output_fields=["video_id", "start_time", "end_time"],
    )

    search_results = []
    for hit in results[0]:
        if hit.score >= threshold:
            search_results.append(
                SearchResult(
                    video_id=hit.entity.get("video_id"),
                    start_time=format_timestamp(hit.entity.get("start_time")),
                    end_time=format_timestamp(hit.entity.get("end_time")),
                    score=float(hit.score),
                    thumbnail=f"/thumbnails/{hit.entity.get('video_id')}_{hit.entity.get('start_time')}.jpg",
                )
            )

    return search_results


def format_timestamp(seconds: float) -> str:
    """将秒数转换为 MM:SS 格式"""
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes:02d}:{secs:02d}"


@router.post("/search", response_model=SearchResponse)
async def search_videos(request: SearchRequest):
    """
    使用自然语言搜索视频片段

    - **query**: 自然语言查询文本，例如 "一只狗在草地上接飞盘"
    - **top_k**: 返回结果数量，默认 10
    - **threshold**: 相似度阈值，默认 0.5
    """
    start_time = time.time()

    try:
        # 编码查询文本
        text_vector = encode_text(request.query)

        # 搜索相似片段
        results = search_similar_fragments(
            text_vector, request.top_k, request.threshold
        )

        # 计算延迟
        latency_ms = (time.time() - start_time) * 1000

        return SearchResponse(
            results=results,
            query=request.query,
            latency_ms=latency_ms,
            total_results=len(results),
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"搜索失败: {str(e)}")
