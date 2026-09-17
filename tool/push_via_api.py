#!/usr/bin/env python3
"""通过 GitHub Git Data API 推送本地 HEAD 提交。

## 为什么需要它

本机 `github.com:443` 的 git 传输层不可靠：`curl https://github.com/`
能正常返回 200，但 `git push` 会挂住直到超时（表现为长时间无输出，
最终被 timeout 杀掉）。`api.github.com` 则始终稳定。

因此改用 Git Data API 完成推送，完全绕开 git 传输层。

## 原理

    POST  /git/blobs          每个文件一个（文本用 utf-8，二进制用 base64）
    POST  /git/trees          用 blob sha 列表组装目录树
    POST  /git/commits        附 message / author / parent，保留完整提交信息
    PATCH /git/refs/heads/main  更新分支引用

与 `git push --force` 不同，这里会读取远程当前 ref 作为 parent，
因此**保持线性历史**，不会把已有提交冲掉。

## 用法

    GH_TOKEN=github_pat_xxx python tool/push_via_api.py

    # 可选：覆盖默认值
    GH_TOKEN=xxx python tool/push_via_api.py --owner 某人 --repo 某仓库

## 注意

- token 需要 **Contents: Read and write** 权限。
  fine-grained token 里该项默认是 No access，必须手动改。
- 通过 `GET /repos/{owner}/{repo}` 看到的 `permissions: {push: true}`
  反映的是**账号对该仓库的角色**，不代表 token 有权写入。
  验证方式只有实际做一次写操作。
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

API = "https://api.github.com"


def api(method: str, path: str, payload=None):
    token = os.environ.get("GH_TOKEN")
    if not token:
        raise SystemExit("[错误] 未设置 GH_TOKEN 环境变量")

    url = f"{API}{path}"
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Accept", "application/vnd.github+json")
    if data:
        req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        print(f"  [HTTP {exc.code}] {method} {path}")
        print(f"  {detail[:400]}")
        raise


def api_soft(method: str, path: str):
    """失败返回 None，用于探测可选资源（如尚不存在的分支）。"""
    try:
        return api(method, path)
    except urllib.error.HTTPError:
        return None


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, encoding="utf-8"
    )
    if result.returncode != 0:
        raise SystemExit(f"[错误] git {' '.join(args)} 失败：{result.stderr}")
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser(description="通过 Git Data API 推送当前 HEAD")
    parser.add_argument("--owner", default="duixm", help="仓库所有者")
    parser.add_argument("--repo", default="pixel-bird", help="仓库名")
    parser.add_argument("--branch", default="main", help="分支名")
    args = parser.parse_args()

    owner, repo, branch = args.owner, args.repo, args.branch
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)

    head = git("rev-parse", "HEAD").strip()
    message = git("log", "-1", "--format=%B").strip()
    author_name = git("log", "-1", "--format=%an").strip()
    author_email = git("log", "-1", "--format=%ae").strip()
    files = [f for f in git("ls-files").split("\n") if f.strip()]

    print(f"本地 HEAD : {head[:12]}")
    print(f"文件数    : {len(files)}")

    ref = api_soft("GET", f"/repos/{owner}/{repo}/git/ref/heads/{branch}")
    parents: list[str] = []
    if ref and ref.get("object", {}).get("sha"):
        parents = [ref["object"]["sha"]]
        print(f"远程 HEAD : {parents[0][:12]}（将作为 parent，保持线性历史）")
    print()

    print("[1/4] 创建 blobs...")
    entries = []
    for i, path in enumerate(files, 1):
        raw = Path(path).read_bytes()
        try:
            content, encoding = raw.decode("utf-8"), "utf-8"
        except UnicodeDecodeError:
            content, encoding = base64.b64encode(raw).decode("ascii"), "base64"

        blob = api(
            "POST", f"/repos/{owner}/{repo}/git/blobs",
            {"content": content, "encoding": encoding},
        )
        entries.append({
            "path": path,
            "mode": "100755" if os.access(path, os.X_OK) else "100644",
            "type": "blob",
            "sha": blob["sha"],
        })
        if i % 25 == 0 or i == len(files):
            print(f"  {i}/{len(files)}")

    print("[2/4] 创建 tree...")
    tree = api("POST", f"/repos/{owner}/{repo}/git/trees", {"tree": entries})
    print(f"  {tree['sha'][:12]}")

    print("[3/4] 创建 commit...")
    payload = {
        "message": message,
        "tree": tree["sha"],
        "author": {"name": author_name, "email": author_email},
    }
    if parents:
        payload["parents"] = parents
    commit = api("POST", f"/repos/{owner}/{repo}/git/commits", payload)
    print(f"  {commit['sha'][:12]}")

    print(f"[4/4] 更新 refs/heads/{branch}...")
    if ref:
        api("PATCH", f"/repos/{owner}/{repo}/git/refs/heads/{branch}",
            {"sha": commit["sha"], "force": False})
    else:
        api("POST", f"/repos/{owner}/{repo}/git/refs",
            {"ref": f"refs/heads/{branch}", "sha": commit["sha"]})

    # 同步本地远程跟踪引用，让 git status 显示为已同步
    subprocess.run(["git", "update-ref", f"refs/remotes/origin/{branch}", head],
                   capture_output=True)

    print()
    print("=" * 52)
    print(f"推送完成: {commit['sha'][:12]}")
    print(f"https://github.com/{owner}/{repo}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
