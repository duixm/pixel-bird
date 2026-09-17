#!/usr/bin/env python3
"""像素小鸟 - 本地 Web 预览启动器。

把「判断是否需构建 -> 构建 -> 修 shader -> 起服务 -> 开浏览器」
串成一条命令，并自动跳过不必要的重复构建。

## 为什么需要这个脚本

两个本机工具链缺陷，与游戏代码无关：

1. `flutter run -d edge` / `-d web-server` 需要调用 reg.exe 探测浏览器版本，
   本机 reg.exe 被安全策略拉黑，命令直接失败
   -> 改用 Python 静态服务器托管构建产物。
2. `flutter build web` 编译内置 shader (ink_sparkle.frag) 时，impellerc
   收不到 shader_lib 的 include 路径而失败
   -> 构建后手动补编译这一个文件。

## 一个重要的判定陷阱

`flutter build web --debug` 即使**产物完整**，退出码也可能是非 0
（原因见上面第 2 点）。因此本脚本以「产物文件是否存在且非空」判定成功，
**不能**依赖退出码，否则会误报构建失败。

## 用法

    python tool/serve_web.py              # 自动判断是否需要构建
    python tool/serve_web.py --rebuild    # 强制重新构建
    python tool/serve_web.py --fast       # 跳过构建，直接用现有产物
    python tool/serve_web.py --port 9000  # 换端口（默认 8090）
    python tool/serve_web.py --no-open    # 不自动打开浏览器
"""

from __future__ import annotations

import argparse
import http.server
import os
import shutil
import socketserver
import subprocess
import sys
import threading
import time
import webbrowser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEB_DIR = ROOT / "build" / "web"
MAIN_JS = WEB_DIR / "main.dart.js"
SHADER_OUT = WEB_DIR / "assets" / "shaders" / "ink_sparkle.frag"
BUILD_DIR = ROOT / "build"

# 影响 web 构建的源文件范围
SOURCE_PATTERNS = ("lib/**/*.dart", "web/**/*", "pubspec.yaml")


def flutter_root() -> Path:
    """定位 Flutter SDK 根目录。"""
    env = os.environ.get("FLUTTER_ROOT")
    if env and Path(env).exists():
        return Path(env)
    return Path.home() / "flutter"


def engine_dir() -> Path:
    return flutter_root() / "bin" / "cache" / "artifacts" / "engine" / "windows-x64"


def find_edge() -> Path | None:
    """定位 Edge 可执行文件。"""
    candidates = [
        Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
        Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    ]
    for path in candidates:
        if path.exists():
            return path
    return None


def strip_proxy_env() -> None:
    """清除代理环境变量。

    本机代理会阻断 pub.dev，也会破坏 flutter_tester 的本地 WebSocket 握手，
    因此构建前必须清掉。
    """
    for key in ("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY"):
        os.environ.pop(key, None)
    os.environ.setdefault("PUB_CACHE", str(Path.home() / ".pub-cache"))


def newest_source_mtime() -> float:
    newest = 0.0
    for pattern in SOURCE_PATTERNS:
        for path in ROOT.glob(pattern):
            if path.is_file():
                newest = max(newest, path.stat().st_mtime)
    return newest


def needs_build() -> tuple[bool, str]:
    """判断是否需要重新构建，返回 (是否需要, 原因)。"""
    if not MAIN_JS.exists() or MAIN_JS.stat().st_size == 0:
        return True, "构建产物不存在"

    if newest_source_mtime() > MAIN_JS.stat().st_mtime:
        return True, "源码有改动"

    if not SHADER_OUT.exists() or SHADER_OUT.stat().st_size == 0:
        return True, "shader 缺失"

    return False, "产物已是最新"


