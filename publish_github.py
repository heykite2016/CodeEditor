#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
通过 GitHub REST API 发布仓库。
本机 git 通道被代理拒绝（CONNECT 502），但 api.github.com 可达，故改用 Git Data API。
Token 从环境变量 GH_TOKEN 读取，不硬编码。

关键：auto_init=false 创建的空仓库，Git Data API 的 blobs 端点会返回
409 "Git Repository is empty"。需先用 Contents API 建首个 commit 初始化 git 后端。
"""
import os
import sys
import json
import base64
import subprocess
import urllib.request
import urllib.error
from datetime import datetime, timezone

ROOT = "/Users/mr.wangjia/Documents/WorkBuddy/Notepad"
OWNER = "heykite2016"
REPO = "CodeEditor"
TOKEN = os.environ.get("GH_TOKEN", "")
if not TOKEN:
    sys.exit("缺少 GH_TOKEN 环境变量")

API = "https://api.github.com"
AUTHOR = {"name": "王嘉", "email": "61083138+heykite2016@users.noreply.github.com"}
UA = "notepad-publish/1.0"


def req(method, path, data=None):
    url = API + path if path.startswith("/") else path
    headers = {
        "Authorization": "Bearer " + TOKEN,
        "Accept": "application/vnd.github+json",
        "User-Agent": UA,
    }
    body = None
    if data is not None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=60) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            err = json.loads(raw)
        except Exception:
            err = raw.decode("utf-8", "replace")
        return e.code, err


def need(status, ok, what, res):
    if status not in ok:
        sys.exit("%s 失败 HTTP %s: %s" % (what, status, res))


def main():
    # 1) 创建公开仓库（已存在则复用）
    st, res = req("POST", "/user/repos", {
        "name": REPO,
        "description": "原生 Swift + AppKit 实现的轻量 macOS 代码编辑器：Windows 记事本 1:1 复刻 + 29 种语言语法高亮",
        "homepage": "https://github.com/%s/%s" % (OWNER, REPO),
        "private": False,
        "has_issues": True,
        "has_wiki": False,
        "auto_init": False,
    })
    need(st, (201, 422), "创建仓库", res)
    print("仓库:", res.get("html_url") if isinstance(res, dict) and res.get("html_url") else "(已存在，复用)")

    # 2) 初始化空仓库 git 后端：Contents API 建首个 commit
    with open(os.path.join(ROOT, "README.md"), "rb") as f:
        readme = f.read()
    st, init = req("PUT", "/repos/%s/%s/contents/README.md" % (OWNER, REPO), {
        "message": "Initialize repository",
        "content": base64.b64encode(readme).decode("ascii"),
    })
    st2, info = req("GET", "/repos/%s/%s" % (OWNER, REPO))
    branch = info.get("default_branch", "main") if isinstance(info, dict) else "main"
    if st == 201:
        init_sha = init["commit"]["sha"]
        print("初始化完成 init commit: %s (分支 %s)" % (init_sha[:8], branch))
    elif st == 422:
        st3, br = req("GET", "/repos/%s/%s/branches/%s" % (OWNER, REPO, branch))
        need(st3, (200,), "获取分支 " + branch, br)
        init_sha = br["commit"]["sha"]
        print("仓库已有内容 HEAD: %s (分支 %s)" % (init_sha[:8], branch))
    else:
        sys.exit("初始化失败 HTTP %s: %s" % (st, init))

    # 3) tracked 文件清单
    out = subprocess.check_output(
        ["git", "-c", "core.quotepath=false", "ls-files", "-z"], cwd=ROOT)
    files = [p.decode("utf-8") for p in out.split(b"\x00") if p]
    print("文件数:", len(files))

    # 4) 逐个创建 blob
    tree = []
    for i, path in enumerate(files, 1):
        with open(os.path.join(ROOT, path), "rb") as f:
            content = f.read()
        st, blob = req("POST", "/repos/%s/%s/git/blobs" % (OWNER, REPO), {
            "encoding": "base64",
            "content": base64.b64encode(content).decode("ascii"),
        })
        need(st, (201, 200), "blob " + path, blob)
        mode = "100755" if path.endswith(".sh") else "100644"
        tree.append({"path": path, "mode": mode, "type": "blob", "sha": blob["sha"]})
        print("  [%d/%d] %s" % (i, len(files), path))

    # 5) 创建 tree
    st, tr = req("POST", "/repos/%s/%s/git/trees" % (OWNER, REPO), {"tree": tree})
    need(st, (201,), "创建 tree", tr)

    # 6) 创建发布 commit（parent 指向 init commit，保证 fast-forward）
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    message = ("Initial release: 代码编辑器 v2.0.0\n\n"
               "原生 Swift + AppKit 实现的轻量 macOS 代码编辑器。\n"
               "Windows 记事本 1:1 复刻 + 29 种语言语法高亮 / 行号栏 / 智能缩进 / 6 套主题。")
    st, cm = req("POST", "/repos/%s/%s/git/commits" % (OWNER, REPO), {
        "message": message,
        "author": dict(AUTHOR, date=now),
        "committer": dict(AUTHOR, date=now),
        "tree": tr["sha"],
        "parents": [init_sha],
    })
    need(st, (201,), "创建 commit", cm)

    # 7) fast-forward 更新分支 ref
    st, rf = req("PATCH", "/repos/%s/%s/git/refs/heads/%s" % (OWNER, REPO, branch),
                 {"sha": cm["sha"]})
    need(st, (200,), "更新 ref", rf)

    # 8) 确保默认分支
    req("PATCH", "/repos/%s/%s" % (OWNER, REPO), {"default_branch": branch})

    # 9) 创建 Release
    body = ("## 代码编辑器 v2.0.0\n\n"
            "Universal 构建（Apple Silicon + Intel），macOS 12.0+。\n\n"
            "### 安装\n"
            "下载 zip 解压后把 `代码编辑器.app` 拖入 `/Applications`；或打开 dmg 拖拽安装。\n"
            "ad-hoc 签名，首次打开若被 Gatekeeper 拦截：系统设置 → 隐私与安全性 → 仍要打开，"
            "或执行 `xattr -cr /Applications/代码编辑器.app`。\n\n"
            "### SHA-256\n"
            "- zip: bce5733b8b6197fcd3d948cb69e64ab929cd23ba52b3f45c85574659a9aae093\n"
            "- dmg: 1910e26b58fb9763590c707773de3e0bd455433bee9e8a806facc082b7a2e4fb\n")
    st, rel = req("POST", "/repos/%s/%s/releases" % (OWNER, REPO), {
        "tag_name": "v2.0.0",
        "name": "代码编辑器 v2.0.0",
        "body": body,
        "draft": False,
        "prerelease": False,
        "target_commitish": branch,
    })
    need(st, (201,), "创建 Release", rel)

    print("")
    print("REPO_URL=https://github.com/%s/%s" % (OWNER, REPO))
    print("RELEASE_ID=%s" % rel["id"])
    print("RELEASE_URL=%s" % rel["html_url"])
    print("UPLOAD_URL=%s" % rel["upload_url"].split("{")[0])
    print("BRANCH=%s" % branch)


if __name__ == "__main__":
    main()
