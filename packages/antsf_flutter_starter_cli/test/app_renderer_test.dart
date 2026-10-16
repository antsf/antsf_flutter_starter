import 'dart:convert';
import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/renderers/app.dart';
import 'package:test/test.dart';

Map<String, dynamic> appConfig({bool staging = false, bool links = false}) => {
  'schemaVersion': 1,
  'project': {
    'name': 'sample_app',
    'organization': 'com.example',
    'applicationId': 'com.example.sample_app',
    'displayName': 'Sample',
    'starter': {'path': 'C:/src/flutter_dir/my_packages/antsf_flutter_starter'},
  },
  'icon': null,
  'flavors': {
    for (final flavor in ['dev', if (staging) 'stg', 'prod'])
      flavor: {
        'applicationIdSuffix': flavor == 'prod' ? '' : '.$flavor',
        'displayName': flavor == 'prod'
            ? 'Sample'
            : '[${flavor.toUpperCase()}] Sample',
        'apiBaseUrl': 'https://$flavor.example.net',
        'allowLocalHttp': false,
        'logMetadata': flavor != 'prod',
        'icon': null,
        'android': {
          'versionName': '1.0.0',
          'versionCode': 1,
          'versionNameSuffix': flavor == 'dev' ? '-b{build}' : '',
        },
        'ios': {'versionName': '1.0.0', 'buildNumber': '1'},
        'links': links
            ? {
                'host': '$flavor.example.net',
                'paths': ['/open'],
                'appleTeamId': null,
                'sha256CertFingerprints': <String>[],
              }
            : null,
      },
  },
};

void main() {
  late Directory project;
  setUp(() => project = Directory.systemTemp.createTempSync('app-renderer-'));
  tearDown(() => project.deleteSync(recursive: true));

  test(
    'renders native-authoritative config and runnable typed MVVM scaffold',
    () {
      final files = renderApp(appConfig(staging: true, links: true), project);
      expect(
        files.keys,
        containsAll([
          'lib/main.dart',
          'lib/app.dart',
          'lib/core/config/app_config.dart',
          'lib/core/di/providers.dart',
          'lib/core/network/metadata_interceptor.dart',
          'lib/core/router/routes.dart',
          'lib/features/home/viewmodels/home_view_model.dart',
          'lib/features/home/views/home_page.dart',
          'test/app_config_test.dart',
          'test/app_widget_test.dart',
          'test/metadata_interceptor_test.dart',
        ]),
      );
      expect(files['lib/main.dart'], contains('appFlavor'));
      expect(
        files['lib/main.dart'],
        contains("String.fromEnvironment('APP_ENV')"),
      );
      expect(
        files['lib/main.dart']!.indexOf('selectAppConfig('),
        lessThan(files['lib/main.dart']!.indexOf('runApp(')),
      );
      expect(
        files['lib/core/config/app_config.dart'],
        contains('https://stg.example.net'),
      );
      expect(
        files['lib/core/di/providers.dart'],
        contains('enableLogging: false'),
      );
      expect(
        files['lib/core/di/providers.dart'],
        contains('MetadataInterceptor'),
      );
      expect(
        files['lib/features/home/viewmodels/home_view_model.dart'],
        contains('@riverpod'),
      );
      expect(
        files['lib/core/router/routes.dart'],
        contains('@TypedGoRoute<HomeRoute>'),
      );
      expect(
        files['lib/core/router/routes.dart'],
        contains('config.allowsLink'),
      );
      expect(files['lib/core/config/app_config.dart'], contains('"/open"'));
      expect(files['lib/app.dart'], contains('AppTheme.defaultLightTheme'));
      expect(files['lib/app.dart'], contains('AppTheme.defaultDarkTheme'));
      expect(files['lib/app.dart'], contains('ScreenUtilWrapper'));
      expect(files['lib/app.dart'], isNot(contains('kDebugMode')));
      expect(files['test/app_widget_test.dart'], contains('testWidgets('));
      expect(
        files['test/metadata_interceptor_test.dart'],
        contains('HttpClientAdapter'),
      );
      expect(files['test/app_config_test.dart'], contains('throwsStateError'));
      expect(
        files['test/app_config_test.dart'],
        contains('package:sample_app/core/config/app_config.dart'),
      );
      expect(project.listSync(), isEmpty);
    },
  );

  test(
    'native project ownership uses CocoaPods and retains default icon fonts',
    () {
      final pubspec = renderApp(appConfig(), project)['pubspec.yaml']!;
      expect(
        pubspec,
        contains('  config:\n    enable-swift-package-manager: false'),
      );
      expect(pubspec, contains('  cupertino_icons: ^1.0.8'));
    },
  );

  test('does not add undeclared staging and safely quotes config', () {
    final config = appConfig();
    config['flavors']['dev']['displayName'] = r"[DEV] Anne's $app";
    final files = renderApp(config, project);
    expect(files['lib/core/config/app_config.dart'], contains(r"Anne's \$app"));
    expect(
      files['lib/core/config/app_config.dart'],
      isNot(contains('https://stg.example.net')),
    );
    expect(
      files['lib/core/config/app_config.dart'],
      contains('linkHost: null'),
    );
  });

  test(
    'sync changes only generated config, not handwritten routing or features',
    () {
      final original = renderApp(appConfig(), project);
      final changedConfig = appConfig(staging: true, links: true);
      changedConfig['flavors']['dev']['links']['host'] = 'changed.example.net';
      changedConfig['flavors']['dev']['links']['paths'] = ['/launch'];
      changedConfig['flavors']['dev']['apiBaseUrl'] = 'http://192.168.1.3:8080';
      changedConfig['flavors']['dev']['allowLocalHttp'] = true;
      final changed = renderApp(changedConfig, project);
      for (final entry in original.entries) {
        if (!entry.key.startsWith('lib/core/config/')) {
          expect(
            changed[entry.key],
            entry.value,
            reason: '${entry.key} is creation-only',
          );
        }
      }
      expect(
        changed['lib/core/config/app_config.dart'],
        contains('changed.example.net'),
      );
      expect(changed['lib/core/config/app_config.dart'], contains('"/launch"'));
    },
  );

  test('preserves supplied git starter pin', () {
    final config = appConfig();
    config['project']['starter'] = {
      'git': {'url': 'https://example.com/starter.git', 'ref': 'a' * 40},
    };
    expect(
      renderApp(config, project)['pubspec.yaml'],
      contains('"ref":"${'a' * 40}"'),
    );
  });

  test('renders dependency declarations with neutral native-owned version', () {
    final files = renderApp(appConfig(), project);
    final pubspec = files['pubspec.yaml']!;
    expect(pubspec, contains('name: sample_app'));
    expect(pubspec, contains('version: 0.0.0+1'));
    expect(
      pubspec,
      contains(
        'antsf_flutter_starter: ${jsonEncode(appConfig()['project']['starter'])}',
      ),
    );
    expect(pubspec, contains('crypto: ^3.0.6'));
    expect(pubspec, contains('riverpod_generator: ^4.0.9'));
    expect(pubspec, contains('go_router_builder: ^4.1.1'));
    expect(
      project.listSync(),
      isEmpty,
      reason: 'Rendering must never mutate the project',
    );
  });
}
