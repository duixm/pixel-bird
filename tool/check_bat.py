#!/usr/bin/env python3
"""对 .bat 文件做静态检查。

## 为什么需要它

`run_web.bat` 无法在开发沙箱内运行验证——cmd.exe 被安全策略拦截，
任何 .bat 都只返回零输出。既然不能动态验证，就用静态分析补上。

批处理的失败往往是**静默的**：脚本不报错，只是行为不对，或者干脆
什么都不做。下面这几类是最常见的：

| 陷阱 | 后果 |
|---|---|
| 非 ASCII 字节 | UTF-8 中文被 OEM 代码页（GBK）误解码，错位字节可能落在 `&` `|` 上，直接破坏语法 |
| 括号不配平 | 后续语句被吞进块里，或提前结束 |
| 延迟展开陷阱 | 块内 set 后用 `%VAR%` 读到的是**进入块之前**的旧值 |
| goto 悬空 | 跳转目标不存在，脚本直接终止 |
| LF 行尾 | 解析 if/for 多行块时可能出错 |

延迟展开那条尤其隐蔽：脚本看起来完全合理，跑起来也不报错，
只是变量永远拿到旧值。

## 用法

    python tool/check_bat.py              # 检查 run_web.bat
    python tool/check_bat.py 某文件.bat
    python tool/check_bat.py --selftest   # 自检：验证检查器本身有效

退出码：0 = 通过，1 = 发现问题。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# set "VAR=value" / set VAR=value / set "VAR="
SET_RE = re.compile(r'\bset\s+"?([A-Za-z_]\w*)\s*=', re.IGNORECASE)
USE_RE = re.compile(r"%([A-Za-z_]\w*)%")


def strip_comment(line: str) -> str:
    """去掉 rem / :: 注释行。"""
    if re.match(r"^\s*rem(\s|$)", line, re.IGNORECASE):
        return ""
    if re.match(r"^\s*::", line):
        return ""
    return line


def check_encoding(raw: bytes) -> list[str]:
    bad = [(i, b) for i, b in enumerate(raw) if b > 127]
    if not bad:
        return []
    lines = sorted({raw[:i].count(b"\n") + 1 for i, _ in bad})
    shown = ", ".join(str(n) for n in lines[:8])
    more = " 等" if len(lines) > 8 else ""
    return [f"含 {len(bad)} 个非 ASCII 字节，位于第 {shown}{more} 行"]


def check_line_endings(raw: bytes) -> list[str]:
    crlf = raw.count(b"\r\n")
    lone = raw.count(b"\n") - crlf
    if lone:
        return [f"有 {lone} 个裸 LF 行尾（{crlf} 个 CRLF），建议全部转 CRLF"]
    return []


def check_parens(lines: list[str]) -> list[str]:
    """检查 if/for 块括号配平。忽略引号内与注释中的括号。"""
    depth = 0
    issues: list[str] = []
    for no, raw_line in enumerate(lines, 1):
        line = strip_comment(raw_line)
        if not line.strip():
            continue
        in_quote = False
        for ch in line:
            if ch == '"':
                in_quote = not in_quote
            elif not in_quote:
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth < 0:
                        issues.append(f"第 {no} 行：多余的右括号")
                        depth = 0
    if depth != 0:
        issues.append(f"括号未配平，结尾仍有 {depth} 个未闭合的左括号")
    return issues


def check_delayed_expansion(lines: list[str]) -> list[str]:
    """检测块内 set 后用 %VAR% 读取的陈旧值问题。

    括号块在解析时一次性展开 %VAR%，所以块内 set 之后再用 %VAR%
    读到的仍是进入块之前的值。正确写法是 !VAR!（需
    enabledelayedexpansion）。
    """
    issues: list[str] = []
    block_vars: list[set[str]] = []

    for no, raw_line in enumerate(lines, 1):
        line = strip_comment(raw_line)
        if not line.strip():
            continue

        # 统计本行净括号增减（跳过引号内）
        in_quote = False
        delta = 0
        for ch in line:
            if ch == '"':
                in_quote = not in_quote
            elif not in_quote:
                if ch == "(":
                    delta += 1
                elif ch == ")":
                    delta -= 1

        if delta > 0:
            for _ in range(delta):
                block_vars.append(set())
        elif delta < 0:
            for _ in range(-delta):
                if block_vars:
                    block_vars.pop()

        # 本行新增的 set 记入当前块作用域
        for m in SET_RE.finditer(line):
            if block_vars:
                block_vars[-1].add(m.group(1).upper())

        # 本行读取的 %VAR% 若在当前（或外层）块内被 set 过，即为陷阱
        for m in USE_RE.finditer(line):
            var = m.group(1).upper()
            if any(var in scope for scope in block_vars):
                issues.append(
                    f"第 {no} 行：块内用 %{m.group(1)}% 读取，"
                    f"但该变量在同一个块内被 set 过，会读到旧值（应用 !{m.group(1)}!）"
                )
    return issues


def check_labels(lines: list[str]) -> list[str]:
    labels: set[str] = set()
    gotos: list[tuple[int, str]] = []
    for no, raw_line in enumerate(lines, 1):
        line = strip_comment(raw_line).strip()
        m = re.match(r"^:([A-Za-z_]\w*)", line)
        if m:
            labels.add(m.group(1).lower())
        for g in re.finditer(r"\bgoto\s+:?([A-Za-z_]\w*)", line, re.IGNORECASE):
            gotos.append((no, g.group(1)))

    return [
        f"第 {no} 行：goto :{target} 找不到对应标签"
        for no, target in gotos
        if target.lower() not in labels
    ]


CHECKS = (
    ("编码（纯 ASCII）", check_encoding),
    ("行尾格式", check_line_endings),
    ("括号配平", check_parens),
    ("延迟展开陷阱", check_delayed_expansion),
    ("goto / 标签", check_labels),
)


def run_checks(path: Path) -> int:
    raw = path.read_bytes()
    lines = raw.decode("utf-8", errors="replace").split("\n")

    print(f"检查文件: {path}")
    print(f"行数: {len(lines) - 1}   大小: {len(raw)} 字节")
    print()

    total = 0
    for name, fn in CHECKS:
        # 括号相关的检查按行处理，编码/行尾按原始字节处理
        issues = fn(raw) if fn in (check_encoding, check_line_endings) else fn(lines)
        if issues:
            total += len(issues)
            print(f"[!] {name}")
            for issue in issues:
                print(f"    - {issue}")
        else:
            print(f"[OK] {name}")

    print()
    print("=" * 56)
    if total:
        print(f"发现 {total} 个问题")
        return 1
    print("全部检查通过，未发现已知的批处理陷阱")
    return 0


# ---------------------------------------------------------------------------
# 自检
# ---------------------------------------------------------------------------

_GOOD = """@echo off
setlocal enabledelayedexpansion
set "PY="
where python >nul 2>&1
if not errorlevel 1 set "PY=python"
if not defined PY (
    for /d %%d in ("%USERPROFILE%\\py\\*") do (
        if exist "%%~fd\\python.exe" set "PY=%%~fd\\python.exe"
    )
)
if not defined PY (
    echo not found
    pause
    exit /b 1
)
echo Using: %PY%
"%PY%" "tool\\serve_web.py" %*
set "RC=%errorlevel%"
if not "%RC%"=="0" pause
exit /b %RC%
"""


def selftest() -> int:
    """验证检查器本身有效。

    一个永远返回 OK 的检查器没有意义，所以既要确认合法输入不误报，
    也要确认故意写错的输入能被检出。
    """
    passed = failed = 0

    def expect(name: str, issues: list, should_flag: bool) -> None:
        nonlocal passed, failed
        if bool(issues) == should_flag:
            detail = f"检出 {len(issues)} 项" if issues else "未误报"
            print(f"  [OK] {name} -> {detail}")
            passed += 1
        else:
            want = "检出" if should_flag else "不检出"
            print(f"  [!!] {name} -> 期望{want}，实际相反")
            for i in issues:
                print(f"        {i}")
            failed += 1

    good_lines = _GOOD.split("\n")
    good_bytes = _GOOD.replace("\n", "\r\n").encode("ascii")

    print("=" * 56)
    print("正向：合法输入不应误报")
    print("=" * 56)
    expect("编码", check_encoding(good_bytes), False)
    expect("行尾", check_line_endings(good_bytes), False)
    expect("括号配平", check_parens(good_lines), False)
    expect("延迟展开", check_delayed_expansion(good_lines), False)
    expect("goto / 标签", check_labels(good_lines), False)

    print()
    print("=" * 56)
    print("反向：故意写错必须检出")
    print("=" * 56)
    expect(
        "中文（UTF-8）",
        check_encoding("@echo off\necho 中文\n".encode("utf-8")),
        True,
    )
    expect("裸 LF 行尾", check_line_endings(b"@echo off\necho hi\n"), True)
    expect("未闭合左括号", check_parens("@echo off\nif defined X (\n  echo y\n".split("\n")), True)
    expect("多余右括号", check_parens("@echo off\nif defined X (\n  echo y\n))\n".split("\n")), True)
    expect(
        "块内 %VAR% 读新值",
        check_delayed_expansion(
            '@echo off\nif defined X (\n    set "PY=python"\n    echo %PY%\n)\n'.split("\n")
        ),
        True,
    )
    expect(
        "用 !VAR! 的正确写法",
        check_delayed_expansion(
            '@echo off\nsetlocal enabledelayedexpansion\nif defined X (\n'
            '    set "PY=python"\n    echo !PY!\n)\n'.split("\n")
        ),
        False,
    )
    expect("goto 悬空", check_labels("@echo off\ngoto :nowhere\n".split("\n")), True)
    expect(
        "goto 正常",
        check_labels("@echo off\ngoto :here\n:here\necho done\n".split("\n")),
        False,
    )

    print()
    print("=" * 56)
    print(f"结果: {passed} 通过 / {failed} 失败")
    print("=" * 56)
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()

    args = [a for a in argv[1:] if not a.startswith("-")]
    target = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "run_web.bat"
    if not target.exists():
        print(f"[错误] 文件不存在: {target}")
        return 1
    return run_checks(target)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
