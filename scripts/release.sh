#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: scripts/release.sh <version>"
    echo "Example: scripts/release.sh 0.1.0"
    exit 1
fi

version="$1"
tag="v${version}"

if git rev-parse "$tag" >/dev/null 2>&1; then
    echo "Error: tag $tag already exists"
    exit 1
fi

git tag "$tag"
git push origin "$tag"

echo "Pushed $tag — release will be created by GitHub Actions"
