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

The local marker scanner (`scripts/scan-private-markers.ps1`) is best-effort. It detects a curated set of private markers and common secret prefixes (for example AWS, GCP, npm auth-token assignments, PyPI, RubyGems, GitLab token prefixes, Slack, Stripe, and PEM private-key headers) and always redacts matched values. Generic secret-assignment checks flag literal values on base or prefixed keys while allowing empty values and explicit runtime placeholders. Text-file selection includes `.env` and suffixed dotenv filenames, routes `.jsx` / `.tsx`, module-specific `.mjs` / `.cjs` / `.mts` / `.cts`, component-source `.vue` / `.svelte` / `.astro`, JSON Lines `.jsonl`, Terraform `.tf` / `.tfvars`, generic `.hcl` / `.conf`, Java `.properties`, SQL `.sql`, and Windows `.bat` / `.cmd` files through the existing rules. Batch-aware `SET` parsing distinguishes quoted values and command separators from `SET /P` prompts, and recognizes `%VAR%`, `!VAR!`, and positional runtime references. Unrelated binary extensions remain skipped.

The default scan takes bounded snapshots from both the Git index and regular worktree files, so staged-only and unstaged-only markers remain visible. Worktree content is opened without following links, bound to a stable file identity, change version, and SHA-256 content hash, and revalidated immediately before reporting. This rejects same-length replacement/restore and in-place modification/restore races as well as type or path drift.

Git runs through a hermetic, time- and output-bounded child-process boundary whose environment is built from an empty allowlist rather than inherited and filtered. POSIX execution uses a readiness-verified live session anchor for both external and native `setsid`; cleanup signals the process group only while the anchor still owns it. Isolation cleanup recognizes only a bounded manifest of expected runtime artifacts and does not recursively traverse unknown data. Unsafe index states, path/type drift, reparse points, invalid UTF-8, scan-budget exhaustion, and ambiguous `.git` ancestry fail closed with exit code 2. Finding reports are bounded, atomically emitted UTF-8 with redacted values, and do not include the absolute scan root on success.

The scanner does not guarantee detection of every secret format. Use it alongside, not instead of, dedicated secret scanners.

## Maintainer Handling

Maintainers should reproduce with synthetic fixtures when possible, avoid requesting protected values in public, and document which checks actually ran before closing a report.
