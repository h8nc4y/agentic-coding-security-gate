# Public Issue Safe Summary

## Public Title

Agent sandbox reports a credential-like failure while a keyring-capable path succeeds

## Public Summary

An agent command running in a restricted shell reported a generic credential failure. A separate proof command in a keyring-capable shell succeeded without printing credential values. This suggests the issue may be an agent sandbox access limitation rather than a broken account credential.

## Public-Safe Reproduction

1. Start from a synthetic repository fixture.
2. Run a non-secret status command inside the restricted agent shell.
3. Observe the generic credential error class.
4. Run a non-secret proof command in a keyring-capable shell.
5. Confirm whether the proof command succeeds without exposing credential values.

## Removed From This Report

- Private repository names.
- Local machine paths.
- Raw logs.
- Screenshots.
- Credential-bearing output.
- Customer or production data.

## Expected Maintainer Response

Maintainers should be able to discuss the sandbox boundary, credential helper behavior, and safe proof commands without needing private logs or secret values.
