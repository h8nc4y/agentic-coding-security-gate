# Security Checklist

Use this checklist before publishing agent-generated work or running a tool that crosses a local boundary.

## Boundary

- [ ] The destination is known: local-only, private external, public, destructive, credential-bearing, or cost-bearing.
- [ ] The action is necessary for the current task.
- [ ] A local or synthetic alternative was considered for risky operations.

## Protected Material

- [ ] No secrets, tokens, OAuth values, API keys, auth cookies, private keys, or credential-bearing logs are included.
- [ ] No customer data, production data, private screenshots, raw logs, or private repository names are included.
- [ ] No local absolute paths or machine-specific identifiers are included.
- [ ] Examples use synthetic names, synthetic IDs, and redacted values.

## Public Issue Or PR

- [ ] The summary is minimal and public-safe.
- [ ] Private context was replaced with neutral placeholders.
- [ ] Logs and screenshots were summarized instead of pasted.
- [ ] The reproduction contains only synthetic data.

## Tools And Cost

- [ ] The tool destination and data payload are understood.
- [ ] Destructive commands have explicit target checks.
- [ ] Credential entry and OAuth loops are avoided unless explicitly approved.
- [ ] Paid APIs, paid models, billing changes, and paid cloud operations are stopped for approval.

## Report

- [ ] Only scans that actually ran are reported as run.
- [ ] Unrun checks are marked as not checked.
- [ ] Findings redact values and include file, line, rule, and remediation only.
- [ ] Residual risk and blockers are stated plainly.
