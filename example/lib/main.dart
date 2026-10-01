import 'package:flutter/material.dart';
import 'package:antsf_flutter_starter/antsf_flutter_starter.dart';

import 'app_router.dart';

void main() {
  runApp(const ProviderScope(child: ExampleApp()));
}

class ExampleApp extends ConsumerWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'antsf_flutter_starter example',
      routerConfig: router,
    );
  }
}
