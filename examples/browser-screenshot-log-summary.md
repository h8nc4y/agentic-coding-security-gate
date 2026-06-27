# Browser Screenshot And Log Safe Summary

Use this synthetic example when an agent needs to summarize browser, Chrome DevTools, Playwright, screenshot, console, or network-log work without exposing private page content.

## Situation

An agent inspected a web UI and captured local evidence for layout, console, and network behavior. The raw evidence may include signed-in page content, user-visible text, account metadata, local file names, cookies, request headers, or screenshots.

## Boundary Classification

- Destination: public issue, pull request, changelog, README, or release note.
- Data sent: synthetic page description, viewport sizes, check names, and pass/fail outcomes only.
- Protected material removed: raw screenshots, cookies, auth headers, full URLs with private query strings, account names, user-entered text, local machine paths, and full console or network logs.
- Cost risk: none when the check is local or unauthenticated; stop before paid browser services, external uploads, or production data export.

## Public-Safe Summary

The agent verified a synthetic browser workflow at desktop and mobile viewport sizes. The public report includes only the check category, the affected UI surface, and whether issues were found. Raw screenshots, console logs, request payloads, cookies, local paths, account identifiers, and production data were omitted.

## Evidence To Keep Local

| Evidence Type | Keep Local | Public Report |
| --- | --- | --- |
| Screenshot | Original image file and pixel-level inspection notes | "Desktop and mobile screenshots were reviewed." |
| Console log | Full log with stack traces and page-specific values | "No relevant console errors" or "one sanitized error class found." |
| Network log | Request URLs, headers, payloads, cookies, and response bodies | "No failed requests" or "one failed request class, details redacted." |
| DOM text | Signed-in names, user input, private labels, and account metadata | "Primary action label was visible" using generic labels. |

## Removed From This Report

- Raw screenshots or videos.
- Cookies, auth headers, session identifiers, local storage, or credential helper output.
- Full URLs containing private path segments, query strings, or account identifiers.
- Local machine paths and browser profile paths.
- User names, customer names, tenant names, account IDs, and production records.
- Full console, stack trace, or network dumps.

## Approval Blocker Pattern

Stop before publishing or uploading raw visual evidence when it may contain signed-in state, private page content, real user input, production records, or account metadata.

Recommended wording:

> Approval required: the next step would publish or upload raw browser evidence. A safe local alternative is to keep screenshots and logs in the protected workspace and share only a synthetic summary with protected values redacted.

## Completion Note Pattern

- Browser or UI check performed: `<checked viewport or flow>`.
- Raw screenshot or log published: no.
- Protected data observed: `<none observed / observed locally and redacted>`.
- External upload performed: no.
- Checks actually run: `<list exact commands or tools>`.
- Checks not run: `<state not checked>`.
