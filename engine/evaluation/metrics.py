"""
评估指标计算模块

实现 R@K (Recall at K) 和 mAP (mean Average Precision) 等指标
"""

import numpy as np
from typing import List, Dict, Set, Tuple
from collections import defaultdict


def compute_recall_at_k(
    retrieved_results: List[List[str]],
    ground_truth: List[Set[str]],
    k_values: List[int] = [1, 5, 10],
) -> Dict[int, float]:
    """
    计算 Recall@K

    Args:
        retrieved_results: 查询结果列表，每个元素是 Top-K 结果的视频ID列表
        ground_truth: 真实标签集合列表，每个元素是该查询的正确视频ID集合
        k_values: 要计算的 K 值列表

    Returns:
        各个 K 值的 Recall@K
    """
    recall_scores = {k: [] for k in k_values}

    for results, gt in zip(retrieved_results, ground_truth):
        for k in k_values:
            top_k = results[:k]
            num_relevant = len(set(top_k) & gt)
            recall = num_relevant / len(gt) if len(gt) > 0 else 0.0
            recall_scores[k].append(recall)

    # 计算平均 Recall
    avg_recall = {k: np.mean(scores) for k, scores in recall_scores.items()}

    return avg_recall


def compute_precision_at_k(
    retrieved_results: List[List[str]],
    ground_truth: List[Set[str]],
    k_values: List[int] = [1, 5, 10],
) -> Dict[int, float]:
    """
    计算 Precision@K

    Args:
        retrieved_results: 查询结果列表
        ground_truth: 真实标签集合列表
        k_values: 要计算的 K 值列表

    Returns:
        各个 K 值的 Precision@K
    """
    precision_scores = {k: [] for k in k_values}

    for results, gt in zip(retrieved_results, ground_truth):
        for k in k_values:
            top_k = results[:k]
            num_relevant = len(set(top_k) & gt)
            precision = num_relevant / k if k > 0 else 0.0
            precision_scores[k].append(precision)

    # 计算平均 Precision
    avg_precision = {k: np.mean(scores) for k, scores in precision_scores.items()}

    return avg_precision


def compute_average_precision(
    retrieved_results: List[str], ground_truth: Set[str]
) -> float:
    """
    计算 Average Precision (AP)

    Args:
        retrieved_results: 单个查询的排序结果
        ground_truth: 该查询的真实标签集合

    Returns:
        Average Precision 值
    """
    if not ground_truth:
        return 0.0

    precisions = []
    num_relevant = 0

    for i, item in enumerate(retrieved_results):
        if item in ground_truth:
            num_relevant += 1
            precision = num_relevant / (i + 1)
            precisions.append(precision)

    if not precisions:
        return 0.0

    ap = np.mean(precisions)
    return ap


def compute_mean_average_precision(
    retrieved_results: List[List[str]], ground_truth: List[Set[str]]
) -> float:
    """
    计算 mean Average Precision (mAP)

    Args:
        retrieved_results: 查询结果列表
        ground_truth: 真实标签集合列表

    Returns:
        mAP 值
    """
    aps = []

    for results, gt in zip(retrieved_results, ground_truth):
        ap = compute_average_precision(results, gt)
        aps.append(ap)

    mAP = np.mean(aps)
    return mAP


def compute_ndcg_at_k(
    retrieved_results: List[List[str]],
    ground_truth: List[Set[str]],
    k_values: List[int] = [5, 10],
) -> Dict[int, float]:
    """
    计算 NDCG@K (Normalized Discounted Cumulative Gain)

    Args:
        retrieved_results: 查询结果列表
        ground_truth: 真实标签集合列表
        k_values: 要计算的 K 值列表

    Returns:
        各个 K 值的 NDCG@K
    """
    ndcg_scores = {k: [] for k in k_values}

    for results, gt in zip(retrieved_results, ground_truth):
        for k in k_values:
            top_k = results[:k]

            # 计算 DCG
            dcg = 0.0
            for i, item in enumerate(top_k):
                relevance = 1 if item in gt else 0
                dcg += relevance / np.log2(i + 2)

            # 计算 Ideal DCG
            idcg = 0.0
            num_relevant = min(len(gt), k)
            for i in range(num_relevant):
                idcg += 1 / np.log2(i + 2)

            # 计算 NDCG
            ndcg = dcg / idcg if idcg > 0 else 0.0
            ndcg_scores[k].append(ndcg)

    # 计算平均 NDCG
    avg_ndcg = {k: np.mean(scores) for k, scores in ndcg_scores.items()}

    return avg_ndcg


