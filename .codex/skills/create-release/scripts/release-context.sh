#!/usr/bin/env bash
set -euo pipefail

requested_tag="${1:-}"

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not inside a git repository." >&2
  exit 1
fi

root_dir="$(git rev-parse --show-toplevel)"
cd "$root_dir"

current_sha="$(git rev-parse HEAD)"
current_branch="$(git branch --show-current || true)"
status="$(git status --short)"

latest_release_tag=""
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  latest_release_tag="$(gh release list --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName // ""' 2>/dev/null || true)"
fi

if [[ -z "$latest_release_tag" ]]; then
  latest_release_tag="$(git tag --sort=-v:refname | sed -n '1p')"
fi

if [[ -z "$latest_release_tag" ]]; then
  echo "No prior tag or GitHub release was found." >&2
  exit 1
fi

if ! git rev-parse --verify "${latest_release_tag}^{commit}" >/dev/null 2>&1; then
  echo "Prior release tag '$latest_release_tag' is not available locally." >&2
  echo "Run: git fetch --tags origin" >&2
  exit 1
fi

prior_sha="$(git rev-parse "${latest_release_tag}^{commit}")"

suggested_tag=""
version_rule="Could not infer a patch bump because the prior tag is not vMAJOR.MINOR.PATCH."
if [[ "$latest_release_tag" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  suggested_tag="v${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
  version_rule="Default to the next patch tag: ${latest_release_tag} -> ${suggested_tag}."
fi

next_tag="${requested_tag:-$suggested_tag}"

cat <<EOF
# Release Context

Repository: $(basename "$root_dir")
Current branch: ${current_branch:-detached}
Current commit: $current_sha
Prior release tag: $latest_release_tag
Prior release commit: $prior_sha
Default next patch tag: ${suggested_tag:-unknown}
Selected next tag: ${next_tag:-unknown}

## Version Guidance

$version_rule

If the changes include substantial new user-facing features, new workflows, or
notable backwards-compatible capabilities, recommend a minor bump before
tagging. If the changes are breaking, remove behavior, require migration, or
drop support, recommend a major bump before tagging.

EOF

if [[ -n "$status" ]]; then
  cat <<EOF
## Worktree Status

\`\`\`
$status
\`\`\`

EOF
else
  cat <<EOF
## Worktree Status

Clean

EOF
fi

cat <<EOF
## Changed Files

\`\`\`
$(git diff --stat "${latest_release_tag}..HEAD")
\`\`\`

## Commits Since Prior Release

\`\`\`
$(git log --no-merges --date=short --pretty=format:'%h %ad %s' "${latest_release_tag}..HEAD")
\`\`\`

## Diff Summary

\`\`\`diff
$(git diff --compact-summary "${latest_release_tag}..HEAD")
\`\`\`
EOF
