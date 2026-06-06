# agentic-coding-security-gate

A Codex-style skill for adding a security gate to agentic coding workflows before an agent publishes, transmits, stores, or executes sensitive or cost-bearing work.

## What It Solves

AI coding agents often move quickly across local files, Git, GitHub, browser tools, MCP tools, plugins, CLIs, cloud consoles, and public collaboration surfaces. That speed is useful, but it also creates a practical risk: secrets, private context, real data, logs, screenshots, or paid operations can cross a boundary before anyone notices.

This skill gives agents a compact gate for those moments. It focuses on workflow safety, public issue and PR hygiene, safe scan reporting, cost approval boundaries, and evidence-backed completion claims.

## Who It Is For

- Codex users and maintainers who publish skills, examples, docs, or issue summaries.
- Agent developers who run GitHub, browser, MCP, plugin, CLI, cloud, or API tools.
- Reviewers who need public-safe security summaries without leaking private material.
- Teams that want a reusable checklist for agentic coding safety.

## Install

Clone the repository:

```bash
git clone https://github.com/h8nc4y/agentic-coding-security-gate.git
cd agentic-coding-security-gate
```

Manual Codex-style skill install on shells with POSIX syntax:

```bash
dest="${HOME}/.agents/skills/agentic-coding-security-gate"
if [ -e "$dest" ]; then
  echo "Install target already exists: $dest"
  exit 1
fi
mkdir -p "$dest"
cp SKILL.md "$dest/SKILL.md"
```

Manual Codex-style skill install from PowerShell:

```powershell
$dest = Join-Path $HOME '.agents\skills\agentic-coding-security-gate'
if (Test-Path -LiteralPath $dest) {
  throw "Install target already exists: $dest"
}
New-Item -ItemType Directory -Path $dest | Out-Null
Copy-Item -LiteralPath .\SKILL.md -Destination (Join-Path $dest 'SKILL.md')
```

The overwrite guard is intentional. If a local skill already exists, review it before replacing it.

## Manual Use

Use the skill before an agent:

- Posts to a public issue, PR, discussion, README, changelog, or release note.
- Reports Gitleaks, Semgrep, dependency, or marker scan findings.
- Handles logs, screenshots, customer data, production data, OAuth, secrets, tokens, API keys, auth cookies, or private keys.
- Runs browser, MCP, plugin, CLI, GitHub, cloud, or API operations that can send data outside the local workspace.
- Performs destructive operations or cost-bearing actions.

Follow [SKILL.md](SKILL.md): classify the boundary, redact protected material, convert public-facing content to synthetic examples, stop before paid or credential-bearing operations, and report only evidence-backed results.

## Synthetic Examples

- [Security checklist](examples/security-checklist.md)
- [Public issue safe summary](examples/public-issue-safe-summary.md)
- [Final report template](examples/final-report-template.md)

The examples are synthetic. Do not replace placeholders with real secrets, raw logs, private repository names, customer data, screenshots, or local machine paths.

## Safety Notes

- Do not print credential values.
- Do not ask users to paste tokens or OAuth output into public issues or chats.
- Do not use real production data in examples.
- Do not claim that a scan, validation, or security review passed unless that check actually ran.
- Treat each environment's active cost, secret, OAuth, and data-handling policy as authoritative.

## Validation And Scan

Run the bundled marker scan from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

If your environment has a Codex-style skill validator, run it against the repository root:

```bash
python path/to/quick_validate.py .
```

Optional local checks can include Gitleaks, Semgrep, markdown linting, or a manual review. Report only the checks that actually ran. If a check is unavailable, say it was not checked.

## Limitations

- This skill is a workflow gate, not a legal, compliance, or incident-response program.
- It does not replace secret rotation, access review, audit logging, or organization-specific policy enforcement.
- It cannot prove that historical repository content or external systems are clean.
- It depends on the active agent honoring the current environment policy.

## Non-Goals

- No GitHub Release automation.
- No Marketplace packaging.
- No package publishing.
- No cloud account setup.
- No paid API or model execution.

## License

MIT. See [LICENSE](LICENSE).
