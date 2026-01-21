from typing import List, Dict, Any, Optional
import numpy as np
from pymilvus import Collection
from .connection import get_collection


def search_similar_vectors(
    query_vector: np.ndarray,
    top_k: int = 10,
    threshold: float = 0.5,
    collection_name: str = "video_fragments",
) -> List[Dict[str, Any]]:
    """
    搜索相似向量

    Args:
        query_vector: 查询向量
        top_k: 返回结果数量
        threshold: 相似度阈值
        collection_name: 集合名称

    Returns:
        搜索结果列表
    """
    collection = get_collection(collection_name)

    # 确保向量已加载
    collection.load()

    # 搜索参数
    search_params = {"metric_type": "IP", "params": {"nprobe": 10}}

    # 执行搜索
    results = collection.search(
        data=[query_vector.tolist()],
        anns_field="feature_vector",
        param=search_params,
        limit=top_k,
        output_fields=["video_id", "start_time", "end_time", "metadata"],
    )

    # 处理结果
    search_results = []
    for hit in results[0]:
        if hit.score >= threshold:
            search_results.append(
                {
                    "id": hit.id,
                    "video_id": hit.entity.get("video_id"),
                    "start_time": hit.entity.get("start_time"),
                    "end_time": hit.entity.get("end_time"),
                    "score": float(hit.score),
                    "metadata": hit.entity.get("metadata"),
                    "distance": float(hit.distance),
                }
            )

    return search_results


def batch_search(
    query_vectors: List[np.ndarray], top_k: int = 10, threshold: float = 0.5
) -> List[List[Dict[str, Any]]]:
    """
    批量搜索

    Args:
        query_vectors: 查询向量列表
        top_k: 返回结果数量
        threshold: 相似度阈值

    Returns:
        每个查询向量的结果列表
    """
    collection = get_collection()
    collection.load()

    search_params = {"metric_type": "IP", "params": {"nprobe": 10}}

    results = collection.search(
        data=[v.tolist() for v in query_vectors],
        anns_field="feature_vector",
        param=search_params,
        limit=top_k,
        output_fields=["video_id", "start_time", "end_time", "metadata"],
    )

    batch_results = []
    for query_result in results:
        query_results = []
        for hit in query_result:
            if hit.score >= threshold:
                query_results.append(
                    {
                        "id": hit.id,
                        "video_id": hit.entity.get("video_id"),
                        "start_time": hit.entity.get("start_time"),
                        "end_time": hit.entity.get("end_time"),
                        "score": float(hit.score),
                        "metadata": hit.entity.get("metadata"),
                        "distance": float(hit.distance),
                    }
                )
        batch_results.append(query_results)

    return batch_results


def search_by_video_id(
    video_id: str, top_k: int = 5, threshold: float = 0.7
) -> List[Dict[str, Any]]:
    """
    根据视频ID搜索相似视频

    Args:
        video_id: 视频ID
        top_k: 返回结果数量
        threshold: 相似度阈值

    Returns:
        相似视频片段列表
    """
    collection = get_collection()

    # 先获取该视频的所有片段
    fragments = collection.query(
        expr=f'video_id == "{video_id}"',
        output_fields=["id", "feature_vector"],
        limit=10,
    )

    if not fragments:
        return []

    # 使用第一个片段的特征向量作为查询
    query_vector = np.array(fragments[0]["feature_vector"])

    return search_similar_vectors(query_vector, top_k, threshold)
