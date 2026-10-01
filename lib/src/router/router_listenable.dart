/// Riverpod-specific wiring for [CompositeRouteGuard]/[RouteGate]: bridges
/// a watched `AsyncValue` provider into a `Listenable` for
/// `GoRouter.refreshListenable`, since `GoRouter` doesn't know about
/// Riverpod providers directly.
///
/// This is the accepted community pattern for this problem (see the
/// long-running discussion at https://github.com/rrousselGit/riverpod/discussions/1357
/// — "strategy 3": a `ValueNotifier`/`ChangeNotifier` updated via
/// `ref.listen`, disposed via `ref.onDispose`). There's no dedicated
/// pub.dev package for it; every production codebase hand-rolls a small
/// bridge like this one.
///
/// This is the one file in the package that imports `flutter_riverpod` —
/// `route_guard.dart` stays framework-agnostic so it's unit-testable
/// without a `ProviderContainer`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'route_guard.dart';

/// Derives a [GateStatus] from an [AsyncValue]'s loading/error/data shape.
/// Callers still supply their own `satisfied`/`isAuthenticated` boolean
/// separately (e.g. from `value.value?.isAuthenticated`) — this only
/// reports whether the async operation itself has settled without error.
extension GateStatusFromAsync on GateStatus {
  static GateStatus fromAsync<T>(AsyncValue<T> value) {
    if (value.isLoading) return GateStatus.loading;
    if (value.hasError) return GateStatus.error;
    return GateStatus.satisfied;
  }
}

/// A `ValueNotifier<AsyncValue<T>>` kept in sync with a Riverpod provider,
/// for use as (one leg of) `GoRouter.refreshListenable`.
///
/// Construct via [RouterListenableRef.listenAsRefreshListenable] from
/// inside a `@riverpod` router provider function rather than directly —
/// that also wires up `ref.onDispose` and the `ref.listen` subscription.
/// [ValueNotifier] already no-ops [notifyListeners] when the new value
/// equals the old one (via `==`), so a settled `AsyncValue` that keeps
/// resolving to an equal value won't cause redundant `GoRouter` refreshes.
class AsyncValueListenable<T> extends ValueNotifier<AsyncValue<T>> {
  AsyncValueListenable(super.initial);
}

/// Wires a Riverpod provider into an [AsyncValueListenable] via
/// `ref.listen` (NOT `ref.watch` — this must not rebuild the router
/// provider itself on every auth-state change, only push updates into the
/// listenable so `GoRouter` re-runs its `redirect` callback).
///
/// ```dart
/// @riverpod
/// GoRouter appRouter(Ref ref) {
///   final authListenable = ref.listenAsRefreshListenable(authViewmodelProvider);
///   final router = GoRouter(
///     refreshListenable: authListenable,
///     redirect: (context, state) => CompositeRouteGuard([
///       AuthRouteGate(
///         status: GateStatusFromAsync.fromAsync(authListenable.value),
///         isAuthenticated: authListenable.value.value?.isAuthenticated ?? false,
///         loginPath: '/login',
///         homePath: '/home',
///         authOnlyRoutes: const {'/login', '/splash'},
///       ),
///     ]).call(state.uri.path),
///     routes: $appRoutes,
///   );
///   ref.onDispose(router.dispose);
///   return router;
/// }
/// ```
extension RouterListenableRef on Ref {
  AsyncValueListenable<T> listenAsRefreshListenable<T>(
    ProviderListenable<AsyncValue<T>> provider, {
    AsyncValue<T>? initial,
  }) {
    final notifier = AsyncValueListenable<T>(initial ?? const AsyncLoading());
    onDispose(notifier.dispose);
    listen<AsyncValue<T>>(
      provider,
      (_, next) => notifier.value = next,
      fireImmediately: true,
    );
    return notifier;
  }
}

/// Merges multiple [Listenable]s (e.g. several
/// [RouterListenableRef.listenAsRefreshListenable] results) into one, for
/// `GoRouter.refreshListenable`. Thin re-export of [Listenable.merge] so
/// callers don't need a separate `flutter/foundation` import just for this.
Listenable mergeRouterListenables(List<Listenable> listenables) =>
    Listenable.merge(listenables);
