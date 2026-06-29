# Release readiness brief

Status: draft for owner approval. This file is not an approval record, tag, GitHub Release, marketplace publication, package publication, or distribution action.

## Purpose

Prepare the first public release decision for `agentic-coding-security-gate` without performing any publication step.

No local or remote Git tags are present as of the 2026/06/29 Codex check, and `gh release list --limit 20` returned no releases. The owner must therefore confirm whether the first release should use `v0.1.0`, `v0.2.0`, or another version before any tag or GitHub Release is created.

## Current Candidate Scope

The current `main` tip includes these public-safe changes beyond the initial skill skeleton:

- Private-marker scanner hardening for additional cloud, Slack, Stripe, bearer, PEM, Anthropic, JWT-shaped, and npm `_authToken` assignment patterns.
- Redacted scanner regression tests for the covered marker shapes.
- Git-tracked scan mode to reduce local scratch false positives.
- Optional validation decision documentation for markdown lint and external skill validators.
- Synthetic public-safe examples for MCP/cloud boundaries and browser screenshot / console / network log boundaries.
- Handoff and backlog updates that keep real secrets, raw logs, local absolute paths, private repo names, and screenshots out of committed docs.

## Version Decision

Owner confirmation required before release:

- Confirm the release version and tag name: `未確認`.
- Confirm the exact target commit after this preparation branch is merged or rejected: `未確認`.
- Confirm whether the release notes draft should include all current `Unreleased` entries or a smaller subset: `未確認`.
- Confirm publication timing: `未確認`.

## Required Verification Before Tagging

Run from the repository root immediately before any approved release/tag action:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
git diff --check
gitleaks detect --source . --redact --no-banner
```

Also confirm the GitHub `Quality gate` workflow is green for the final target commit.

## Human Approval Checklist

Do not tag or create a GitHub Release until all items are explicitly approved:

- Owner confirms the release version and tag name.
- Owner confirms the exact target commit.
- Owner confirms publication timing.
- Owner approves the final release notes text.
- Owner confirms that no marketplace, package registry, installer, paid service, cloud resource, OAuth, token, or secret-handling operation is bundled into this release.

## Publication Commands After Approval Only

These commands are examples for the approved release moment; do not run them as part of this preparation task.

```powershell
git fetch origin --prune --tags
git switch main
git pull --ff-only origin main
git tag -a <approved-version> -m "<approved-version>"
git push origin <approved-version>
gh release create <approved-version> --title "<approved-version>" --notes-file docs\release-notes-draft.md
```

If the approved target commit differs from the checked-out `main`, tag the explicitly approved commit instead of relying on implicit `HEAD`.

## Out Of Scope

- Creating or pushing a tag.
- Creating, drafting, or publishing a GitHub Release.
- Adding or changing GitHub Actions workflows.
- Publishing a marketplace entry, package, installer, or plugin bundle.
- Running OAuth/token entry, credential repair, cloud, paid API, or paid model operations.
- Collecting real customer data, raw credential logs, screenshots, cookies, private repository names, or local absolute paths for release notes.