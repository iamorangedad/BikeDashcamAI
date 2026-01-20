"""
视频分帧脚本

将视频分解为帧并保存为图像
"""

import cv2
import os
from pathlib import Path
from tqdm import tqdm
from typing import Optional


def extract_frames(
    video_path: str,
    output_dir: str,
    fps: int = 10,
    start_time: Optional[float] = None,
    end_time: Optional[float] = None,
) -> int:
    """
    从视频中提取帧

    Args:
        video_path: 视频文件路径
        output_dir: 输出目录
        fps: 提取帧率（每秒提取多少帧）
        start_time: 开始时间（秒）
        end_time: 结束时间（秒）

    Returns:
        提取的帧数
    """
    os.makedirs(output_dir, exist_ok=True)

    # 打开视频
    cap = cv2.VideoCapture(video_path)

    if not cap.isOpened():
        print(f"❌ 无法打开视频: {video_path}")
        return 0

    # 获取视频信息
    video_fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = total_frames / video_fps

    print(
        f"📹 视频信息: FPS={video_fps:.2f}, 总帧数={total_frames}, 时长={duration:.2f}s"
    )

    # 设置时间范围
    if start_time is None:
        start_time = 0
    if end_time is None:
        end_time = duration

    # 计算起始和结束帧
    start_frame = int(start_time * video_fps)
    end_frame = int(end_time * video_fps)

    # 跳转到起始帧
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

    # 计算帧间隔
    frame_interval = int(video_fps / fps)

    # 提取帧
    frame_count = 0
    saved_count = 0
    video_name = Path(video_path).stem

    current_frame = start_frame
    with tqdm(total=end_frame - start_frame, desc="提取帧") as pbar:
        while current_frame < end_frame:
            ret, frame = cap.read()

            if not ret:
                break

            # 按指定间隔保存帧
            if frame_count % frame_interval == 0:
                frame_path = os.path.join(
                    output_dir, f"{video_name}_{current_frame:06d}.jpg"
                )
                cv2.imwrite(frame_path, frame)
                saved_count += 1

            frame_count += 1
            current_frame += 1
            pbar.update(1)

    cap.release()
    print(f"✅ 提取了 {saved_count} 帧到 {output_dir}")
    return saved_count


def batch_extract_frames(video_dir: str, output_base_dir: str, fps: int = 10):
    """
    批量提取视频帧

    Args:
        video_dir: 视频目录
        output_base_dir: 输出基础目录
        fps: 提取帧率
    """
    video_files = list(Path(video_dir).glob("*.mp4"))
    print(f"📂 找到 {len(video_files)} 个视频文件")

    for video_file in tqdm(video_files, desc="处理视频"):
        video_name = video_file.stem
        output_dir = os.path.join(output_base_dir, video_name)

        extract_frames(str(video_file), output_dir, fps=fps)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="视频分帧工具")
    parser.add_argument("--video", type=str, help="视频文件路径")
    parser.add_argument("--video-dir", type=str, help="视频目录")
    parser.add_argument(
        "--output-dir", type=str, default="data/frames", help="输出目录"
    )
    parser.add_argument("--fps", type=int, default=10, help="提取帧率")
    parser.add_argument("--start-time", type=float, help="开始时间（秒）")
    parser.add_argument("--end-time", type=float, help="结束时间（秒）")

    args = parser.parse_args()

    if args.video:
        extract_frames(
            args.video, args.output_dir, args.fps, args.start_time, args.end_time
        )
    elif args.video_dir:
        batch_extract_frames(args.video_dir, args.output_dir, args.fps)
    else:
        print("❌ 请指定 --video 或 --video-dir")
