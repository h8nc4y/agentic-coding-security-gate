# Release notes draft

Status: draft. Review and approve before using this text in a GitHub Release. Version, target commit, and publication timing are `未確認` until the owner approves them.

## Summary

`agentic-coding-security-gate` provides a reusable safety gate for AI coding agents before they publish, transmit, store, or execute sensitive or cost-bearing work. This draft release prepares the skill for public distribution while preserving the core boundaries: no secret replay, no real-data examples, no OAuth/token entry loops, no paid operation without approval, and no evidence claims without actual verification.

## Added

- Synthetic MCP/cloud boundary summary example for public-safe reporting of tool, plugin, cloud, cost, and secret boundaries.
- Synthetic browser screenshot and log boundary summary example for public-safe reporting of UI evidence without raw screenshots, console logs, network logs, or private identifiers.
- Optional validation decision document explaining why markdown lint and external skill validators remain optional unless a future policy change justifies making them mandatory.
- Scanner regression coverage for Anthropic key prefixes, compact JWT-shaped token values, and npm registry `_authToken` assignment patterns.

## Changed

- Private-marker scanner now uses git-tracked scan mode by default to avoid committing local scratch and advisory-only files into public safety decisions.
- Scanner coverage now includes additional cloud, Slack, Stripe, bearer-token, PEM, path-like private marker, Anthropic, JWT-shaped, and npm auth-token patterns while keeping findings redacted.
- README and examples better separate verified evidence, blocked checks, and unverified UI/browser claims.

## Security And Safety

- Scanner tests preserve redaction expectations so raw marker values are not replayed in findings.
- Public docs and examples remain synthetic and must not be replaced with real secrets, credential-bearing logs, screenshots, customer data, private repository names, or local machine paths.
- The skill remains a workflow safety gate; it does not replace incident response, organization policy, access review, or secret rotation.

## Validation Before Release

The final release commit should pass:

- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1`
- `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1`
- `git diff --check`
- `gitleaks detect --source . --redact --no-banner`
- GitHub Actions `Quality gate` workflow on the final target commit

## Known Limits

- No Git tag or GitHub Release exists yet as of the preparation check; the first release version is owner-approved `未確認`.
- Marketplace, package registry, installer, plugin bundle, and workflow automation are not included in this draft release.
- The scanner is best-effort and cannot prove historical repository content or external systems are clean.