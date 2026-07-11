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

## Skill Content Review (Attack Surface)

`SKILL.md` and `examples/` are high-trust instruction text that agents load and
follow. A malicious or careless change here can do more damage than ordinary
code, so changes to these files get extra review beyond the local checks:

- Review the full diff line by line. Do not approve skill-text changes from a
  summary alone.
- Check for hidden or invisible Unicode characters (zero-width spaces, bidi
  controls, byte order marks) that could smuggle instructions past a human
  reader. One local check, run inside `pwsh` from the repository root (the
  character class is written as escaped code points so this file stays free of
  the characters it hunts):

  ```powershell
  $p = '[\u200B-\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]'
  $hits = Get-ChildItem -Recurse -Include *.md -File | Select-String -Pattern $p
  if ($hits) { $hits | ForEach-Object { '{0}:{1}' -f $_.Path, $_.LineNumber } }
  else { 'No hidden unicode characters found.' }
  ```

- Reject remote-instruction patterns. The skill must never tell an agent to
  fetch an external URL and follow the instructions found there.
- Reject changes that nudge agents toward broader permissions, disabled
  approval gates, weaker redaction, or skipped verification.
- A change that flips an expected decision in
  `docs/adversarial-decision-matrix.md` is a product-requirement change and
  needs explicit owner approval before merge.
- The bundled marker scanner must stay green, but it does not detect hostile
  instruction text. The scanner is not a substitute for this review.

## Documentation Style

- Write for agents and reviewers who need a quick safety decision.
- Use direct language and concrete steps.
- Make unsafe examples synthetic and clearly labeled.
- Keep the skill compact enough to load into an agent workflow.
