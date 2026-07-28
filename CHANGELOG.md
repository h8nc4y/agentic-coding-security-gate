# Changelog

All notable changes to this project should be documented in this file.

This project follows a lightweight, human-readable changelog format. Add entries under `Unreleased` before cutting any release tag.

## Unreleased

- Fixed text-file selection so case-insensitive `.jsx` and `.tsx` sources reach the same existing marker rules as `.js` and `.ts`, with redacted findings.

- Fixed text-file selection so case-insensitive `.key` containers reach the existing private-key marker rule while findings remain redacted.

- Fixed text-file selection so case-insensitive `.pem` containers reach the existing private-key marker rule while findings remain redacted.

- Hardened the private marker scanner with bounded hermetic Git execution, exact index plus worktree snapshots, staged-only detection, non-following path checks, a scan-wide deadline, fixed redacted bootstrap/process/cleanup integrity failures, and atomic UTF-8 reports.

- Made the scan-wide deadline cover Git child setup, Windows atomic launch, POSIX session readiness, execution, stream drain, and cleanup under one millisecond-accurate absolute budget; added linked-worktree, POSIX `.GIT`, public argument-redaction, and first-call AST regressions.

- Added cross-runtime boundary regressions for binary stdin/stdout/stderr and real `git cat-file --batch` transport, AST first-call enforcement across aliases/scopes/function and alias providers/classes/dynamic invocation, missing-helper redaction, Windows launch/Job-close/Dispose failure cleanup, process-tree timeout cleanup, `.git` ancestry shapes, dangling metadata, invalid UTF-8, and output budgets.

- Closed the final scanner-boundary review findings: child processes now start from an explicit environment allowlist, POSIX external and native `setsid` paths share a readiness-verified live anchor, worktree snapshots retain no-follow file identity, change version, and content hashes through final report validation, stale process-group identifiers are never signaled after owner exit, and isolation cleanup follows a bounded known-artifact manifest.

- Fixed text-file selection so `.env` and suffixed dotenv files such as `.env.example` and `.env.local` are scanned while unrelated binary extensions remain skipped.

- Fixed generic secret-assignment scanning to detect prefixed keys with literal values while allowing empty values and explicit runtime placeholders.

- Fixed the legacy `.Tests.ps1` harness to report one real Pester adapter test instead of a misleading zero-test pass, and aligned `CODEX_START_HERE.md` with the dependency-free validation commands.

- Added a project code of conduct plus public-safe bug, feature, and pull request templates with private-first reporting guidance.

- Consolidated project documentation: added `docs/REQUIREMENTS.md` as the single requirements source (absorbing the 2026-07 requirements review and the validation decision), compressed `HANDOFF.md` and `TASKS_BACKLOG.md` to current-state-only, and removed resolved historical docs that git history already preserves.

- Documented skill-content attack-surface review guidance in CONTRIBUTING.md: full-diff review, hidden-unicode check, and rejection of remote-instruction or gate-weakening changes.

- Added a static adversarial decision matrix that maps synthetic boundary scenarios to expected gate decisions without claiming measured agent enforcement.

- Broadened GitLab scanner coverage to the official token prefix family and the session cookie shape while keeping synthetic values redacted.

- Added scanner coverage for GitLab `glpat-`, Hugging Face `hf_`, Slack incoming webhook URL, and SendGrid `SG.` two-segment key shapes while keeping synthetic values redacted.

- Added scanner coverage for GitHub classic token prefixes (`ghp_`, `gho_`, `ghu_`, `ghs_`, and `ghr_`) while keeping synthetic values redacted.

- Added scanner coverage for RubyGems credentials assignments while keeping synthetic values redacted.

- Added scanner coverage for PyPI API token prefixes while keeping synthetic values redacted.

- Added a synthetic GitHub Actions artifact boundary summary example for public-safe CI evidence reports.

- Added a synthetic release and tag gate summary example for owner-approval stop reports.

- Added a synthetic cost approval blocker summary example for paid-operation stop reports.

- Added release readiness brief and release notes draft for the first owner-approved public release; no tag or GitHub Release is created by this change.

- Added scanner coverage for literal npm registry auth token assignments while allowing environment-variable placeholders.

- Added a synthetic browser screenshot and log boundary summary example for public-safe UI evidence reports.

- Added a synthetic MCP/cloud boundary summary example for public-safe tool and deployment reports.

- Added scanner coverage for Anthropic key prefixes and compact JWT-shaped token values while keeping findings redacted.

- Added docs/VALIDATION_DECISION.md to record that markdown lint and external skill validators remain optional unless a future release or CI policy change justifies adopting them.

- Hardened the private marker scanner to scan git-tracked text files and detect additional cloud, Slack, Stripe, bearer, and PEM secret markers without replaying values.
- Tightened the OpenAI key-prefix check so ordinary task filenames do not trigger false positives.
- Clarified that PowerShell 7+ (`pwsh`) is the supported local validation runtime.
- Added a GitHub Actions quality gate for scanner tests and private marker scanning.
- Added scanner regression tests that verify redacted findings and script-path coverage.
- Added contribution and security reporting guidance for public-safe OSS collaboration.

## 0.1.0

- Initial public skill, examples, README, license, and private marker scan script.
