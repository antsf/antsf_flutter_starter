/// Riverpod-specific wiring for [CompositeRouteGuard]/[RouteGate]: turns a
/// list of watched `AsyncValue` providers into a single `Listenable` for
/// `GoRouter.refreshListenable`, since `GoRouter` doesn't know about
/// Riverpod providers directly.
///
/// This is the one file in the package that imports `flutter_riverpod` —
/// `route_guard.dart` stays framework-agnostic so it's unit-testable
/// without a `ProviderContainer`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'route_guard.dart';

/// Converts an [AsyncValue] into a [GateStatus] + `satisfied` bool pair,
/// via [isSatisfied] applied to the data value once loaded.
///
/// Example: `GateStatus.fromAsync(authState, (s) => s.isAuthenticated)`.
extension GateStatusFromAsync on GateStatus {
  static GateStatus fromAsync<T>(AsyncValue<T> value) {
    if (value.isLoading) return GateStatus.loading;
    if (value.hasError) return GateStatus.error;
    return GateStatus.satisfied; // caller still applies its own `satisfied`
    // boolean separately (e.g. AuthRouteGate.isAuthenticated) — this only
    // reports whether the async operation itself settled without error.
  }
}

/// A `ValueNotifier<AsyncValue<T>>` kept in sync with a Riverpod provider
/// via `ref.listen`, for use as (one leg of) `GoRouter.refreshListenable`.
///
/// Call [RouterListenableRef.watchAsListenable] from inside a `@riverpod`
/// router provider function instead of constructing this directly — it
/// also wires up `ref.onDispose`.
class AsyncValueListenable<T> extends ValueNotifier<AsyncValue<T>> {
  AsyncValueListenable(super.initial);
}

/// Convenience for building a router's `refreshListenable` from one or more
/// Riverpod providers, inside a `@riverpod` function that has a `Ref`.
///
/// ```dart
/// @riverpod
/// GoRouter appRouter(Ref ref) {
///   final authListenable = ref.watchAsListenable(authViewmodelProvider);
///   return GoRouter(
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
/// }
/// ```
extension RouterListenableRef on Ref {
  AsyncValueListenable<T> watchAsListenable<T>(
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
/// [RouterListenableRef.watchAsListenable] results) into one, for
/// `GoRouter.refreshListenable`. Thin re-export of [Listenable.merge] so
/// callers don't need a separate `flutter/foundation` import just for this.
Listenable mergeRouterListenables(List<Listenable> listenables) =>
    Listenable.merge(listenables);
