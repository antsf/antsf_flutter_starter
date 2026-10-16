import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';

void main() {
  group('RouterErrorScreen', () {
    testWidgets('shows the go-home button and calls onGoHome when tapped', (
      tester,
    ) async {
      var goHomeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RouterErrorScreen(
            error: Exception('route not found'),
            canPop: false,
            onGoHome: () => goHomeCalled = true,
          ),
        ),
      );

      expect(find.text('Halaman tidak ditemukan'), findsOneWidget);
      expect(find.text('Kembali ke Beranda'), findsOneWidget);
      expect(find.byIcon(Icons.home), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(goHomeCalled, isTrue);
    });

    testWidgets('shows pop button and calls onPop when canPop is true', (
      tester,
    ) async {
      var popCalled = false;
      var goHomeCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: RouterErrorScreen(
            error: Exception('route not found'),
            canPop: true,
            onPop: () => popCalled = true,
            onGoHome: () => goHomeCalled = true,
          ),
        ),
      );

      expect(find.text('Kembali'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(popCalled, isTrue);
      expect(goHomeCalled, isFalse);
    });

    testWidgets(
      'falls back to onGoHome when canPop is true but onPop is null',
      (tester) async {
        var goHomeCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: RouterErrorScreen(
              error: Exception('route not found'),
              canPop: true,
              onGoHome: () => goHomeCalled = true,
            ),
          ),
        );

        await tester.tap(find.byType(ElevatedButton));
        await tester.pump();

        expect(goHomeCalled, isTrue);
      },
    );

    testWidgets('shows a default message when error is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RouterErrorScreen(error: null, onGoHome: () {})),
      );

      expect(find.text('Terjadi kesalahan saat navigasi'), findsOneWidget);
    });

    testWidgets('renders custom title and homeButtonLabel', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RouterErrorScreen(
            error: null,
            onGoHome: () {},
            title: 'Halaman hilang',
            homeButtonLabel: 'Ke Dashboard',
          ),
        ),
      );

      expect(find.text('Halaman hilang'), findsOneWidget);
      expect(find.text('Ke Dashboard'), findsOneWidget);
    });
  });
}
