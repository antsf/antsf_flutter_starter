# Changelog

## 0.1.0 — 2026-09-10

Initial extraction, generalized from `draiv_logistik_supplier`'s private
`core/router/draiv_router.dart`.

### Added
- `RouteGate` / `SimpleRouteGate` / `AuthRouteGate` / `CompositeRouteGuard` —
  framework-agnostic auth/onboarding redirect-chain building blocks
  (`lib/src/router/route_guard.dart`).
- `RouterListenableRef.watchAsListenable`, `AsyncValueListenable`,
  `GateStatusFromAsync`, `mergeRouterListenables` — Riverpod wiring to feed
  `GoRouter.refreshListenable` (`lib/src/router/router_listenable.dart`).
- `RouterErrorScreen` — generic go_router `errorBuilder` screen
  (`lib/src/router/router_error_screen.dart`).
- 11 unit tests covering `RouteGate` implementations and
  `CompositeRouteGuard` composition.
