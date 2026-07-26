# agentic-coding-security-gate

[![CI](https://github.com/h8nc4y/agentic-coding-security-gate/actions/workflows/ci.yml/badge.svg)](https://github.com/h8nc4y/agentic-coding-security-gate/actions/workflows/ci.yml)

A Codex-style skill for adding a security gate to agentic coding workflows before an agent publishes, transmits, stores, or executes sensitive or cost-bearing work.

## What It Solves

AI coding agents often move quickly across local files, Git, GitHub, browser tools, MCP tools, plugins, CLIs, cloud consoles, and public collaboration surfaces. That speed is useful, but it also creates a practical risk: secrets, private context, real data, logs, screenshots, or paid operations can cross a boundary before anyone notices.

This skill gives agents a compact gate for those moments. It focuses on workflow safety, public issue and PR hygiene, safe scan reporting, cost approval boundaries, and evidence-backed completion claims.

## Who It Is For

- Codex users and maintainers who publish skills, examples, docs, or issue summaries.
- Agent developers who run GitHub, browser, MCP, plugin, CLI, cloud, or API tools.
- Reviewers who need public-safe security summaries without leaking private material.
- Teams that want a reusable checklist for agentic coding safety.

## Prerequisites

- Git for cloning the repository.
- PowerShell 7+ (`pwsh`) for the bundled marker scan and tests.
- A Codex-style skills directory such as `~/.agents/skills` for manual installation.

PowerShell 7+ is the supported validation runtime. Windows PowerShell 5.1
(`powershell.exe`) may run simple repository commands, but it is not the
documented compatibility target; the CI workflow and regression test harness use
`pwsh`.

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

## Repository Layout

```text
SKILL.md                         Skill instructions loaded by an agent.
examples/                        Synthetic examples and templates.
scripts/scan-private-markers.ps1 Local public-safety marker scan.
scripts/private-marker-process.ps1 Bounded native-process and Git transport.
tests/                           Dependency-free scanner regression tests.
.github/workflows/ci.yml         Pull request and main-branch quality gate.
```

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
- [MCP and cloud boundary safe summary](examples/mcp-cloud-boundary-summary.md)
- [Browser screenshot and log safe summary](examples/browser-screenshot-log-summary.md)
- [Cost approval blocker safe summary](examples/cost-approval-blocker-summary.md)
- [Release and tag gate safe summary](examples/release-tag-gate-summary.md)
- [GitHub Actions artifact boundary safe summary](examples/github-actions-artifact-boundary-summary.md)

The examples are synthetic. Do not replace placeholders with real secrets, raw logs, private repository names, customer data, screenshots, or local machine paths.

For the expected gate decision (`stop`, `redact`, `synthetic`, or `not-checked`) across synthetic boundary scenarios, see the [adversarial decision matrix](docs/adversarial-decision-matrix.md). It is a static reference of intended judgments, not a claim of measured agent behavior.

## Safety Notes

- Do not print credential values.
- Do not ask users to paste tokens or OAuth output into public issues or chats.
- Do not use real production data in examples.
- Do not claim that a scan, validation, or security review passed unless that check actually ran.
- Treat each environment's active cost, secret, OAuth, and data-handling policy as authoritative.

## Validation And Scan

Confirm that `pwsh` is available:

```powershell
pwsh --version
```

Run the dependency-free scanner tests from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\scan-private-markers.Tests.ps1
```

Run the bundled marker scan:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\scan-private-markers.ps1
```

The default `auto` mode uses the exact Git index plus regular worktree
snapshots when the root is a repository. This detects staged-only and
worktree-only markers without following symlinks or reparse points. Worktree
reads retain a no-follow file identity, change version, and content hash, then
revalidate all three
immediately before reporting so an intermediate same-length replacement and
restore cannot be accepted as the original snapshot. Use
`-ScanMode tracked` to require that Git boundary, or `-ScanMode worktree` for
an explicit non-Git fixture scan. Ambiguous repository state, malformed UTF-8,
budget exhaustion, or process-boundary failure exits with code 2 and a fixed
redacted integrity diagnostic.

Text-file selection includes case-insensitive `.pem` containers so the existing
private-key marker rule also reaches standard PEM files. Unrelated binary
extensions remain skipped.

If your environment has a Codex-style skill validator, run it against the repository root:

```bash
python path/to/quick_validate.py .
```

Optional local checks can include Gitleaks, Semgrep, markdown linting, or a manual review. Report only the checks that actually ran. If a check is unavailable, say it was not checked. Markdown lint and external skill validators remain optional by policy; see `docs/REQUIREMENTS.md` (Japanese) for the validation policy and its revisit triggers.

The dependency-free test entrypoint also runs process-containment, binary Git
transport, index/worktree provenance, path-boundary, one-budget operation
deadline, and atomic output regressions. The operation deadline includes child
setup, launch, POSIX readiness, execution, drain, and cleanup. Native children
start from an explicit environment allowlist. On POSIX, both external and
native `setsid` paths use the same readiness-verified live anchor, and cleanup
signals a process group only while that anchor still owns it. Isolation
directories are removed through a bounded manifest of known artifacts rather
than recursive traversal. Pull requests run the same bundled scanner tests and
marker scan in GitHub Actions.

## Contributing And Security

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening issues or pull requests.
- Read [SECURITY.md](SECURITY.md) before reporting security-sensitive behavior.
- Keep public reports synthetic and redact protected values.
- Do not claim a validation passed unless the exact command ran successfully.

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
