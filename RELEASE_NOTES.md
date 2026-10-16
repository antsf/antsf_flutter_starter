# Release notes

## Unreleased — Android-first flavor generator (CLI 0.1.0)

Prepared in [PR #6](https://github.com/antsf/antsf_flutter_starter/pull/6).
The runtime library stays at **0.2.1**, unchanged; the new **0.1.0 CLI** is a
separate in-repository tool, not an added runtime dependency or a pub.dev release.

### What's included

- New-app generation with native dev/prod flavors and optional stg, corekit,
  Riverpod/router codegen, MVVM scaffold, distinct package IDs and visual markers.
- Independent versions per flavor/platform, explicit flavor selection, transport
  and logging safety, managed-file conflict detection, and recoverable sync.
- Exact-byte Git attributes and tracked native baselines; normal Git checkout is
  covered by a regression rather than relying on force-added files.
- Android-first PR/main CI: real generation/tests and dev/stg/prod APK builds with
  assertions against the packaged identity, display name and version metadata.

### Install and use

Follow the [CLI README](packages/antsf_flutter_starter_cli/README.md) for path/Git
installation, prerequisites, create/sync/version/run/build commands and recovery.
Use an immutable reviewed commit for Git installation. Existing apps are not
migrated automatically; this generator creates new projects.

### Verification and release boundary

- Local: 60 CLI tests, 26 starter tests; generated-app codegen/analyzers and 16/17
  tests for two-/three-flavor apps; actual debug APKs for all flavors and dev release.
- Initial [PR workflow](https://github.com/antsf/antsf_flutter_starter/actions/runs/38845268853)
  passed CLI and Android, including real packaged metadata checks. Consult the
  PR's latest checks for any later documentation commits.
- **iOS is deferred and build-unverified**. Its macOS matrix requires explicit
  manual dispatch with `verify_ios: true`; CocoaPods regressions are not Xcode proof.
- No automatic merge, production deployment, signing setup, store upload, tag,
  GitHub Release or registry publication is included. The existing published
  GitHub Release is not replaced by these source notes.
- Detailed evidence: [verification report](docs/verification/flutter-flavor-generator-20261016.md).

## 0.2.1 — historical release preparation

Release preparation date: 2026-10-01. This patch prepares GitHub consumption for
new OMS/PH apps, without a local corekit checkout or dependency override.

## Included

- Single starter import supports actual generated Riverpod function providers,
  AsyncNotifiers and typed GoRouter routes.
- Configured public routes remain reachable during loading/error; protected
  routes still redirect and authenticated auth-only precedence is unchanged.
- Example router is disposed by its owning provider, separately from the refresh
  listenable. The example exercises login, home, logout and unmount/disposal.
- Dart minimum adjusted to 3.13.1, package/example version bumped to 0.2.1 and
  corekit pinned to reviewed Git commit
  `8995c06884e7ac4ae004db3b357f6da5c642f96d` (flutter_corekit 3.1.1).

## Install for a new app

```yaml
dependencies:
  flutter:
    sdk: flutter
  antsf_flutter_starter:
    git:
      url: git@github.com:antsf/antsf_flutter_starter.git
      ref: fix/independent-review-20260930

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.16.1
  riverpod_generator: ^4.0.9
  go_router_builder: ^4.1.1
```

Pin the full starter commit SHA from the PR for immutable application builds,
and commit your app's `pubspec.lock`. Run `flutter pub get`,
`dart run build_runner build`, `flutter analyze` and `flutter test` in your app.
The single barrel import re-exports corekit; a direct corekit import additionally
requires its own declared dependency with this exact Git URL and commit.

The original preparation assumed private repository access; the repository was
verified public on 2026-10-16. Git/SSH access must still work when using SSH URLs.
Never embed credentials in dependency URLs. The app owns
its generated providers/router/auth/route files; reuse the example pattern, not
an assumption that the package generates a full project automatically.

## Verification

The source checkpoint passed 26 package tests and 1 actual example smoke test,
code generation, package/example analyzers, formatting and whitespace checks.
Independent source/generated-part review passed without findings. Native/device
plugin checks are not claimed; notifications and save_to_dir remain deferred.

## Release boundary

This delivery is commit + branch push + PR to `main`, **without auto-merge**.
Version 0.2.1, changelog, README and release notes are prepared in source. No
`v0.2.1` tag, GitHub Release or pub.dev publication is created by opening the PR.
Use the tag only after approved merge and actual tag creation. Merge corekit's
companion PR first; the pinned commit remains the reviewed source meanwhile.
