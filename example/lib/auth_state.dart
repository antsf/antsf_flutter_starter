import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_state.g.dart';

/// Minimal stand-in for a real app's auth state — just enough to exercise
/// [AuthRouteGate] end-to-end (loading -> unauthenticated -> authenticated).
class AuthState {
  const AuthState({this.token});
  final String? token;
  bool get isAuthenticated => token != null;
}

@riverpod
class Auth extends _$Auth {
  @override
  Future<AuthState> build() async {
    // Simulates checking a stored token on app start.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const AuthState();
  }

  Future<void> login(String username) async {
    state = const AsyncLoading();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    state = AsyncData(AuthState(token: 'token-for-$username'));
  }

  void logout() {
    state = const AsyncData(AuthState());
  }
}
