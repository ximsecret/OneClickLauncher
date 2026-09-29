#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

REPO_NAME="${1:-OneClickLauncher}"
VISIBILITY="${2:---public}" # --public or --private

echo "==> Checking GitHub CLI authentication..."
if ! gh auth status >/dev/null 2>&1; then
    echo "⚠️  尚未登录 GitHub CLI，正在启动浏览器网页授权..."
    gh auth login --hostname github.com --git-protocol https --web
fi

echo "==> Creating GitHub repository '$REPO_NAME' ($VISIBILITY) and pushing code..."
gh repo create "$REPO_NAME" "$VISIBILITY" --source="$DIR" --remote=origin --push

echo "✅ 源码已成功上传至您的 GitHub 仓库！"
gh repo view --web || true
