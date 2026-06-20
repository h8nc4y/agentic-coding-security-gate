# Contributing

Thanks for improving `agentic-coding-security-gate`. Keep contributions small, public-safe, and evidence-backed.

## Local Checks

Use PowerShell 7+ (`pwsh`) for local validation. Windows PowerShell 5.1
(`powershell.exe`) is not the supported compatibility target for this
repository's quality gate.

Run these commands from the repository root before opening a pull request:

```powershell
pwsh --version
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

If a check fails, fix the finding instead of hiding it. Scanner output intentionally redacts values; do not replay protected values in issues, commits, or pull request comments.

## Pull Request Guidelines

- Keep examples synthetic and minimal.
- Avoid private repository names, local machine paths, raw logs, screenshots, customer data, OAuth values, tokens, private keys, and production identifiers.
- Update `README.md`, `SKILL.md`, examples, or tests when behavior or guidance changes.
- Report only checks that actually ran. Mark skipped checks as not checked.
- Prefer one coherent change per pull request.

## Documentation Style

- Write for agents and reviewers who need a quick safety decision.
- Use direct language and concrete steps.
- Make unsafe examples synthetic and clearly labeled.
- Keep the skill compact enough to load into an agent workflow.
