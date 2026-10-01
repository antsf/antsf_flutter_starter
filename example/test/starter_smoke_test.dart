import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/app_router.dart';
import 'package:example/main.dart';

void main() {
  testWidgets(
    'generated single-import app logs in/out and disposes its router',
    (tester) async {
      await tester.pumpWidget(const ProviderScope(child: ExampleApp()));
      await tester.pumpAndSettle();
      expect(find.text('Login as demo'), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExampleApp)),
        listen: false,
      );
      final router = container.read(appRouterProvider);

      await tester.tap(find.text('Login as demo'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(find.text('Login as demo'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(
        () => ChangeNotifier.debugAssertNotDisposed(
          router.routeInformationProvider,
        ),
        throwsAssertionError,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
