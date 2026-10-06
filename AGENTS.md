# AGENTS.md

<!-- moli-rules:start -->
## Moli rules (copied verbatim from MoliSpec; do not edit)

These rules apply to every Moli repository. The full standards live in the private repo `MoliDuo/MoliSpec` (`standards/`).

**Naming**
- Product name `MoliFoo` (repo, package, file and identifier names, no spaces). User-facing name is `Moli Foo` (one space): window titles, app name, UI text, README title, Release titles.

**Deploy and CI**
- Deploy only after CI passes. Merging to `main` deploys to production (server apps), so run the check entry (`npm run check` or the stack's equivalent) locally before opening the PR, and watch CI and the deploy after it merges.
- Keep the CI names fixed: workflows `ci` / `deploy` / `release` / `codeql`; jobs `check`, `gitleaks`, `build`, `integration`, `ci-gate`.
- Never delete or skip tests, or loosen lint rules, to make a check pass.

**Git**
- Conventional Commits (`feat(scope): subject`).
- Never push to `main` directly. Every change, however small, goes on a new branch and is merged through a PR with auto-merge on. Before starting, update local `main` (`git switch main && git pull`) and branch from it; if a push is rejected or the branch is behind, pull the latest `main` and merge or rebase it in.
- Never force-push `main`. Roll back with `git revert`.

**Secrets and private information**
- Never commit secrets, `.env` files, keys, or internal information (server addresses, hostnames, Tailscale addresses, personal emails). Use obviously fake values in tests and examples (`test-token`, `example.com`, `192.0.2.1`).
- Never print secret values in logs, chat, or commits. Never store secrets in the OS keychain. Runtime secrets live in the server `.env` (mode 600); build and release secrets live in GitHub organization secrets.
- Do not copy a shared (organization-level) secret into repository-level secrets unless the administrator has said so.

**Login, data, config**
- Sign-in is Authelia only. Do not build your own accounts, passwords or registration pages.
- Database and settings schemas only add; never delete or rename an existing field in one step. Migrations must keep the previous app version working.
- Clients are offline-first and the server is authoritative. Settings are read in the order defined in the config standard; do not invent a second source.
- Server apps expose `GET /healthz` returning `{"ok": true, "version": "<commit sha>"}`, run as non-root, take config from environment variables, and publish no host ports.

**Working with the user**
- Do only what was asked. Do not publish, delete, or change shared settings (GitHub org, server, DNS) without being asked.
- Reply to the user in Chinese, briefly.
<!-- moli-rules:end -->

## About this project

Moli Mac is a macOS 27 menu bar app. Its first module is the mouse module, a reimplementation of
Mac Mouse Fix: remapped side and middle buttons (click, hold, drag, scroll), smooth scrolling, and
trackpad gestures synthesised for a plain mouse. Dock previews, a window switcher and menu bar
management come later as further modules of the same app. Scope: `docs/MoliMac-确定范围.md`.
Design: `docs/architecture.md`.

## Run and test

- Code is built and tested on macOS 27 with Xcode 27 (Swift 6.2+). There is no Linux build.
- Check (same as CI): `Scripts/check.sh` — SwiftFormat lint, SwiftLint, build with warnings as
  errors, unit tests. `Scripts/check.sh --fix` applies the formatter and the autocorrectable lint fixes.
- Package locally: `Scripts/package-release.sh`, then `Scripts/verify-package.sh`. Run
  `Scripts/setup-dev-signing.sh` once per Mac: local builds are then signed with a fixed development
  certificate kept in `~/.moli-dev-signing` (a standalone keychain file, never the login keychain), so the
  Accessibility grant survives rebuilds. Without it builds are ad-hoc signed and lose the grant each time.
- Run: open `.build/MoliMac.app`. Quit Mac Mouse Fix first, or both apps act on every event.
- Logs: `log stream --predicate 'subsystem == "com.moliduo.mac"' --level debug`.
- Release: bump `VERSION`, commit `chore(release): vX.Y.Z`, tag `vX.Y.Z`, push the tag.
  `.github/workflows/release.yml` does the rest. `CFBundleVersion` is derived from `VERSION`.

## Layout

- `Sources/MoliMacCore`: pure logic with no AppKit — settings model and store, the click/hold/drag/scroll
  state machine, scroll curves and acceleration, per-app navigation rules. Every rule that decides what an
  input does lives here and is unit tested without a clock (timers are passed in as tokens).
- `Sources/MoliMacApp`: AppKit and SwiftUI — app shell, event taps, synthesised events, settings window.
- `Sources/MoliMac/main.swift`: entry point only.
- `Config/`: icons, design tokens, the Sparkle public key and the signing certificate fingerprint.

## Conventions

- Mac Mouse Fix's source is not copied. Event field numbers, timing thresholds and other facts about
  macOS are fine to reuse; write the code fresh.
- Private macOS APIs are loaded at runtime with `dlsym`, so a missing symbol degrades one feature
  instead of crashing at launch. List every private API in `docs/architecture.md`.
- Events the app posts carry the marker in `eventSourceUserData`; taps pass them through untouched.
- Settings are added, never renamed or removed (MoliSpec 009). Unknown fields in `settings.json`
  are kept on save.

## Do not touch

- `Config/SparklePublicKey.txt` and `Config/CodeSigningCertificate.txt`: changing either cuts installed
  apps off from updates or resets every user's Accessibility grant.
- The bundle identifier `com.moliduo.mac`.
