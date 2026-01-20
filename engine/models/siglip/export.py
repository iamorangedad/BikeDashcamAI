"""
SigLIP 模型导出为 TensorRT 引擎
"""

import torch
from transformers import SiglipModel, SiglipProcessor
import tensorrt as trt
import numpy as np


def export_siglip_to_onnx(output_path: str = "siglip.onnx"):
    """
    导出 SigLIP 到 ONNX 格式

    Args:
        output_path: 输出 ONNX 文件路径
    """
    print("📦 加载 SigLIP 模型...")
    model = SiglipModel.from_pretrained("google/siglip-base-patch16-224")
    model.eval()

    processor = SiglipProcessor.from_pretrained("google/siglip-base-patch16-224")

    # 准备示例输入
    dummy_image = torch.randn(1, 3, 224, 224)

    print(f"🚀 导出 SigLIP 到 {output_path}...")

    torch.onnx.export(
        model,
        dummy_image,
        output_path,
        input_names=["pixel_values"],
        output_names=["image_features"],
        dynamic_axes={
            "pixel_values": {0: "batch_size"},
            "image_features": {0: "batch_size"},
        },
        opset_version=17,
    )

    print(f"✅ SigLIP 已导出到 {output_path}")
    return output_path


def convert_onnx_to_tensorrt(
    onnx_path: str, engine_path: str = "siglip.plan", fp16_mode: bool = True
):
    """
    将 ONNX 模型转换为 TensorRT 引擎

    Args:
        onnx_path: ONNX 模型路径
        engine_path: 输出 TensorRT 引擎路径
        fp16_mode: 是否使用 FP16 精度
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

    # 设置最大工作空间
    config.max_workspace_size = 1 << 30  # 1GB

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


def test_inference(engine_path: str, input_image: np.ndarray):
    """
    测试 TensorRT 推理

    Args:
        engine_path: TensorRT 引擎路径
        input_image: 输入图像数组 (1, 3, 224, 224)
    """
    print(f"🧪 测试推理: {engine_path}")

    TRT_LOGGER = trt.Logger(trt.Logger.INFO)

    # 加载引擎
    with open(engine_path, "rb") as f:
        engine = trt.Runtime(TRT_LOGGER).deserialize_cuda_engine(f.read())

    # 创建执行上下文
    context = engine.create_execution_context()

    # 准备输入输出缓冲区
    inputs = [input_image]
    outputs = []
    bindings = []

    for i in range(engine.num_io_tensors):
        name = engine.get_tensor_name(i)
        dtype = trt.nptype(engine.get_tensor_dtype(name))
        shape = context.get_tensor_shape(name)

        if engine.get_tensor_mode(name) == trt.TensorIOMode.INPUT:
            bindings.append(inputs[i].astype(dtype).reshape(shape))
        else:
            output = np.empty(shape, dtype=dtype)
            outputs.append(output)
            bindings.append(output)

    # 执行推理
    print("🚀 执行推理...")
    for i in range(engine.num_io_tensors):
        context.set_tensor_address(engine.get_tensor_name(i), bindings[i].ctypes.data)

    context.execute_async_v3(0)

    print(f"✅ 推理完成，输出形状: {outputs[0].shape}")
    return outputs[0]


if __name__ == "__main__":
    # 导出到 ONNX
    onnx_path = export_siglip_to_onnx()

    # 转换为 TensorRT
    engine_path = convert_onnx_to_tensorrt(onnx_path)

    # 测试推理
    dummy_input = np.random.randn(1, 3, 224, 224).astype(np.float32)
    test_inference(engine_path, dummy_input)
