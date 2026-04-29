---
name: create-release
description: Create a real GitHub release from the local repo by comparing the current commit to the prior published release, drafting annotated tag release notes, validating the build/tests, creating an annotated git tag, and pushing that tag to origin to trigger the release workflow. Use when Codex is asked to create, cut, publish, or ship a release; make release notes; bump to a new vMAJOR.MINOR.PATCH tag; or trigger the release workflow. This skill creates/pushes tags and does not create draft releases.
---

# Create Release

## Contract

Create a release by pushing an annotated git tag. The tag message is the release
notes source of truth, and the GitHub Actions release workflow publishes the
non-draft GitHub Release after the tag is pushed.

Do not create or commit `release-notes.md`. Do not create draft releases. Do not
stop after drafting notes unless the user explicitly asks for a dry run.

## Workflow

1. Refresh context:
   - Run `git fetch --tags origin` when an `origin` remote exists.
   - Run `scripts/release-context.sh [next-tag]` from this skill directory.
   - Prefer the latest published GitHub release as the prior release when `gh` is authenticated; otherwise use the latest local version tag.
2. Choose the next tag:
   - Preserve the repo's existing format, usually `vMAJOR.MINOR.PATCH`.
   - Find the previous published release tag or latest local version tag.
   - When the prior tag is `vMAJOR.MINOR.PATCH` and the user did not specify a tag, default to `vMAJOR.MINOR.(PATCH + 1)`. For example, `v0.0.11` becomes `v0.0.12`.
   - Use the user's requested tag when they explicitly provide one, after checking that it does not already exist.
   - If the diff suggests more than a patch release, stop before tagging, tell the user why, and recommend a larger increment based on semantic versioning best practices.
   - Recommend a minor bump for substantial new user-facing features, new workflows, notable UI/product capability additions, or meaningful backwards-compatible API/CLI behavior.
   - Recommend a major bump for breaking changes, removed behavior, incompatible file/config formats, migration requirements, or support drops.
   - Refuse to reuse an existing local or remote tag unless the user explicitly asks to replace it.
3. Draft the annotated tag message:
   - Use only the commit range and diffs between the prior release and `HEAD`.
   - Summarize user-visible changes concisely.
   - Use Markdown headings such as `## Changes`, `## Fixes`, or `## Maintenance` only when useful.
   - Do not include install commands, checksums, build commit hashes, or asset metadata; CI appends those details.
   - When recommending a larger increment, include the proposed tag and the specific changes that justify it before asking the user whether to proceed with that tag.
4. Validate:
   - Run this repo's documented validation commands before tagging: `scripts/test.sh` and `scripts/build.sh`.
   - If validation fails, do not tag or push unless the user explicitly overrides.
5. Publish:
   - Write the final Markdown notes to a temporary file outside the repo.
   - Run `scripts/create-release.sh <tag> <notes-file>` from this skill directory.
   - This script validates the notes, verifies the tag does not already exist locally or remotely, creates an annotated tag, pushes it to `origin`, and prints the expected release workflow URL.
6. Report:
   - Tell the user the tag pushed and that the release workflow was triggered.
   - Include the GitHub Actions URL when available.

## Commands

Get release context:

```bash
scripts/release-context.sh
```

Create and push the release tag:

```bash
notes_file="$(mktemp)"
# Write final Markdown release notes into "$notes_file".
scripts/create-release.sh "$next_tag" "$notes_file"
```
