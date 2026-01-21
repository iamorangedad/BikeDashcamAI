from typing import List, Dict, Any
from pymilvus import Collection
import numpy as np
from .connection import get_collection


def insert_fragments(
    video_id: str,
    start_times: List[float],
    end_times: List[float],
    feature_vectors: List[np.ndarray],
    metadata_list: List[Dict[str, Any]] = None,
) -> int:
    """
    插入视频片段到集合

    Args:
        video_id: 视频ID
        start_times: 起始时间列表
        end_times: 结束时间列表
        feature_vectors: 特征向量列表
        metadata_list: 元数据列表

    Returns:
        插入的数量
    """
    collection = get_collection()

    if len(start_times) != len(end_times) or len(start_times) != len(feature_vectors):
        raise ValueError("输入列表长度不一致")

    if metadata_list is None:
        metadata_list = [{} for _ in range(len(start_times))]

    # 准备数据
    video_ids = [video_id] * len(start_times)
    metadatas = [str(metadata) for metadata in metadata_list]

    data = [video_ids, start_times, end_times, feature_vectors, metadatas]

    # 插入数据
    collection.insert(data)
    collection.flush()

    print(f"✅ 插入 {len(start_times)} 个片段")
    return len(start_times)


def get_fragment_by_id(fragment_id: int) -> Dict[str, Any]:
    """根据 ID 获取片段"""
    collection = get_collection()

    results = collection.query(
        expr=f"id == {fragment_id}",
        output_fields=["video_id", "start_time", "end_time", "metadata"],
    )

    if not results:
        return None

    return {
        "id": fragment_id,
        "video_id": results[0]["video_id"],
        "start_time": results[0]["start_time"],
        "end_time": results[0]["end_time"],
        "metadata": eval(results[0]["metadata"]),
    }


def get_fragments_by_video(video_id: str, limit: int = 100) -> List[Dict[str, Any]]:
    """根据视频ID获取片段列表"""
    collection = get_collection()

    results = collection.query(
        expr=f'video_id == "{video_id}"',
        output_fields=["id", "start_time", "end_time", "metadata"],
        limit=limit,
    )

    return [
        {
            "id": r["id"],
            "start_time": r["start_time"],
            "end_time": r["end_time"],
            "metadata": eval(r["metadata"]),
        }
        for r in results
    ]


def delete_video_fragments(video_id: str) -> int:
    """删除指定视频的所有片段"""
    collection = get_collection()

    # 先查询该视频的片段数量
    count = collection.num_entities

    # 删除片段
    collection.delete(expr=f'video_id == "{video_id}"')
    collection.flush()

    new_count = collection.num_entities
    deleted = count - new_count

    print(f"✅ 删除视频 {video_id} 的 {deleted} 个片段")
    return deleted


def get_collection_stats() -> Dict[str, Any]:
    """获取集合统计信息"""
    collection = get_collection()

    return {
        "num_entities": collection.num_entities,
        "index": collection.indexes,
        "name": collection.name,
    }
