# Contributing to KAutomobileTracker

Thank you for helping improve KAutomobileTracker. This guide matches the **long-run engineering plan**: small PRs, tests where possible, and scoped changes.

## Before you code

1. Read the **Mission** and scope in the root [README.md](../README.md) (what the app is / is not).
2. For non-trivial features, open a **GitHub Issue** first: problem, proposed approach, test plan, and out-of-scope notes. Link the issue from your PR.

## Branching and pull requests

- Fork the repo (unless you are a maintainer with branch access).
- Name branches descriptively: `feature/…`, `fix/…`, `docs/…`.
- Keep PRs **small** and single-purpose when possible.
- PR description must include:
  - **What** changed
  - **Why**
  - **How to test** (`swift build`, `swift test`, and any manual dashcam / video steps)
  - **Screenshots** for UI changes

Do **not** commit secrets (passwords, API keys, signing identities), personal trip exports, or large binaries without maintainer agreement.

## Review expectations

- **Authors:** Address feedback; resolve threads when fixed; re-request review after meaningful updates.
- **Reviewers:** Be specific (file/line or pattern). Label **must-fix** vs **nit/suggestion**. Approve when the change builds, fits scope, and avoids obvious regressions.
- **Automation:** CI runs `swift build` and `swift test` on macOS 14 — keep the main branch green.

## Feature ideas

Use Issues with the **enhancement** label. Include a short user/job story and **acceptance criteria**. Vendor-specific dashcam work should reference [DASHCAM_VENDOR_NOTES.md](DASHCAM_VENDOR_NOTES.md).

## Local development

```bash
swift build
swift test
./build_app.sh   # optional unsigned .app for local use
```

Open **Package.swift** in Xcode for debugging UI with full entitlements (see [XCODE_SIGNING.md](XCODE_SIGNING.md)).

## Licensing

This repository is under the [Apache License 2.0](../LICENSE). By contributing, you agree your contributions are licensed under those same terms unless you state otherwise explicitly in the pull request.
