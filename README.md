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
- `RouterListenableRef.listenAsRefreshListenable` / `AsyncValueListenable`
  (`lib/src/router/router_listenable.dart`) — the one Riverpod-aware file:
  turns a Riverpod `AsyncValue` provider into a `Listenable` for
  `GoRouter.refreshListenable`, via `ref.listen()` (not `ref.watch()` —
  the whole point is to notify without triggering a router *rebuild*).
- `RouterErrorScreen` (`lib/src/router/router_error_screen.dart`) — generic
  "route not found" screen for `GoRouter.errorBuilder`.

`antsf_flutter_starter.dart` also re-exports `flutter_corekit`, `go_router`,
`flutter_riverpod`, and `riverpod_annotation` — every package this library
actually depends on — so consuming apps can
`import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';` alone
and get the full stack (network/storage/theme via flutter_corekit, plus
routing and state management) used by the patterns below, without
separately importing each dependency.

Generalized from `draiv_logistik_supplier`'s `core/router/draiv_router.dart`
(private `_handleRedirect` + `_ErrorScreen`), made app-agnostic (plain
booleans instead of a hardcoded `AuthState` type, configurable paths
instead of hardcoded route names).

## Usage

The example below is a trimmed version of [`example/`](example/). Regenerate
its parts with `dart run build_runner build`, then run `flutter analyze`
and `flutter test`. Generated provider/notifier parts need only the starter
import: its annotation bridge deliberately includes generator-support symbols.

```dart
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final authListenable = ref.listenAsRefreshListenable(authViewmodelProvider);

  final router = GoRouter(
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
  ref.onDispose(router.dispose);
  return router;
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

Public routes such as `/privacy` and `/register` remain reachable while auth
is loading or has failed; protected routes still redirect to splash/login.
`authOnlyRoutes` continues to redirect authenticated users home, even when
the same route is also public. The router provider owns the `GoRouter` it
creates and must register its disposal; the listenable helper owns only its
notifier, not the router.

## Install from GitHub (OMS/PH app)

Requires Dart **3.13.1 or newer below 4.0.0** and a compatible Flutter SDK.
This repository is private: your local Git/SSH identity and CI must have access.
Do not place credentials in a pubspec or URL.

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

While the 0.2.1 PR is open, the branch above exposes its release-preparation
source. Pin the full starter commit SHA from the PR for reproducible apps and
commit the application's `pubspec.lock`. Use `v0.2.1` only after approved merge
and actual tag creation; a version bump alone does not create that ref.

Starter pins corekit **3.1.1** to Git commit
`8995c06884e7ac4ae004db3b357f6da5c642f96d`. You need no local package checkout,
path dependency or `dependency_overrides`. Import the starter barrel to use the
re-exported corekit APIs. If your app imports corekit directly, declare it as a
direct dependency with exactly the same Git URL and commit as this pubspec.

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

Copy the app-owned router/auth/route pattern from `example/` into your project;
the starter supplies building blocks, not a CLI that generates an entire app.
The generators belong in the consuming app's dev dependencies; they are not
inherited from the starter package.

## Status

**0.2.1 release preparation** — GitHub-pinned corekit dependency, generated
single-import providers/notifiers, public-route loading/error fixes and explicit
router ownership. The source checkpoint passed 26 package tests, 1 example
widget smoke test, actual code generation and clean package/example analyzers;
independent final review found no remaining blockers. Native/device plugin
verification is not claimed. See `CHANGELOG.md` and `RELEASE_NOTES.md`.

Not published to pub.dev. This delivery opens a PR without automatic merge,
version tag creation or GitHub Release publication.
Future candidates for this
package (not yet built): a Riverpod-wired `SecureStorage`/`DioClient`
provider bundle, a shared onboarding-state provider shape.
