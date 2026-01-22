#!/usr/bin/env python3
"""
开发工具脚本
提供常用的开发命令快捷方式
"""

import subprocess
import sys
import os
from pathlib import Path


def run_command(cmd, cwd=None, check=True):
    """运行命令"""
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True, cwd=cwd, check=check)
    return result


def check_venv():
    """检查虚拟环境是否激活"""
    if not os.getenv("VIRTUAL_ENV"):
        print("❌ 虚拟环境未激活")
        print("请先激活虚拟环境: source .venv/bin/activate")
        return False
    return True


def run_tests():
    """运行测试"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return

    # 设置环境变量
    env = os.environ.copy()
    env["PYTHONPATH"] = str(project_root / "backend")

    cmd = [str(venv_python), "-m", "pytest"]
    if len(sys.argv) > 2:
        cmd.extend(sys.argv[2:])

    print(f"Running: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ 测试失败: {e}")
    except FileNotFoundError:
        print(f"❌ 虚拟环境Python未找到: {venv_python}")
        print("请先运行: python scripts/setup_dev.py")


def run_coverage():
    """运行覆盖率测试"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return

    env = os.environ.copy()
    env["PYTHONPATH"] = str(project_root / "backend")

    cmd = [
        str(venv_python),
        "-m",
        "pytest",
        "--cov=backend/app",
        "--cov-report=html",
        "--cov-report=term-missing",
    ]

    print(f"Running: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, env=env, check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ 覆盖率测试失败: {e}")


def lint_code():
    """代码检查和格式化"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return

    tools = ["black", "isort", "flake8"]
    for tool in tools:
        try:
            print(f"Running {tool}...")
            if tool == "black":
                subprocess.run(
                    [str(venv_python), "-m", "black", "backend/", "tests/"], check=True
                )
            elif tool == "isort":
                subprocess.run(
                    [str(venv_python), "-m", "isort", "backend/", "tests/"], check=True
                )
            elif tool == "flake8":
                subprocess.run(
                    [str(venv_python), "-m", "flake8", "backend/", "tests/"], check=True
                )
        except subprocess.CalledProcessError as e:
            print(f"❌ {tool} 失败: {e}")


def type_check():
    """类型检查"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return

    try:
        print("Running mypy...")
        subprocess.run([str(venv_python), "-m", "mypy", "backend/"], check=True)
    except subprocess.CalledProcessError as e:
        print(f"❌ mypy 失败: {e}")


def start_server():
    """启动开发服务器"""
    project_root = Path(__file__).parent.parent
    venv_python = project_root / ".venv" / "bin" / "python"

    if not venv_python.exists():
        print("❌ 虚拟环境未找到")
        print("请先运行: python scripts/setup_dev.py")
        return

    env = os.environ.copy()
    env["PYTHONPATH"] = str(project_root / "backend")

    if len(sys.argv) > 2 and sys.argv[2] == "--prod":
        cmd = [
            str(venv_python),
            "-m",
            "uvicorn",
            "app.main:app",
            "--host",
            "0.0.0.0",
            "--port",
            "8000",
        ]
    else:
        cmd = [
            str(venv_python),
            "-m",
            "uvicorn",
            "app.main:app",
            "--reload",
            "--host",
            "0.0.0.0",
            "--port",
            "8000",
        ]

    print(f"Starting server: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, env=env, cwd=project_root / "backend")
    except KeyboardInterrupt:
        print("\n服务器已停止")
    except subprocess.CalledProcessError as e:
        print(f"❌ 启动服务器失败: {e}")


def install_deps():
    """安装依赖"""
    run_command("uv pip install -e .")
    run_command("uv pip install -e '.[test,dev]'")


def show_help():
    """显示帮助信息"""
    print("""
BikeDashcamAI 开发工具

用法: python scripts/dev.py <command> [options]

命令:
  test [pytest_args]     - 运行测试
  coverage               - 运行覆盖率测试
  lint                   - 代码检查和格式化
  typecheck              - 类型检查
  server [--prod]        - 启动开发服务器
  install                - 安装依赖
  help                   - 显示帮助信息

示例:
  python scripts/dev.py test
  python scripts/dev.py test tests/test_api.py::TestHealthEndpoints
  python scripts/dev.py coverage
  python scripts/dev.py lint
  python scripts/dev.py typecheck
  python scripts/dev.py server
  python scripts/dev.py server --prod
""")


def main():
    if len(sys.argv) < 2:
        show_help()
        return

    command = sys.argv[1]

    if command == "test":
        run_tests()
    elif command == "coverage":
        run_coverage()
    elif command == "lint":
        lint_code()
    elif command == "typecheck":
        type_check()
    elif command == "server":
        start_server()
    elif command == "install":
        install_deps()
    elif command == "help":
        show_help()
    else:
        print(f"未知命令: {command}")
        show_help()


if __name__ == "__main__":
    main()
