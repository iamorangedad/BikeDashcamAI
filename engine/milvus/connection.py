from pymilvus import (
    connections,
    utility,
    Collection,
    CollectionSchema,
    FieldSchema,
    DataType,
)
import os

MILVUS_HOST = os.getenv("MILVUS_HOST", "milvus-standalone")
MILVUS_PORT = os.getenv("MILVUS_PORT", "19530")

VECTOR_DIM = 512  # CLIP 特征维度


def connect_to_milvus():
    """连接到 Milvus"""
    connections.connect(host=MILVUS_HOST, port=MILVUS_PORT)
    print(f"✅ 已连接到 Milvus: {MILVUS_HOST}:{MILVUS_PORT}")


def disconnect_from_milvus():
    """断开 Milvus 连接"""
    connections.disconnect("default")
    print("🔌 已断开 Milvus 连接")


def create_video_fragment_collection():
    """创建视频片段集合"""
    collection_name = "video_fragments"

    if utility.has_collection(collection_name):
        print(f"⚠️  集合 {collection_name} 已存在")
        return Collection(collection_name)

    # 定义字段
    fields = [
        FieldSchema(name="id", dtype=DataType.INT64, is_primary=True, auto_id=True),
        FieldSchema(name="video_id", dtype=DataType.VARCHAR, max_length=256),
        FieldSchema(name="start_time", dtype=DataType.FLOAT),
        FieldSchema(name="end_time", dtype=DataType.FLOAT),
        FieldSchema(name="feature_vector", dtype=DataType.FLOAT_VECTOR, dim=VECTOR_DIM),
        FieldSchema(name="metadata", dtype=DataType.VARCHAR, max_length=1024),
    ]

    # 创建 Schema
    schema = CollectionSchema(
        fields=fields, description="视频片段特征向量集合", enable_dynamic_field=True
    )

    # 创建集合
    collection = Collection(name=collection_name, schema=schema)

    # 创建 HNSW 索引
    index_params = {
        "metric_type": "IP",
        "index_type": "HNSW",
        "params": {"M": 16, "efConstruction": 200},
    }
    collection.create_index(field_name="feature_vector", index_params=index_params)

    print(f"✅ 集合 {collection_name} 创建成功")
    return collection


def get_collection(collection_name: str = "video_fragments") -> Collection:
    """获取集合"""
    if not utility.has_collection(collection_name):
        raise ValueError(f"集合 {collection_name} 不存在")
    return Collection(collection_name)


def create_index(collection_name: str = "video_fragments"):
    """为集合创建索引"""
    collection = get_collection(collection_name)

    if collection.has_index():
        print(f"⚠️  集合 {collection_name} 已有索引")
        return

    index_params = {
        "metric_type": "IP",
        "index_type": "HNSW",
        "params": {"M": 16, "efConstruction": 200},
    }
    collection.create_index(field_name="feature_vector", index_params=index_params)
    print(f"✅ 索引创建成功")
