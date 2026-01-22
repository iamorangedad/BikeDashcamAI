#!/usr/bin/env python3
"""
BikeDashcamAI开发环境设置脚本
使用uv进行本地开发环境配置
"""

import subprocess
import sys
import os
from pathlib import Path


def run_command(cmd, cwd=None, check=True):
    """运行命令"""
    print(f"Running: {cmd}")
    result = subprocess.run(
        cmd, shell=True, cwd=cwd, check=check, capture_output=True, text=True
    )
    if result.stdout:
        print(result.stdout)
    if result.stderr and result.returncode != 0:
        print(f"Error: {result.stderr}")
    return result


def check_uv_installed():
    """检查uv是否已安装"""
    try:
        result = run_command("uv --version", check=False)
        return result.returncode == 0
    except:
        return False


def install_uv():
    """安装uv"""
    print("Installing uv...")
    run_command("curl -LsSf https://astral.sh/uv/install.sh | sh")
    print("Please restart your terminal or run: source ~/.bashrc")


def setup_project():
    """设置项目"""
    project_root = Path(__file__).parent

    print("Setting up BikeDashcamAI development environment...")

    # 检查uv安装
    if not check_uv_installed():
        print("uv not found. Installing...")
        install_uv()
        return

    # 创建虚拟环境
    print("Creating virtual environment...")
    run_command("uv venv", cwd=project_root)

    # 激活虚拟环境并安装依赖
    print("Installing dependencies...")
    run_command("uv pip install -e .", cwd=project_root)

    # 安装开发依赖
    print("Installing development dependencies...")
    run_command("uv pip install -e '.[test,dev]'", cwd=project_root)

    # 创建.venv目录结构（如果不存在）
    venv_path = project_root / ".venv"
    if not venv_path.exists():
        print("Virtual environment not found. Please run setup again.")
        return

    print("✅ Development environment setup complete!")
    print("\nNext steps:")
    print("1. Activate virtual environment:")
    print("   source .venv/bin/activate  # On Windows: .venv\\Scripts\\activate")
    print("2. Run tests:")
    print("   pytest")
    print("3. Start development server:")
    print("   uvicorn app.main:app --reload")
    print("4. Run linting:")
    print("   black backend/")
    print("   isort backend/")
    print("   flake8 backend/")


def show_usage():
    """显示使用说明"""
    print("""
BikeDashcamAI Development Guide

环境设置:
  python scripts/setup_dev.py

常用命令:
  # 激活虚拟环境
  source .venv/bin/activate
  
  # 运行测试
  pytest
  
  # 运行测试并生成覆盖率报告
  pytest --cov=backend/app --cov-report=html
  
  # 代码格式化
  black backend/ tests/
  
  # 导入排序
  isort backend/ tests/
  
  # 代码检查
  flake8 backend/ tests/
  
  # 类型检查
  mypy backend/
  
  # 启动开发服务器
  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
  
  # 运行特定测试
  pytest tests/test_api.py::TestHealthEndpoints::test_health_check
  
  # 运行集成测试
  pytest -m integration
  
  # 跳过慢速测试
  pytest -m "not slow"
""")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--help":
        show_usage()
    else:
        setup_project()
