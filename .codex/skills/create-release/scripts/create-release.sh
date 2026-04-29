#!/usr/bin/env bash
set -euo pipefail

tag="${1:-}"
notes_file="${2:-}"

usage() {
  echo "Usage: $0 <tag> <notes-file>" >&2
}

if [[ -z "$tag" || -z "$notes_file" ]]; then
  usage
  exit 2
fi

if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Tag must use vMAJOR.MINOR.PATCH format, got '$tag'." >&2
  exit 1
fi

if [[ ! -f "$notes_file" ]]; then
  echo "Notes file not found: $notes_file" >&2
  exit 1
fi

if ! grep -q '[^[:space:]]' "$notes_file"; then
  echo "Notes file is empty: $notes_file" >&2
  exit 1
fi

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

root_dir="$(git rev-parse --show-toplevel)"
cd "$root_dir"

if [[ -n "$(git status --short)" ]]; then
  echo "Worktree is dirty. Commit or stash changes before creating a release tag." >&2
  git status --short >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "No origin remote is configured." >&2
  exit 1
fi

git fetch --tags origin

if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Local tag already exists: $tag" >&2
  exit 1
fi

if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
  echo "Remote tag already exists on origin: $tag" >&2
  exit 1
fi

if [[ -x scripts/test.sh ]]; then
  scripts/test.sh
fi

if [[ -x scripts/build.sh ]]; then
  scripts/build.sh
fi

git tag -a "$tag" -F "$notes_file"

if [[ "$(git cat-file -t "refs/tags/$tag")" != "tag" ]]; then
  echo "Created tag is not annotated: $tag" >&2
  git tag -d "$tag" >/dev/null 2>&1 || true
  exit 1
fi

git push origin "$tag"

repo_url="$(git remote get-url origin)"
repo_slug="$repo_url"
repo_slug="${repo_slug#git@github.com:}"
repo_slug="${repo_slug#https://github.com/}"
repo_slug="${repo_slug%.git}"

echo "Pushed annotated release tag: $tag"
if [[ "$repo_slug" == */* ]]; then
  echo "Release workflow: https://github.com/$repo_slug/actions/workflows/release.yml"
fi
