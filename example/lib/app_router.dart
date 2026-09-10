import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'auth_state.dart';
import 'routes.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(Ref ref) {
  final authListenable = ref.listenAsRefreshListenable(authProvider);

  return GoRouter(
    initialLocation: const SplashRoute().location,
    refreshListenable: authListenable,
    redirect: (context, state) => CompositeRouteGuard([
      AuthRouteGate(
        status: GateStatusFromAsync.fromAsync(authListenable.value),
        isAuthenticated: authListenable.value.value?.isAuthenticated ?? false,
        loginPath: const LoginRoute().location,
        homePath: const HomeRoute().location,
        splashPath: const SplashRoute().location,
        authOnlyRoutes: {
          const SplashRoute().location,
          const LoginRoute().location,
        },
      ),
    ]).call(state.uri.path),
    routes: $appRoutes,
    errorBuilder: (context, state) => RouterErrorScreen(
      error: state.error,
      canPop: context.canPop(),
      onPop: () => context.pop(),
      onGoHome: () => context.go(const HomeRoute().location),
    ),
  );
}
