# Validation decision

## Decision

This repository does not adopt a mandatory markdown lint or external skill validator at this time.
The required local validation remains the bundled scanner regression test and the bundled private marker scan:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

Optional checks may still be run when locally available, including markdown lint, Gitleaks, Semgrep, or a Codex-style skill validator.
Reports must name only the checks that actually ran.

## Rationale

- The repository is intentionally zero-dependency and portable: `SKILL.md`, examples, a PowerShell scanner, and regression tests.
- Adding a mandatory markdown linter would introduce a new toolchain and false-positive maintenance for limited current value.
- Adding a mandatory skill validator is useful only when a stable local validator is present in the target environment.
- Adding either check to GitHub Actions would modify `.github/workflows/*`, which is a human gate under `AGENTS.md`.

## Revisit triggers

Reconsider mandatory markdown lint or skill validation when one of these becomes true:

- A release/tag or marketplace-style distribution is being prepared.
- A stable local skill validator is selected and documented.
- Markdown formatting churn starts hiding meaningful changes in review.
- CI policy changes are explicitly approved.

Until then, keep optional validation documented in `README.md`, and keep the required gate limited to the bundled PowerShell checks.