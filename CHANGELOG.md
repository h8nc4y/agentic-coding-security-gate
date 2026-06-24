# Changelog

All notable changes to this project should be documented in this file.

This project follows a lightweight, human-readable changelog format. Add entries under `Unreleased` before cutting any release tag.

## Unreleased

- Hardened the private marker scanner to scan git-tracked text files and detect additional cloud, Slack, Stripe, bearer, and PEM secret markers without replaying values.
- Tightened the OpenAI key-prefix check so ordinary task filenames do not trigger false positives.
- Clarified that PowerShell 7+ (`pwsh`) is the supported local validation runtime.
- Added a GitHub Actions quality gate for scanner tests and private marker scanning.
- Added scanner regression tests that verify redacted findings and script-path coverage.
- Added contribution and security reporting guidance for public-safe OSS collaboration.

## 0.1.0

- Initial public skill, examples, README, license, and private marker scan script.
