/// Building blocks for wiring an authentication/onboarding-aware
/// go_router redirect chain. Deliberately framework-agnostic at this
/// layer (pure functions over plain strings/booleans/enums, no go_router
/// or Riverpod import) — callers pass `state.uri.path` in from their own
/// `GoRouter.redirect` callback. The Riverpod wiring lives in
/// `router_listenable.dart`.
library;

/// Where a gate currently stands. Mirrors the shape of Riverpod's
/// `AsyncValue` (loading/error/data) without depending on it, so this file
/// has no Riverpod import.
enum GateStatus { loading, error, satisfied, unsatisfied }

/// A single step in a redirect chain — e.g. "has the user finished
/// onboarding?" or "is the user authenticated?". Each gate looks at the
/// current route path and its own [status] and either returns a path to
/// redirect to, or `null` to let the next gate (or the route itself)
/// decide.
///
/// Implementations should be cheap/pure — [evaluate] runs on every
/// navigation and every listened state change.
abstract class RouteGate {
  const RouteGate();

  /// Returns a redirect path, or `null` to pass through to the next gate.
  /// [currentPath] is typically `GoRouterState.uri.path` from the call
  /// site's `redirect` callback.
  String? evaluate(String currentPath);
}

/// Generic gate: while [status] is loading, allow only [waitingPath] (and
/// paths in [allowedWhileUnsatisfied]); otherwise, if unsatisfied, force
/// [redirectPathWhenUnsatisfied] unless the current path is already in
/// [allowedWhileUnsatisfied].
///
/// This is intentionally generic (not auth-specific) so it also covers
/// gates like "onboarding completed" or "terms accepted" — see
/// [AuthRouteGate] for the auth-specific convenience wrapper.
class SimpleRouteGate extends RouteGate {
  const SimpleRouteGate({
    required this.status,
    required this.satisfied,
    required this.redirectPathWhenUnsatisfied,
    this.waitingPath,
    this.allowedWhileUnsatisfied = const {},
    this.redirectPathWhenLoadingBlocksRoute,
  });

  /// Current [GateStatus]. Pass [GateStatus.loading]/[GateStatus.error]
  /// explicitly rather than collapsing them into satisfied/unsatisfied —
  /// callers usually want different UX for "still checking" vs "checked,
  /// and no".
  final GateStatus status;

  /// Whether the gate's condition holds, once [status] is settled
  /// (`satisfied` or `unsatisfied` — ignored while `loading`/`error`).
  final bool satisfied;

  /// Redirect target when [satisfied] is false.
  final String redirectPathWhenUnsatisfied;

  /// Path allowed to stay on while [status] is [GateStatus.loading] (e.g. a
  /// splash screen). If the current route isn't this path and isn't in
  /// [allowedWhileUnsatisfied], loading redirects to
  /// [redirectPathWhenLoadingBlocksRoute] (falls back to
  /// [redirectPathWhenUnsatisfied] if unset).
  final String? waitingPath;

  /// Paths that stay reachable even while unsatisfied (e.g. login/register
  /// pages during an auth gate).
  final Set<String> allowedWhileUnsatisfied;

  final String? redirectPathWhenLoadingBlocksRoute;

  @override
  String? evaluate(String currentPath) {
    if (status == GateStatus.loading) {
      if (waitingPath != null && currentPath == waitingPath) return null;
      if (allowedWhileUnsatisfied.contains(currentPath)) return null;
      return redirectPathWhenLoadingBlocksRoute ?? redirectPathWhenUnsatisfied;
    }

    if (status == GateStatus.error) {
      if (allowedWhileUnsatisfied.contains(currentPath)) return null;
      return redirectPathWhenUnsatisfied;
    }

    if (!satisfied) {
      if (allowedWhileUnsatisfied.contains(currentPath)) return null;
      return redirectPathWhenUnsatisfied;
    }

    return null;
  }
}

/// Convenience gate for the common "logged in?" case: redirects
/// unauthenticated users away from protected routes to [loginPath], and
/// redirects already-authenticated users away from [authOnlyRoutes]
/// (login/register/splash) to [homePath].
///
/// This mirrors `draiv_logistik_supplier`'s `_handleRedirect` auth case,
/// generalized to take plain booleans instead of an app-specific
/// `AuthState`.
class AuthRouteGate extends RouteGate {
  const AuthRouteGate({
    required this.status,
    required this.isAuthenticated,
    required this.loginPath,
    required this.homePath,
    this.publicRoutes = const {},
    this.authOnlyRoutes = const {},
    this.splashPath,
  });

  final GateStatus status;
  final bool isAuthenticated;
  final String loginPath;
  final String homePath;

  /// Routes reachable regardless of auth state (e.g. login, register).
  final Set<String> publicRoutes;

  /// Routes only meaningful while NOT authenticated (splash, login,
  /// register, onboarding) — an authenticated user gets bounced to
  /// [homePath] if they land here.
  final Set<String> authOnlyRoutes;

  /// Path to allow while [status] is [GateStatus.loading] (e.g. splash).
  final String? splashPath;

  @override
  String? evaluate(String currentPath) {
    final isAuthOnlyRoute = authOnlyRoutes.contains(currentPath);
    final isPublicRoute = publicRoutes.contains(currentPath);

    if (status == GateStatus.loading) {
      if (isAuthOnlyRoute) return null;
      return splashPath ?? loginPath;
    }

    if (status == GateStatus.error) {
      if (currentPath == loginPath) return null;
      return loginPath;
    }

    if (isAuthenticated) {
      if (isAuthOnlyRoute) return homePath;
      return null;
    }

    if (isPublicRoute) return null;
    return loginPath;
  }
}

/// Runs a list of [RouteGate]s in order and returns the first non-null
/// redirect. Wire this up in `GoRouter.redirect` as:
/// `(context, state) => CompositeRouteGuard([...]).call(state.uri.path)`
/// (rebuild the gate list per call so gates reflect current state — they
/// carry snapshots, not live references).
class CompositeRouteGuard {
  const CompositeRouteGuard(this.gates);

  final List<RouteGate> gates;

  String? call(String currentPath) {
    for (final gate in gates) {
      final redirect = gate.evaluate(currentPath);
      if (redirect != null) return redirect;
    }
    return null;
  }
}
