# Security Policy

## Supported Versions

The `main` branch is the supported development line.

## Reporting Security Issues

Do not include secrets, credential-bearing output, raw logs, private repository names, screenshots, customer data, or production identifiers in public issues or pull requests.

Preferred reporting path:

1. Use GitHub private vulnerability reporting for this repository if it is available.
2. If private reporting is unavailable, open a public issue with a minimal synthetic summary only.
3. State that sensitive details were removed and ask the maintainer for a private channel.

Safe public issue content may include:

- A short description of the affected behavior.
- Synthetic reproduction steps.
- The relative file path and rule name when a scanner finding is involved.
- Confirmation that protected values were redacted.

Unsafe public issue content includes credential values, raw authentication output, production logs, screenshots with private data, customer or tenant identifiers, and local absolute paths.

## Scanner Coverage

The local marker scanner (`scripts/scan-private-markers.ps1`) is best-effort. It detects a curated set of private markers and common secret prefixes (for example AWS, GCP, npm auth-token assignments, PyPI, RubyGems, GitLab token prefixes, Slack, Stripe, and PEM private-key headers) and always redacts matched values. Generic secret-assignment checks flag literal values on base or prefixed keys while allowing empty values and explicit runtime placeholders. The scanner does not guarantee detection of every secret format. By default it scans only git-tracked files, so a passing local scan reflects what would actually be published. Use it alongside, not instead of, dedicated secret scanners.

## Maintainer Handling

Maintainers should reproduce with synthetic fixtures when possible, avoid requesting protected values in public, and document which checks actually ran before closing a report.
