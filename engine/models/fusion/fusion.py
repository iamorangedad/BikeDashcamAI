"""
特征融合模块 - 加权融合 SigLIP 和 TimeSformer 特征
"""

import torch
import torch.nn as nn
import numpy as np


class FeatureFusion(nn.Module):
    """
    特征融合模块

    将 SigLIP 图像特征和 TimeSformer 时序特征进行加权融合
    """

    def __init__(
        self,
        siglip_dim: int = 768,
        timesformer_dim: int = 768,
        output_dim: int = 512,
        fusion_method: str = "weighted_sum",
    ):
        """
        初始化特征融合模块

        Args:
            siglip_dim: SigLIP 特征维度
            timesformer_dim: TimeSformer 特征维度
            output_dim: 输出特征维度
            fusion_method: 融合方法 ('weighted_sum', 'concat', 'attention')
        """
        super(FeatureFusion, self).__init__()

        self.siglip_dim = siglip_dim
        self.timesformer_dim = timesformer_dim
        self.output_dim = output_dim
        self.fusion_method = fusion_method

        # 投影层
        self.siglip_projection = nn.Linear(siglip_dim, output_dim)
        self.timesformer_projection = nn.Linear(timesformer_dim, output_dim)

        # 可学习的融合权重
        if fusion_method == "weighted_sum":
            self.alpha = nn.Parameter(torch.tensor(0.5))
            self.beta = nn.Parameter(torch.tensor(0.5))

        # 注意力机制
        elif fusion_method == "attention":
            self.attention = nn.MultiheadAttention(output_dim, num_heads=8)
            self.query = nn.Linear(output_dim, output_dim)
            self.key = nn.Linear(output_dim, output_dim)
            self.value = nn.Linear(output_dim, output_dim)

        # 层归一化
        self.layer_norm = nn.LayerNorm(output_dim)

    def forward(
        self, siglip_features: torch.Tensor, timesformer_features: torch.Tensor
    ) -> torch.Tensor:
        """
        前向传播

        Args:
            siglip_features: SigLIP 特征 (batch_size, seq_len, siglip_dim)
            timesformer_features: TimeSformer 特征 (batch_size, seq_len, timesformer_dim)

        Returns:
            融合后的特征 (batch_size, seq_len, output_dim)
        """
        # 投影到相同维度
        siglip_proj = self.siglip_projection(siglip_features)
        timesformer_proj = self.timesformer_projection(timesformer_features)

        # 融合
        if self.fusion_method == "weighted_sum":
            # 加权和
            alpha = torch.softmax(torch.stack([self.alpha, self.beta]), dim=0)
            fused = alpha[0] * siglip_proj + alpha[1] * timesformer_proj

        elif self.fusion_method == "concat":
            # 拼接后投影
            fused = torch.cat([siglip_proj, timesformer_proj], dim=-1)
            fused = nn.Linear(self.output_dim * 2, self.output_dim).to(fused.device)(
                fused
            )

        elif self.fusion_method == "attention":
            # 注意力机制
            query = self.query(siglip_proj)
            key = self.key(timesformer_proj)
            value = self.value(timesformer_proj)

            attn_output, _ = self.attention(query, key, value)
            fused = self.layer_norm(siglip_proj + attn_output)

        else:
            raise ValueError(f"未知的融合方法: {self.fusion_method}")

        return fused


class GlobalPooling(nn.Module):
    """
    全局池化层

    将序列特征池化为全局特征向量
    """

    def __init__(self, pool_method: str = "mean"):
        """
        初始化池化层

        Args:
            pool_method: 池化方法 ('mean', 'max', 'attention')
        """
        super(GlobalPooling, self).__init__()
        self.pool_method = pool_method

        if pool_method == "attention":
            self.attention_weights = nn.Linear(512, 1)

    def forward(self, features: torch.Tensor) -> torch.Tensor:
        """
        前向传播

        Args:
            features: 输入特征 (batch_size, seq_len, feature_dim)

        Returns:
            全局特征向量 (batch_size, feature_dim)
        """
        if self.pool_method == "mean":
            # 平均池化
            pooled = features.mean(dim=1)

        elif self.pool_method == "max":
            # 最大池化
            pooled = features.max(dim=1)[0]

        elif self.pool_method == "attention":
            # 注意力池化
            attn_scores = torch.softmax(self.attention_weights(features), dim=1)
            pooled = (features * attn_scores).sum(dim=1)

        else:
            raise ValueError(f"未知的池化方法: {self.pool_method}")

        # L2 归一化
        pooled = pooled / (pooled.norm(dim=-1, keepdim=True) + 1e-8)

        return pooled


