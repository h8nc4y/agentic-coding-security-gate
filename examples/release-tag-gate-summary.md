# Release And Tag Gate Safe Summary

Use this synthetic example when an agent reaches a release, tag, or publication
step that is gated by project policy. The point is to stop before mutating the
public release surface, preserve the exact approval questions, and keep private
context out of the report.

## Situation

An agent has finished local validation and the next obvious step would create a
Git tag, push a tag, create or publish a GitHub Release, change a release
workflow, or publish a package or marketplace artifact. The agent must not run
the publication step until the owner approves the release version, target
commit, timing, and final release notes.

## Boundary Classification

- Destination: public Git hosting release surface, package registry, marketplace,
  or CI/release workflow.
- Data that might be published: release notes, commit identifiers, artifact
  names, build outputs, logs, screenshots, and repository metadata.
- Protected material removed: private repository names, local machine paths,
  raw logs, screenshots, tokens, OAuth material, customer data, and production
  identifiers.
- Cost risk: not expected for the synthetic tag/release example, but billing
  impact remains `未確認` for any package, marketplace, storage, or deployment
  destination that was not checked in the current run.

## Public-Safe Stop Report

```markdown
Release/tag gate:
- Blocked operation: create and push `<approved-version>`, then create a public release from the approved target commit.
- Why it is needed: local validation is complete, but publication changes the public release surface and must match the owner's version, target commit, timing, and final notes decision.
- Local/mock alternative: keep the release notes draft in the repository and run local validation against the candidate commit without creating a tag or release.
- Cost impact: no paid operation is expected for the tag/release action itself; any registry, marketplace, deployment, or storage cost is 未確認 unless checked from a current source.
- Approval wording: Please approve release `<approved-version>` for commit `<approved-commit>` using `docs/release-notes-draft.md`, with no marketplace publish, package publish, paid service, OAuth flow, token entry, production data, private screenshots, or release workflow change.
- Safest next commands after approval: run the bounded publication commands from the release readiness brief, replacing placeholders only with owner-approved values.
```

## Approval Checklist

- Owner-approved version and tag name: `未確認`.
- Owner-approved target commit: `未確認`.
- Owner-approved publication timing: `未確認`.
- Owner-approved release notes text: `未確認`.
- Explicit confirmation that no marketplace, package registry, installer,
  deployment, paid service, OAuth, token, secret-handling, or workflow-change
  operation is bundled into this release: `未確認`.

## Commands After Approval Only

Keep commands narrow, bounded, and tied to the approved values. Do not run this
block as a dry-run substitute; it is the real publication path after approval.

```powershell
git fetch origin --prune --tags
git switch main
git pull --ff-only origin main
git tag -a <approved-version> <approved-commit> -m "<approved-version>"
git push origin <approved-version>
gh release create <approved-version> --title "<approved-version>" --notes-file docs/release-notes-draft.md --target <approved-commit>
```

## Removed From This Report

- Private repository names and local machine paths.
- Raw CI logs, credential logs, browser screenshots, and console or network
  dumps.
- Tokens, OAuth output, cookies, credentials, API keys, or private keys.
- Real customer data, production identifiers, private media, and account
  metadata.

## Completion Note Pattern

- Release/tag operation performed: no.
- Public release surface mutated: no.
- Workflow changed: no.
- Package, marketplace, deployment, or paid operation performed: no.
- Protected data sent externally: no.
- Local validation completed: `<command or not checked>`.
- Approval still required for: release version, target commit, timing, final
  notes, and any additional publication destination.

## Integrity Rules

- Stop before creating the tag or release, not after a draft or test release.
- Do not infer approval from a release notes draft, changelog entry, or green CI.
- Do not publish release notes containing raw logs, private paths, screenshots,
  customer data, or credential-shaped output.
- Do not combine a release/tag approval with marketplace, package, deployment,
  workflow, OAuth, secret, or paid-service approval unless the owner explicitly
  approved each operation class.
- After approval, report only the exact commands that ran and the evidence that
  was actually observed.
