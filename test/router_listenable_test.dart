import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';

/// A tiny state notifier standing in for a real auth viewmodel, so these
/// tests exercise [RouterListenableRef.listenAsRefreshListenable] against
/// an actual Riverpod provider graph instead of mocking [Ref].
@immutable
class _FakeAuthState {
  const _FakeAuthState({this.token});
  final String? token;

  bool get isAuthenticated => token != null;
}

class _FakeAuthNotifier extends AsyncNotifier<_FakeAuthState> {
  @override
  Future<_FakeAuthState> build() async => const _FakeAuthState();

  void login(String token) {
    state = AsyncData(_FakeAuthState(token: token));
  }

  void fail() {
    state = AsyncError('boom', StackTrace.current);
  }
}

final _fakeAuthProvider =
    AsyncNotifierProvider<_FakeAuthNotifier, _FakeAuthState>(
      _FakeAuthNotifier.new,
    );

/// Exposes the bridge as a provider so a [ProviderContainer] can build and
/// dispose it like a real app would (mirrors the `@riverpod GoRouter
/// appRouter(Ref ref)` usage shown in the README).
final _listenableProvider = Provider<AsyncValueListenable<_FakeAuthState>>((
  ref,
) {
  return ref.listenAsRefreshListenable(_fakeAuthProvider);
});

void main() {
  group('GateStatusFromAsync.fromAsync', () {
    test('loading -> GateStatus.loading', () {
      expect(
        GateStatusFromAsync.fromAsync<int>(const AsyncLoading()),
        GateStatus.loading,
      );
    });

    test('error -> GateStatus.error', () {
      expect(
        GateStatusFromAsync.fromAsync<int>(
          AsyncError<int>('boom', StackTrace.current),
        ),
        GateStatus.error,
      );
    });

    test('data -> GateStatus.satisfied', () {
      expect(
        GateStatusFromAsync.fromAsync<int>(const AsyncData(1)),
        GateStatus.satisfied,
      );
    });
  });

  group('RouterListenableRef.listenAsRefreshListenable', () {
    test('starts at AsyncLoading before the source provider settles', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final listenable = container.read(_listenableProvider);
      expect(listenable.value, isA<AsyncLoading<_FakeAuthState>>());
    });

    test('mirrors the source provider once it resolves', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final listenable = container.read(_listenableProvider);
      // AsyncNotifier.build() resolves asynchronously (a microtask), even
      // though this fake's body is synchronous — pump once.
      await Future<void>.delayed(Duration.zero);

      expect(listenable.value.value, const _FakeAuthState());
    });

    test('fires notifyListeners exactly once per distinct auth change', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final listenable = container.read(_listenableProvider);
      await Future<void>.delayed(Duration.zero);

      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      container.read(_fakeAuthProvider.notifier).login('token-1');
      await Future<void>.delayed(Duration.zero);

      expect(notifyCount, 1);
      expect(listenable.value.value?.isAuthenticated, isTrue);
      expect(listenable.value.value?.token, 'token-1');
    });

    test('propagates provider errors as AsyncError', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final listenable = container.read(_listenableProvider);
      await Future<void>.delayed(Duration.zero);

      container.read(_fakeAuthProvider.notifier).fail();
      await Future<void>.delayed(Duration.zero);

      expect(listenable.value.hasError, isTrue);
    });

    test('disposes the notifier when the container is disposed', () async {
      final container = ProviderContainer();
      final listenable = container.read(_listenableProvider);
      await Future<void>.delayed(Duration.zero);

      container.dispose();

      // A disposed ChangeNotifier/ValueNotifier throws on further listener
      // mutation — this is the standard way to assert dispose() ran.
      expect(() => listenable.addListener(() {}), throwsFlutterError);
    });
  });

  group('mergeRouterListenables', () {
    test('notifies when any merged listenable notifies', () {
      final a = ValueNotifier<int>(0);
      final b = ValueNotifier<int>(0);
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final merged = mergeRouterListenables([a, b]);
      var notifyCount = 0;
      merged.addListener(() => notifyCount++);

      a.value = 1;
      b.value = 1;

      expect(notifyCount, 2);
    });
  });
}
