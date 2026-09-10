import 'package:flutter_test/flutter_test.dart';
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';

void main() {
  group('AuthRouteGate', () {
    test('loading: allows the splash/auth-only route, blocks others', () {
      final gate = AuthRouteGate(
        status: GateStatus.loading,
        isAuthenticated: false,
        loginPath: '/login',
        homePath: '/home',
        authOnlyRoutes: const {'/splash', '/login'},
        splashPath: '/splash',
      );

      expect(gate.evaluate('/splash'), isNull);
      expect(gate.evaluate('/login'), isNull);
      expect(gate.evaluate('/orders'), '/splash');
    });

    test('loading without splashPath falls back to loginPath', () {
      final gate = AuthRouteGate(
        status: GateStatus.loading,
        isAuthenticated: false,
        loginPath: '/login',
        homePath: '/home',
      );

      expect(gate.evaluate('/orders'), '/login');
    });

    test('error: redirects to login unless already there', () {
      const gate = AuthRouteGate(
        status: GateStatus.error,
        isAuthenticated: false,
        loginPath: '/login',
        homePath: '/home',
      );

      expect(gate.evaluate('/login'), isNull);
      expect(gate.evaluate('/orders'), '/login');
    });

    test('authenticated: bounced away from auth-only routes to home', () {
      const gate = AuthRouteGate(
        status: GateStatus.satisfied,
        isAuthenticated: true,
        loginPath: '/login',
        homePath: '/home',
        authOnlyRoutes: {'/login', '/splash'},
      );

      expect(gate.evaluate('/login'), '/home');
      expect(gate.evaluate('/splash'), '/home');
      expect(gate.evaluate('/orders'), isNull);
    });

    test('unauthenticated: public routes pass, protected routes redirect', () {
      const gate = AuthRouteGate(
        status: GateStatus.satisfied,
        isAuthenticated: false,
        loginPath: '/login',
        homePath: '/home',
        publicRoutes: {'/login', '/register'},
      );

      expect(gate.evaluate('/login'), isNull);
      expect(gate.evaluate('/register'), isNull);
      expect(gate.evaluate('/orders'), '/login');
    });
  });

  group('SimpleRouteGate', () {
    test('unsatisfied redirects unless on an allowed path', () {
      const gate = SimpleRouteGate(
        status: GateStatus.satisfied,
        satisfied: false,
        redirectPathWhenUnsatisfied: '/onboarding',
        allowedWhileUnsatisfied: {'/onboarding'},
      );

      expect(gate.evaluate('/onboarding'), isNull);
      expect(gate.evaluate('/home'), '/onboarding');
    });

    test('satisfied passes through everywhere', () {
      const gate = SimpleRouteGate(
        status: GateStatus.satisfied,
        satisfied: true,
        redirectPathWhenUnsatisfied: '/onboarding',
      );

      expect(gate.evaluate('/anything'), isNull);
    });

    test('loading uses waitingPath, else redirectPathWhenLoadingBlocksRoute',
        () {
      const gate = SimpleRouteGate(
        status: GateStatus.loading,
        satisfied: false,
        redirectPathWhenUnsatisfied: '/onboarding',
        waitingPath: '/splash',
        redirectPathWhenLoadingBlocksRoute: '/splash',
      );

      expect(gate.evaluate('/splash'), isNull);
      expect(gate.evaluate('/home'), '/splash');
    });
  });

  group('CompositeRouteGuard', () {
    test('returns the first non-null redirect, in gate order', () {
      const onboardingGate = SimpleRouteGate(
        status: GateStatus.satisfied,
        satisfied: false,
        redirectPathWhenUnsatisfied: '/onboarding',
      );
      const authGate = AuthRouteGate(
        status: GateStatus.satisfied,
        isAuthenticated: false,
        loginPath: '/login',
        homePath: '/home',
      );

      const guard = CompositeRouteGuard([onboardingGate, authGate]);

      // Onboarding gate fires first regardless of auth gate's own verdict.
      expect(guard.call('/home'), '/onboarding');
    });

    test('falls through to null when every gate passes', () {
      const passthroughGate = SimpleRouteGate(
        status: GateStatus.satisfied,
        satisfied: true,
        redirectPathWhenUnsatisfied: '/onboarding',
      );
      const guard = CompositeRouteGuard([passthroughGate]);

      expect(guard.call('/home'), isNull);
    });
  });
}
