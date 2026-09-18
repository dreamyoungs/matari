## What changed

Describe the user-visible problem and the chosen approach.

## Verification

- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
- [ ] `./scripts/build-release.sh`
- [ ] `codesign --verify --deep --strict --verbose=2 .build/ReleaseDerivedData/Build/Products/Release/MATARI.app`
- [ ] `git diff --check`

Add focused manual checks or sanitized screenshots where relevant.

## Security and privacy

- [ ] No real session JSONL, prompts, responses, tool payloads, credentials, identifiers, usernames, or private paths are included.
- [ ] Parser, persistence, logging, folder-access, login-item, or Codex-boundary changes are explained below.
- [ ] New network calls, telemetry, uploads, external processes, or permissions are documented.

Security/privacy impact:

## Deferred work

List intentionally deferred follow-ups or write `None`.
