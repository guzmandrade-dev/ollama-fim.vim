#!/usr/bin/env bash
# Build local release artifacts into build/ (same file list as the GitHub
# release vimball — see scripts/release_files.vim):
#   build/ollama-fim-<version>.vmb   vimball (vimball-style install)
#   build/ollama-fim-<version>.zip   for the vim.org upload form (wants a zip)
#
# Usage:
#   bash scripts/dist.sh            # version = latest git tag (v1.4.0 -> 1.4.0)
#   bash scripts/dist.sh 1.4.1      # explicit version
#   make dist                       # same, via the Makefile
set -u
cd "$(dirname "$0")/.."

if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
    if [ -z "$VERSION" ]; then
        VERSION="$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -1)"
    fi
fi
if [ -z "${VERSION:-}" ]; then
    echo "dist.sh: cannot determine version (no arg, no git tag, no CHANGELOG entry)" >&2
    exit 1
fi

mkdir -p build
VMB="build/ollama-fim-$VERSION.vmb"
ZIP="build/ollama-fim-$VERSION.zip"
rm -f "$VMB" "$ZIP"

echo "==> vimball: $VMB"
VERSION="$VERSION" vim -u NONE -N -n -es -c 'set fileformat=unix' \
    -c 'source scripts/mkvimball.vim' -c 'quit' || exit 1

# Ask Vim for the exact shipped file list so the zip matches the vmb.
vim -u NONE -N -n -es \
    -c 'source scripts/release_files.vim' \
    -c 'call writefile(ReleaseFiles(), "build/.dist-files.txt")' \
    -c 'quit' || exit 1

FILES="$(tr '\n' ' ' < build/.dist-files.txt)"
rm -f build/.dist-files.txt

echo "==> zip: $ZIP"
if command -v zip >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    zip -q -r "$ZIP" $FILES
elif command -v python3 >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    python3 scripts/mkzip.py "$ZIP" $FILES
else
    # Windows fallback: stage the files, then Compress-Archive.
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    for f in $FILES; do
        mkdir -p "$TMP/$(dirname "$f")"
        cp "$f" "$TMP/$f"
    done
    powershell -NoProfile -Command \
        "Compress-Archive -Path '$TMP/*' -DestinationPath '$PWD/$ZIP' -Force"
fi

echo "==> done:"
ls -la build/ollama-fim-$VERSION.*