def compute_latency_stats(latencies: List[float]) -> Dict[str, float]:
    """
    计算延迟统计信息

    Args:
        latencies: 延迟列表（毫秒）

    Returns:
        统计信息字典
    """
    if not latencies:
        return {}

    return {
        "mean": np.mean(latencies),
        "median": np.median(latencies),
        "std": np.std(latencies),
        "min": np.min(latencies),
        "max": np.max(latencies),
        "p95": np.percentile(latencies, 95),
        "p99": np.percentile(latencies, 99),
    }


def evaluate_search_system(
    queries: List[str],
    retrieved_results: List[List[str]],
    ground_truth: List[Set[str]],
    latencies: List[float],
) -> Dict[str, any]:
    """
    综合评估搜索系统性能

    Args:
        queries: 查询列表
        retrieved_results: 检索结果列表
        ground_truth: 真实标签列表
        latencies: 延迟列表

    Returns:
        评估结果字典
    """
    evaluation_results = {}

    # Recall@K
    recall_scores = compute_recall_at_k(retrieved_results, ground_truth)
    evaluation_results["recall"] = recall_scores

    # Precision@K
    precision_scores = compute_precision_at_k(retrieved_results, ground_truth)
    evaluation_results["precision"] = precision_scores

    # mAP
    mAP = compute_mean_average_precision(retrieved_results, ground_truth)
    evaluation_results["mAP"] = mAP

    # NDCG@K
    ndcg_scores = compute_ndcg_at_k(retrieved_results, ground_truth)
    evaluation_results["ndcg"] = ndcg_scores

    # 延迟统计
    latency_stats = compute_latency_stats(latencies)
    evaluation_results["latency"] = latency_stats

    # 查询数量
    evaluation_results["num_queries"] = len(queries)

    return evaluation_results


def print_evaluation_report(evaluation_results: Dict[str, any]):
    """
    打印评估报告

    Args:
        evaluation_results: 评估结果字典
    """
    print("=" * 60)
    print("📊 视频搜索引擎评估报告")
    print("=" * 60)

    # Recall@K
    print("\n📈 Recall@K:")
    for k, score in evaluation_results["recall"].items():
        print(f"   R@{k}: {score:.4f}")

    # Precision@K
    print("\n📈 Precision@K:")
    for k, score in evaluation_results["precision"].items():
        print(f"   P@{k}: {score:.4f}")

    # mAP
    print(f"\n📈 Mean Average Precision (mAP): {evaluation_results['mAP']:.4f}")

    # NDCG@K
    print("\n📈 NDCG@K:")
    for k, score in evaluation_results["ndcg"].items():
        print(f"   NDCG@{k}: {score:.4f}")

    # 延迟
    if evaluation_results.get("latency"):
        print("\n⏱️  延迟统计 (毫秒):")
        latency = evaluation_results["latency"]
        print(f"   平均: {latency['mean']:.2f}")
        print(f"   中位数: {latency['median']:.2f}")
        print(f"   标准差: {latency['std']:.2f}")
        print(f"   最小: {latency['min']:.2f}")
        print(f"   最大: {latency['max']:.2f}")
        print(f"   P95: {latency['p95']:.2f}")
        print(f"   P99: {latency['p99']:.2f}")

    print(f"\n📝 查询数量: {evaluation_results.get('num_queries', 0)}")
    print("=" * 60)


if __name__ == "__main__":
    # 测试示例
    test_retrieved = [
        ["video1", "video2", "video3", "video4", "video5"],
        ["video2", "video1", "video3", "video4", "video5"],
        ["video1", "video3", "video2", "video4", "video5"],
    ]

    test_ground_truth = [
        {"video1", "video2"},
        {"video1", "video3"},
        {"video2", "video3"},
    ]

    test_latencies = [120.5, 115.3, 130.2]

    results = evaluate_search_system(
        ["query1", "query2", "query3"],
        test_retrieved,
        test_ground_truth,
        test_latencies,
    )

    print_evaluation_report(results)