class VideoFeatureExtractor(nn.Module):
    """
    完整的视频特征提取器

    包括特征融合和全局池化
    """

    def __init__(
        self,
        siglip_dim: int = 768,
        timesformer_dim: int = 768,
        output_dim: int = 512,
        fusion_method: str = "weighted_sum",
        pool_method: str = "attention",
    ):
        """
        初始化特征提取器

        Args:
            siglip_dim: SigLIP 特征维度
            timesformer_dim: TimeSformer 特征维度
            output_dim: 输出特征维度
            fusion_method: 融合方法
            pool_method: 池化方法
        """
        super(VideoFeatureExtractor, self).__init__()

        self.fusion = FeatureFusion(
            siglip_dim, timesformer_dim, output_dim, fusion_method
        )

        self.pooling = GlobalPooling(pool_method)

    def forward(
        self, siglip_features: torch.Tensor, timesformer_features: torch.Tensor
    ) -> torch.Tensor:
        """
        前向传播

        Args:
            siglip_features: SigLIP 特征
            timesformer_features: TimeSformer 特征

        Returns:
            全局视频特征向量
        """
        # 特征融合
        fused = self.fusion(siglip_features, timesformer_features)

        # 全局池化
        global_feature = self.pooling(fused)

        return global_feature


def export_fusion_to_onnx(
    output_path: str = "fusion.onnx",
    siglip_dim: int = 768,
    timesformer_dim: int = 768,
    output_dim: int = 512,
):
    """
    导出融合模型到 ONNX

    Args:
        output_path: 输出路径
        siglip_dim: SigLIP 特征维度
        timesformer_dim: TimeSformer 特征维度
        output_dim: 输出特征维度
    """
    print("📦 初始化特征融合模型...")
    model = VideoFeatureExtractor(
        siglip_dim=siglip_dim,
        timesformer_dim=timesformer_dim,
        output_dim=output_dim,
        fusion_method="weighted_sum",
        pool_method="mean",
    )
    model.eval()

    # 准备示例输入
    batch_size = 4
    seq_len = 16

    dummy_siglip = torch.randn(batch_size, seq_len, siglip_dim)
    dummy_timesformer = torch.randn(batch_size, seq_len, timesformer_dim)

    print(f"🚀 导出融合模型到 {output_path}...")

    torch.onnx.export(
        model,
        (dummy_siglip, dummy_timesformer),
        output_path,
        input_names=["siglip_features", "timesformer_features"],
        output_names=["global_feature"],
        dynamic_axes={
            "siglip_features": {0: "batch_size", 1: "seq_len"},
            "timesformer_features": {0: "batch_size", 1: "seq_len"},
            "global_feature": {0: "batch_size"},
        },
        opset_version=17,
    )

    print(f"✅ 融合模型已导出到 {output_path}")
    return output_path


if __name__ == "__main__":
    # 导出到 ONNX
    export_fusion_to_onnx()

    # 测试推理
    print("\n🧪 测试特征融合...")
    fusion_model = VideoFeatureExtractor()

    siglip_feat = torch.randn(2, 16, 768)
    timesformer_feat = torch.randn(2, 16, 768)

    with torch.no_grad():
        global_feat = fusion_model(siglip_feat, timesformer_feat)

    print(f"✅ 融合特征形状: {global_feat.shape}")
    print(f"   特征范数: {global_feat.norm(dim=-1)}")
