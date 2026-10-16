# Changelog

## Unreleased — Android-first flavor generator

This delivery adds the separate `antsf_flutter_starter_cli` package at version
`0.1.0`. The runtime starter remains `0.2.1`: its API and dependency constraints
are unchanged. No tag, GitHub Release or registry publication is implied.

### Added
- Standalone Dart CLI for new corekit/Riverpod/router/MVVM apps with native
  dev/prod flavors and optional stg, distinct identities and non-prod markers.
- Independent per-flavor/platform version configuration, guarded run/build,
  conflict-safe managed synchronization and journaled recovery.
- Android PR/main CI that generates a real app, builds all three flavors and
  inspects packaged IDs, labels and versions. iOS verification is deferred and
  available only through manual dispatch with `verify_ios: true`.
- Git round-trip regression with `core.autocrlf=true`, baseline tracking and
  exact-byte attributes so guarded files survive an ordinary checkout.

### Verification and limits
- 60 CLI tests and 26 starter tests passed; real generated two-/three-flavor apps
  passed codegen, analyzers and 16/17 tests respectively.
- Actual Android dev/stg/prod debug APKs and a dev release APK built locally;
  PR #6's initial CLI/Android CI run passed, including packaged metadata checks.
- iOS remains configuration-checked / build-unverified. No production signing,
  physical-device UI QA, live domain verification or automatic deployment is claimed.
- See `RELEASE_NOTES.md`, the CLI's own `CHANGELOG.md`, and
  `docs/verification/flutter-flavor-generator-20261016.md` for usage and evidence.

## 0.2.1 — 2026-10-01

Patch release preparation for GitHub-based OMS/PH app bootstrapping. Version
source and notes are prepared in a PR; no tag or GitHub Release is implied.

### Fixed
- Restore generated function-provider and AsyncNotifier support through the
  single starter import by re-exporting annotation generator-support symbols.
- Keep configured public routes reachable during auth loading/error; protected
  routes still redirect to splash/login, and authenticated auth-only precedence
  remains unchanged.
- Register disposal of the example's owned `GoRouter`; document that the router
  owner must dispose it separately from its refresh listenable.

### Changed
- Lower package/example Dart minimum from `^3.13.2` to `^3.13.1`.
- Pin Git dependency `flutter_corekit` to reviewed commit
  `8995c06884e7ac4ae004db3b357f6da5c642f96d` (3.1.1), not mutable `main`.
- Bump the example to 0.2.1, regenerate its provider parts and Git dependency
  lockfile, and replace local-checkout setup with GitHub installation guidance.
- Add prepared release notes and a smoke test reusing the example's actual
  login/home/logout flow and router-disposal behavior.

### Verification
- 26 package tests and 1 example smoke test passed; actual code generation,
  package/example analyzers, formatter and whitespace checks passed.
- Independent final source/generated-part review passed without findings.
- No native/device or platform-plugin verification is claimed.
- See `RELEASE_NOTES.md` for dependency refs, private-repository access and
  release boundaries. Local dependency overrides are not shipped.

## 0.2.0 — 2026-09-21

### Changed
- `antsf_flutter_starter.dart` now re-exports `flutter_corekit`, `go_router`,
  `flutter_riverpod`, and `riverpod_annotation` alongside the package's own
  router/Riverpod files, so consumers get every dependency this package
  actually uses — including the underlying flutter_corekit primitives —
  from a single import.
- Bumped dependency constraints so the package can be consumed by apps on
  newer majors: `go_router` ^16.2.5 -> ^18.0.1, `flutter_riverpod` ^3.0.3 ->
  ^3.4.3, `riverpod_annotation` ^3.0.0 -> ^4.0.7, `build_runner` ^2.15.1 ->
  ^2.16.1, `riverpod_generator` ^3.0.0 -> ^4.0.9, `go_router_builder`
  unpinned to ^4.1.1.

## 0.1.0 — 2026-09-10

Initial extraction, generalized from `draiv_logistik_supplier`'s private
`core/router/draiv_router.dart`.

### Added
- `RouteGate` / `SimpleRouteGate` / `AuthRouteGate` / `CompositeRouteGuard` —
  framework-agnostic auth/onboarding redirect-chain building blocks
  (`lib/src/router/route_guard.dart`).
- `RouterListenableRef.listenAsRefreshListenable`, `AsyncValueListenable`,
  `GateStatusFromAsync`, `mergeRouterListenables` — Riverpod wiring to feed
  `GoRouter.refreshListenable` via `ref.listen()` (not `ref.watch()`, so it
  notifies without forcing a router rebuild)
  (`lib/src/router/router_listenable.dart`).
- `RouterErrorScreen` — generic go_router `errorBuilder` screen
  (`lib/src/router/router_error_screen.dart`).
- `example/` — a compiled, buildable Flutter app exercising the full
  README pattern (real `riverpod_generator` + `go_router_builder` codegen,
  `flutter analyze` clean, `flutter build apk --debug` succeeds).
- 24 unit/widget tests: `RouteGate` implementations and
  `CompositeRouteGuard` composition, the Riverpod `refreshListenable`
  bridge (`router_listenable_test.dart`), and `RouterErrorScreen`
  (`router_error_screen_test.dart`).

### Fixed (post-review, same day)
- Renamed `watchAsListenable` → `listenAsRefreshListenable`: the old name
  implied `ref.watch()` semantics (rebuild-on-change) when the
  implementation always used `ref.listen()` (notify-without-rebuild) —
  the distinction matters in Riverpod and the name was actively
  misleading.
- Fixed a broken doc comment on `GateStatusFromAsync` referencing a
  non-existent `[isSatisfied]` parameter.
