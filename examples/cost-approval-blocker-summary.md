# Cost Approval Blocker Safe Summary

Use this synthetic example when an agent reaches a step that may incur cost,
start a paid plan, consume paid API credits, or create billable cloud resources.
The point is to stop before the paid operation, keep protected values out of the
public report, and offer a local or mock alternative when possible.

## Situation

An agent has finished local validation for a feature and the next obvious step
would run a paid external operation, such as a hosted rendering job, a paid model
call, a production cloud deploy that may exceed free quota, or a billing-plan
change. The agent must not execute the operation without explicit approval.

## Boundary Classification

- Destination: paid external service, billing surface, or cloud control plane.
- Data that might be sent: prompt text, source files, media, logs, account
  metadata, production data, or deployment configuration.
- Protected material removed: tokens, OAuth material, customer data, production
  identifiers, full logs, screenshots, and local machine paths.
- Cost risk: unknown until current pricing, quota, and account state are checked.

## Public-Safe Stop Report

```markdown
Cost blocker:
- Blocked operation: run a paid hosted render for the synthetic preview scene.
- Why it is needed: local checks can verify file shape, but they cannot prove the hosted renderer output.
- Local/mock alternative: run the renderer adapter against a synthetic fixture and save a local placeholder artifact.
- Estimated cost: 未確認. Current pricing and remaining free quota were not checked in this run.
- Pricing source: 未確認. No external pricing page was opened.
- Approval wording: Please approve one paid hosted render using synthetic input only, with no secrets, OAuth material, customer data, production data, or private media.
- Safest next command after approval: <bounded command with explicit dry-run disabled and output path under an ignored local folder>
```

## If Pricing Was Checked

When a trusted current source was actually checked, include only the minimum
necessary facts:

```markdown
Estimated cost:
- Source checked: official pricing page, checked on YYYY-MM-DD.
- Assumption: one synthetic render, default quality, no storage retention.
- Estimate: <amount> JPY, using <exchange-rate source or 未確認>.
- Caveat: account-specific discounts, quota, taxes, and overage rules were not verified.
```

Do not guess prices. If the estimate is not backed by a current source, write
`未確認` and stop.

## Removed From This Report

- Account IDs, tenant IDs, project IDs, invoice details, and billing dashboard
  screenshots.
- Tokens, OAuth output, cookies, credentials, or API keys.
- Real customer data, production logs, private media, or non-synthetic prompts.
- Full local command output that may contain machine paths or account metadata.

## Completion Note Pattern

- Paid operation performed: no.
- External service contacted: no, unless the pricing/status page was explicitly
  checked and safe to report.
- Protected data sent externally: no.
- Local alternative completed: `<command or not checked>`.
- Approval still required for: `<operation class>`.

## Integrity Rules

- Stop before paid execution, not after a small paid test.
- Do not convert a pricing assumption into a verified estimate.
- Do not use real customer data, private media, production logs, or secrets to
  make a paid-operation approval request more convincing.
- Prefer a local mock, dry-run, fixture, or adapter test when it answers the
  development question without spend.
- After approval, run the narrowest bounded operation that matches the approved
  wording and record the exact evidence actually produced.