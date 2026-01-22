#!/usr/bin/env python3
"""
快速测试运行脚本
"""

import subprocess
import sys
import os
from pathlib import Path


def run_in_venv(cmd):
    """在虚拟环境中运行命令"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return False

    # 设置环境变量
    env = os.environ.copy()
    env["PYTHONPATH"] = str(project_root / "backend")

    try:
        subprocess.run([str(venv_python), "-m"] + cmd, check=True, env=env)
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ 命令执行失败: {e}")
        return False
    except FileNotFoundError:
        print(f"❌ 虚拟环境Python未找到: {venv_python}")
        return False


def main():
    if len(sys.argv) < 2:
        print("用法: python scripts/run_test.py [pytest_args...]")
        print("示例:")
        print("  python scripts/run_test.py test_api.py")
        print("  python scripts/run_test.py test_api.py::TestHealthEndpoints")
        print("  python scripts/run_test.py -v -s test_api.py")
        return

    # 转换命令行参数
    pytest_args = sys.argv[1:]
    cmd = ["pytest"] + pytest_args

    print(f"运行: {' '.join(cmd)}")
    success = run_in_venv(cmd)

    if not success:
        print("\n💡 尝试以下步骤:")
        print("1. source .venv/bin/activate")
        print("2. pytest " + " ".join(pytest_args))


if __name__ == "__main__":
    main()
