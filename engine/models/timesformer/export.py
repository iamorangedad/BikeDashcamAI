"""
TimeSformer 模型导出为 TensorRT 引擎
"""

import torch
from transformers import TimesformerModel, TimesformerImageProcessor
import tensorrt as trt
import numpy as np


def export_timesformer_to_onnx(
    output_path: str = "timesformer.onnx", num_frames: int = 16
):
    """
    导出 TimeSformer 到 ONNX 格式

    Args:
        output_path: 输出 ONNX 文件路径
        num_frames: 输入视频帧数
    """
    print("📦 加载 TimeSformer 模型...")
    model = TimesformerModel.from_pretrained("facebook/timesformer-base-finetuned-k400")
    model.eval()

    processor = TimesformerImageProcessor.from_pretrained(
        "facebook/timesformer-base-finetuned-k400"
    )

    # 准备示例输入: (batch_size, num_frames, channels, height, width)
    dummy_video = torch.randn(1, num_frames, 3, 224, 224)

    print(f"🚀 导出 TimeSformer 到 {output_path}...")

    torch.onnx.export(
        model,
        dummy_video,
        output_path,
        input_names=["pixel_values"],
        output_names=["last_hidden_state", "pooler_output"],
        dynamic_axes={
            "pixel_values": {0: "batch_size", 1: "num_frames"},
            "last_hidden_state": {0: "batch_size", 1: "num_frames"},
            "pooler_output": {0: "batch_size"},
        },
        opset_version=17,
        do_constant_folding=True,
    )

    print(f"✅ TimeSformer 已导出到 {output_path}")
    return output_path


def convert_onnx_to_tensorrt(
    onnx_path: str,
    engine_path: str = "timesformer.plan",
    fp16_mode: bool = True,
    num_frames: int = 16,
):
    """
    将 ONNX 模型转换为 TensorRT 引擎

    Args:
        onnx_path: ONNX 模型路径
        engine_path: 输出 TensorRT 引擎路径
        fp16_mode: 是否使用 FP16 精度
        num_frames: 输入视频帧数
    """
    TRT_LOGGER = trt.Logger(trt.Logger.INFO)

    print("🔧 初始化 TensorRT...")
    builder = trt.Builder(TRT_LOGGER)
    network = builder.create_network(
        1 << int(trt.NetworkDefinitionCreationFlag.EXPLICIT_BATCH)
    )
    parser = trt.OnnxParser(network, TRT_LOGGER)

    print(f"📖 读取 ONNX 模型: {onnx_path}")
    with open(onnx_path, "rb") as model:
        if not parser.parse(model.read()):
            print("❌ ONNX 解析失败:")
            for error in range(parser.num_errors):
                print(parser.get_error(error))
            return

    print("✅ ONNX 模型解析成功")

    # 配置 TensorRT
    config = builder.create_builder_config()

    if fp16_mode and builder.platform_has_fast_fp16:
        config.set_flag(trt.BuilderFlag.FP16)
        print("⚡ 启用 FP16 模式")

    # 设置优化配置文件
    profile = builder.create_optimization_profile()

    # 设置输入维度范围
    min_shape = (1, 1, 3, 224, 224)
    opt_shape = (1, num_frames, 3, 224, 224)
    max_shape = (4, 32, 3, 224, 224)

    profile.set_shape("pixel_values", min_shape, opt_shape, max_shape)
    config.add_optimization_profile(profile)

    # 设置最大工作空间
    config.max_workspace_size = 1 << 31  # 2GB

    print("🔨 构建 TensorRT 引擎...")
    serialized_engine = builder.build_serialized_network(network, config)

    if not serialized_engine:
        print("❌ TensorRT 引擎构建失败")
        return

    print(f"💾 保存 TensorRT 引擎到 {engine_path}")
    with open(engine_path, "wb") as f:
        f.write(serialized_engine)

    print("✅ TensorRT 引擎构建完成")
    return engine_path


def test_inference(engine_path: str, input_video: np.ndarray):
    """
    测试 TensorRT 推理

    Args:
        engine_path: TensorRT 引擎路径
        input_video: 输入视频数组 (batch_size, num_frames, channels, height, width)
    """
    print(f"🧪 测试推理: {engine_path}")

    TRT_LOGGER = trt.Logger(trt.Logger.INFO)

    # 加载引擎
    with open(engine_path, "rb") as f:
        engine = trt.Runtime(TRT_LOGGER).deserialize_cuda_engine(f.read())

    # 创建执行上下文
    context = engine.create_execution_context()

    # 准备输入输出缓冲区
    inputs = [input_video]
    outputs = []
    bindings = []

    for i in range(engine.num_io_tensors):
        name = engine.get_tensor_name(i)
        dtype = trt.nptype(engine.get_tensor_dtype(name))

        if engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT:
            # 设置动态维度
            context.set_input_shape(name, inputs[0].shape)
            shape = inputs[0].shape
            bindings.append(inputs[i].astype(dtype).reshape(shape))
        else:
            shape = context.get_tensor_shape(name)
            output = np.empty(shape, dtype=dtype)
            outputs.append(output)
            bindings.append(output)

    # 执行推理
    print("🚀 执行推理...")
    for i in range(engine.num_io_tensors):
        context.set_tensor_address(engine.get_tensor_name(i), bindings[i].ctypes.data)

    context.execute_async_v3(0)

    print(f"✅ 推理完成")
    for i, output in enumerate(outputs):
        print(f"   输出 {i} 形状: {output.shape}")

    return outputs


if __name__ == "__main__":
    # 导出到 ONNX
    onnx_path = export_timesformer_to_onnx()

    # 转换为 TensorRT
    engine_path = convert_onnx_to_tensorrt(onnx_path)

    # 测试推理
    dummy_input = np.random.randn(1, 16, 3, 224, 224).astype(np.float32)
    test_inference(engine_path, dummy_input)
