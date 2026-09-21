# Changelog

## Unreleased

### Changed
- `antsf_flutter_starter.dart` now re-exports `flutter_corekit`, `go_router`,
  `flutter_riverpod`, and `riverpod_annotation` alongside the package's own
  router/Riverpod files, so consumers get every dependency this package
  actually uses — including the underlying flutter_corekit primitives —
  from a single import.

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
