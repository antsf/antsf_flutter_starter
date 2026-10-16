# Changelog

## 0.1.0 — 2026-10-16 (bundled with source release v0.2.1)

Initial source delivery in [PR #6](https://github.com/antsf/antsf_flutter_starter/pull/6),
available through repository tag `v0.2.1`.
This CLI is separate from the unchanged `antsf_flutter_starter` runtime 0.2.1.

### Added
- New-app generation: dev/prod and optional stg, native identities, corekit,
  Riverpod/typed-router codegen, MVVM scaffold and non-production visual markers.
- Validated non-secret configuration, independent flavor/platform versions,
  explicit run/build flavor selection and safe transport/logging defaults.
- Managed-file hashes, idempotent synchronization, handwritten-code preservation,
  conflict refusal, transactional rollback and interrupted-operation recovery.
- Tracked native baseline inputs and exact-byte Git attributes, with an actual
  Git add/checkout regression covering `core.autocrlf=true`.
- Optional HTTPS link configuration/templates and launcher-icon overrides.
- Android-first CI: actual dev/stg/prod APKs and packaged metadata checks.

### Verification and limits
- 60 CLI tests passed with the real Android-template test enabled; generated apps
  passed codegen/analyzers and 16/17 tests for two-/three-flavor fixtures.
- Android debug APKs for all flavors and dev release built locally; initial PR CI
  passed CLI and Android. Refer to the PR checks for the latest commit's status.
- iOS scaffolding and CocoaPods ownership/recovery tests are included, but actual
  iOS builds are unverified and its CI matrix is manual opt-in only.
- No existing-app migration, production signing, live domain verification,
  automatic app deployment or registry publication is included. Install this
  package from the repository's `v0.2.1` source tag, not a pub.dev version.

See [usage](README.md), [repository release notes](../../RELEASE_NOTES.md), and
[verification evidence](../../docs/verification/flutter-flavor-generator-20261016.md).