def run_build() -> bool:
    """执行 flutter build web --debug。"""
    flutter = flutter_root() / "bin" / "flutter.bat"
    if not flutter.exists():
        print(f"  [错误] 找不到 Flutter: {flutter}")
        return False

    print("  正在编译（约 1-2 分钟）...")
    proc = subprocess.run(
        [str(flutter), "build", "web", "--debug"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    # 关键：不依赖退出码，以产物为准。
    # 本机 shader 编译必然失败并导致非 0 退出，但主体产物是完整的。
    if MAIN_JS.exists() and MAIN_JS.stat().st_size > 0:
        size_mb = MAIN_JS.stat().st_size / 1024 / 1024
        print(f"  产物已生成 ({size_mb:.1f} MB)")
        return True

    print("  [错误] 构建失败，产物未生成。Flutter 输出：")
    tail = (proc.stdout or "")[-1500:]
    print(tail)
    return False


def ensure_shader() -> bool:
    """补编译 Flutter 内置 shader。返回是否就绪。"""
    if SHADER_OUT.exists() and SHADER_OUT.stat().st_size > 0:
        return True

    impellerc = engine_dir() / "impellerc.exe"
    shader_lib = engine_dir() / "shader_lib"
    src = (
        flutter_root()
        / "packages"
        / "flutter"
        / "lib"
        / "src"
        / "material"
        / "shaders"
        / "ink_sparkle.frag"
    )

    if not impellerc.exists() or not src.exists():
        return False

    SHADER_OUT.parent.mkdir(parents=True, exist_ok=True)

    # 把 include 目录和源文件都放进 build/ 下，之后全部用相对路径调用。
    # impellerc 对路径处理比较脆弱，相对路径最稳。
    include_dir = BUILD_DIR / "shader_lib"
    (include_dir / "flutter").mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        shader_lib / "flutter" / "runtime_effect.glsl",
        include_dir / "flutter" / "runtime_effect.glsl",
    )
    shutil.copy2(src, BUILD_DIR / "ink_sparkle.frag")

    subprocess.run(
        [
            str(impellerc),
            "--sksl",
            "--input=ink_sparkle.frag",
            "--input-type=frag",
            "--sl=web/assets/shaders/ink_sparkle.frag",
            "--spirv=shader_lib/ink_sparkle.spirv",
            "--include=shader_lib",
        ],
        cwd=BUILD_DIR,
        capture_output=True,
    )
    return SHADER_OUT.exists() and SHADER_OUT.stat().st_size > 0


class Handler(http.server.SimpleHTTPRequestHandler):
    """静态文件处理器，附加禁用缓存。"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(WEB_DIR), **kwargs)

    def end_headers(self):
        # 开发预览场景下禁用缓存，避免改代码后看到旧产物
        self.send_header("Cache-Control", "no-store, must-revalidate")
        super().end_headers()

    def log_message(self, fmt, *args):
        # 只输出异常请求，正常 200 不刷屏
        message = fmt % args
        if " 200 " not in message and " 304 " not in message:
            sys.stderr.write(f"    {message}\n")


class Server(socketserver.ThreadingTCPServer):
    """静态服务器。

    allow_reuse_address 只在非 Windows 平台启用。Windows 的
    SO_REUSEADDR 语义与 Unix 不同：Unix 只允许复用 TIME_WAIT 状态的
    socket，而 Windows 允许两个进程同时绑定同一端口（端口劫持）。
    若在 Windows 上开启，端口冲突会静默成功而不是报错，用户会看到
    两个服务器抢同一端口却没有任何提示。
    """

    allow_reuse_address = os.name != "nt"
    daemon_threads = True


def serve(port: int, open_browser: bool) -> int:
    try:
        httpd = Server(("127.0.0.1", port), Handler)
    except OSError as exc:
        print(f"  [错误] 无法监听 {port} 端口：{exc}")
        print(f"  提示：换一个端口，例如 --port {port + 1}")
        return 1

    url = f"http://127.0.0.1:{port}/"
    print(f"  服务已启动: {url}")

    if open_browser:
        edge = find_edge()
        if edge:
            subprocess.Popen([str(edge), "--new-window", url])
            print("  已在 Edge 中打开")
        else:
            webbrowser.open(url)
            print("  已在默认浏览器中打开")

    print()
    print("=" * 58)
    print("  按 Ctrl+C 停止服务器")
    print()
    print("  操作提示：")
    print("    - 按 F12，再按 Ctrl+Shift+M 切换到手机模拟视图")
    print("    - 选一个竖屏机型（如 iPhone 12 Pro）体验真实手感")
    print("    - 点击画面开始游戏")
    print("=" * 58)
    print()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n  已停止。")
    finally:
        httpd.server_close()
    return 0


def main() -> int:
    # 行缓冲：输出被管道重定向时仍能看到实时进度
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except (AttributeError, OSError):
        pass

    parser = argparse.ArgumentParser(
        description="像素小鸟本地预览启动器",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--rebuild", "-r", action="store_true", help="强制重新构建")
    parser.add_argument("--fast", "-f", action="store_true", help="跳过构建，直接用现有产物")
    parser.add_argument("--port", "-p", type=int, default=8090, help="监听端口（默认 8090）")
    parser.add_argument("--no-open", action="store_true", help="不自动打开浏览器")
    args = parser.parse_args()

    if args.rebuild and args.fast:
        print("[错误] --rebuild 与 --fast 不能同时使用")
        return 2

    os.chdir(ROOT)
    strip_proxy_env()

    print()
    print("[1/3] 检查构建状态...")

    if args.fast:
        if not MAIN_JS.exists():
            print("  [错误] --fast 指定跳过构建，但没有可用产物。")
            print("  请去掉 --fast 先构建一次。")
            return 1
        print("  已跳过构建（--fast）")
    else:
        if args.rebuild:
            need, reason = True, "指定了 --rebuild"
        else:
            need, reason = needs_build()

        print(f"  {reason}")

        if need:
            if not run_build():
                return 1
        else:
            print("  跳过编译，直接用现有产物")

    print()
    print("[2/3] 检查内置 shader...")
    if ensure_shader():
        print("  已就绪")
    else:
        print("  [警告] shader 补编译未成功。")
        print("         游戏主体功能不受影响，仅 Material 水波纹特效缺失。")

    print()
    print("[3/3] 启动服务器...")
    return serve(args.port, open_browser=not args.no_open)


if __name__ == "__main__":
    sys.exit(main())
