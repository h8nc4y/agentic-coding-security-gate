# GitHub Actions Artifact Boundary Safe Summary

Use this synthetic summary when an agent is about to inspect or download workflow artifacts, job logs, or CI reports and needs to decide what can be shared publicly.

## Boundary

- Surface: GitHub Actions workflow artifacts and job logs.
- Destination: public issue, pull request, or release-support comment.
- Risk: artifacts and logs can contain local paths, private repository names, generated reports, environment-derived values, and credential-looking strings.

## Safe Report Pattern

### Summary

A workflow run produced an artifact needed for debugging, but the raw artifact and full job log were not posted publicly. The report below only includes the workflow name, check conclusion, sanitized failure class, and the exact local checks that were re-run.

### What Was Checked

- Workflow: `<workflow-name>`
- Run: `<workflow-run-url>`
- Job: `<job-name>`
- Conclusion: `<success|failure|cancelled|timed_out>`
- Artifact names reviewed: `<artifact-name-1>`, `<artifact-name-2>`
- Public-safe failure class: `<for example: test assertion failure, dependency install failure, scanner finding, timeout>`

### What Was Not Shared

- Raw artifact files.
- Full job logs.
- Environment dumps.
- Paths from the runner or local machine.
- Repository names outside the public project.
- Secret-looking substrings, authorization headers, cookies, tokens, private keys, or credential file names.
- Customer, account, tenant, user, or production identifiers.

### Public-Safe Evidence

- Re-ran `<local-check-command>` with synthetic inputs: `<pass|fail>`.
- Re-ran `<scanner-command>` with redaction enabled: `<pass|fail>`.
- If a finding remained, reported only: file, line, rule, and remediation.
- If the artifact was not safe to quote, summarized it as: `<sanitized one-line finding>`.

### Recommendation

Do not attach workflow artifacts or paste full logs into a public thread. If maintainers need the artifact, share a regenerated synthetic reproduction or a redacted excerpt that removes protected material and preserves only the minimum debugging signal.

## Unsafe Pattern To Avoid

```text
Here is the full CI log and the downloaded artifact contents:
<raw log omitted>
<raw artifact omitted>
```

The unsafe pattern can leak protected data even when the original CI failure looks harmless.