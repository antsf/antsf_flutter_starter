# antsf_flutter_starter

Opinionated app-starter building blocks for antsf Flutter projects —
specifically the pieces that `flutter_corekit` deliberately does NOT own:
navigation guards and Riverpod wiring for `go_router`.

## Why a separate package (not inside `flutter_corekit`)

`flutter_corekit` is a state-management-agnostic toolkit (network, storage,
theme, extensions). Adding `go_router`/Riverpod as hard dependencies there
would turn it into an opinionated framework and force that choice on every
consumer, even ones that don't want it. This package sits one layer up:
depends on `flutter_corekit`, adds the "how we build an app" opinions
(auth-gated routing, Riverpod-driven `refreshListenable`), and is meant to
be pulled in — or copied as a starting point — per new project, not treated
as an unconditional dependency of every Flutter app.

## What's in here

- `RouteGate` / `SimpleRouteGate` / `AuthRouteGate` / `CompositeRouteGuard`
  (`lib/src/router/route_guard.dart`) — a pure, framework-agnostic redirect
  chain. No `go_router` or Riverpod import; takes/returns plain path
  strings, so it's unit-testable without a running app.
- `RouterListenableRef.watchAsListenable` / `AsyncValueListenable`
  (`lib/src/router/router_listenable.dart`) — the one Riverpod-aware file:
  turns a watched `AsyncValue` provider into a `Listenable` for
  `GoRouter.refreshListenable`.
- `RouterErrorScreen` (`lib/src/router/router_error_screen.dart`) — generic
  "route not found" screen for `GoRouter.errorBuilder`.

Generalized from `draiv_logistik_supplier`'s `core/router/draiv_router.dart`
(private `_handleRedirect` + `_ErrorScreen`), made app-agnostic (plain
booleans instead of a hardcoded `AuthState` type, configurable paths
instead of hardcoded route names).

## Usage

```dart
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final authListenable = ref.watchAsListenable(authViewmodelProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authListenable,
    redirect: (context, state) => CompositeRouteGuard([
      AuthRouteGate(
        status: GateStatusFromAsync.fromAsync(authListenable.value),
        isAuthenticated: authListenable.value.value?.isAuthenticated ?? false,
        loginPath: '/login',
        homePath: '/home',
        splashPath: '/splash',
        authOnlyRoutes: const {'/splash', '/login'},
      ),
    ]).call(state.uri.path),
    routes: $appRoutes,
    errorBuilder: (context, state) => RouterErrorScreen(
      error: state.error,
      canPop: context.canPop(),
      onPop: () => context.pop(),
      onGoHome: () => context.go('/home'),
    ),
  );
}
```

Multiple gates compose in order (first non-null redirect wins) — e.g. an
onboarding gate before the auth gate:

```dart
CompositeRouteGuard([
  SimpleRouteGate(
    status: GateStatusFromAsync.fromAsync(onboardingListenable.value),
    satisfied: onboardingListenable.value.value ?? false,
    redirectPathWhenUnsatisfied: '/onboarding',
    allowedWhileUnsatisfied: {'/onboarding'},
  ),
  AuthRouteGate(/* ... */),
]).call(state.uri.path)
```

## Status

Early extraction (v0.1.0) — router guard + Riverpod listenable wiring only.
Not published to pub.dev; consumed via git/path dependency per app repo.
Future candidates for this package (not yet built): a Riverpod-wired
`SecureStorage`/`DioClient` provider bundle, a shared onboarding-state
provider shape.
