"""
视频搜索引擎评估主脚本
"""

import json
import time
import requests
from pathlib import Path
from typing import List, Set
from metrics import evaluate_search_system, print_evaluation_report


class VideoSearchEvaluator:
    """视频搜索引擎评估器"""

    def __init__(self, api_url: str = "http://localhost:8000"):
        """
        初始化评估器

        Args:
            api_url: API 服务 URL
        """
        self.api_url = api_url
        self.search_endpoint = f"{api_url}/api/v1/search"

    def load_test_queries(self, query_file: str = "test_queries.json"):
        """
        加载测试查询

        Args:
            query_file: 查询文件路径

        Returns:
            查询列表
        """
        with open(query_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        return data["queries"]

    def perform_search(self, query: str, top_k: int = 10) -> dict:
        """
        执行搜索

        Args:
            query: 查询文本
            top_k: 返回结果数量

        Returns:
            搜索结果
        """
        payload = {"query": query, "top_k": top_k, "threshold": 0.5}

        try:
            response = requests.post(self.search_endpoint, json=payload)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"❌ 搜索失败: {e}")
            return {"results": [], "latency_ms": 0}

    def run_evaluation(self, query_file: str = "test_queries.json"):
        """
        运行评估

        Args:
            query_file: 查询文件路径

        Returns:
            评估结果
        """
        print("🚀 开始评估视频搜索引擎...")

        # 加载测试查询
        queries = self.load_test_queries(query_file)
        print(f"✅ 加载了 {len(queries)} 个测试查询")

        # 准备数据
        all_queries = []
        all_retrieved = []
        all_ground_truth = []
        all_latencies = []

        # 执行搜索
        print("\n🔍 执行搜索...")
        for idx, query_data in enumerate(queries, 1):
            query = query_data["query"]
            relevant_videos = set(query_data["relevant_videos"])

            print(f"   [{idx}/{len(queries)}] 查询: {query}")

            # 执行搜索
            result = self.perform_search(query, top_k=10)

            # 提取结果
            retrieved_videos = [r["video_id"] for r in result["results"]]
            latency = result.get("latency_ms", 0)

            # 保存数据
            all_queries.append(query)
            all_retrieved.append(retrieved_videos)
            all_ground_truth.append(relevant_videos)
            all_latencies.append(latency)

            print(f"      延迟: {latency:.2f}ms, 检索到 {len(retrieved_videos)} 个结果")

        # 计算评估指标
        print("\n📊 计算评估指标...")
        evaluation_results = evaluate_search_system(
            all_queries, all_retrieved, all_ground_truth, all_latencies
        )

        return evaluation_results

    def save_results(self, results: dict, output_file: str = "evaluation_results.json"):
        """
        保存评估结果

        Args:
            results: 评估结果
            output_file: 输出文件路径
        """

        # 转换 numpy 类型为 Python 类型
        def convert_types(obj):
            if hasattr(obj, "tolist"):
                return obj.tolist()
            elif isinstance(obj, (np.integer, np.floating)):
                return obj.item()
            elif isinstance(obj, dict):
                return {k: convert_types(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_types(item) for item in obj]
            return obj

        results = convert_types(results)

        with open(output_file, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=2, ensure_ascii=False)

        print(f"\n✅ 评估结果已保存到 {output_file}")


def main():
    """主函数"""
    import numpy as np

    # 创建评估器
    evaluator = VideoSearchEvaluator(api_url="http://localhost:8000")

    # 运行评估
    results = evaluator.run_evaluation(query_file="evaluation/test_queries.json")

    # 打印报告
    print_evaluation_report(results)

    # 保存结果
    evaluator.save_results(results, "evaluation/evaluation_results.json")

    print("\n✅ 评估完成！")


if __name__ == "__main__":
    main()
