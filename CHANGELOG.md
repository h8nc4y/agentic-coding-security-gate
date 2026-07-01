# Changelog

All notable changes to this project should be documented in this file.

This project follows a lightweight, human-readable changelog format. Add entries under `Unreleased` before cutting any release tag.

## Unreleased

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
