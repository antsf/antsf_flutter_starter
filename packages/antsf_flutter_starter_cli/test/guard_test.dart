import 'dart:convert';
import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:antsf_flutter_starter_cli/src/guard.dart';
import 'package:antsf_flutter_starter_cli/src/synchronizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  final packages = p.absolute('.dart_tool/package_config.json');
  setUp(() {
    root = Directory.systemTemp.createTempSync('antsf_guard_test_');
    final config = ProjectConfig.create(
      name: 'sample',
      organization: 'com.example',
      displayName: 'Sample',
      apiUrls: {
        'dev': 'https://dev.example.net',
        'prod': 'https://api.example.net',
      },
    );
    config.flavors['dev']['android']['versionName'] = '1.0.4';
    config.flavors['dev']['android']['versionCode'] = 51;
    config.flavors['dev']['ios']['versionName'] = '2.3.4';
    config.flavors['dev']['ios']['buildNumber'] = '8';
    File(p.join(root.path, 'antsf_flavors.json'))
        .writeAsStringSync(config.encode());
    Synchronizer(root).apply({
      'tool/flavor_guard.dart': utf8.encode(renderGuard()),
      'owned.txt': utf8.encode('managed'),
    }, initialize: true);
  });
  tearDown(() => root.deleteSync(recursive: true));
  ProcessResult run(List<String> arguments) => Process.runSync(
    Platform.resolvedExecutable,
    ['--packages=$packages', 'tool/flavor_guard.dart', ...arguments],
    workingDirectory: root.path,
  );

  test(
    'allows native-owned versions and Flutter baseline without mutation',
    () {
      final before = File(p.join(root.path, 'antsf_flavors.json'))
          .readAsStringSync();
      expect(
        run([
          '--flavor=dev',
          '--platform=android',
          '--build-name=1.0.4',
          '--build-number=51',
        ]).exitCode,
        0,
      );
      expect(
        run([
          '--flavor=dev',
          '--platform=ios',
          '--build-name=0.0.0',
          '--build-number=1',
        ]).exitCode,
        0,
      );
      expect(
        File(p.join(root.path, 'antsf_flavors.json')).readAsStringSync(),
        before,
      );
    },
  );
  test(
    'rejects absent/unknown flavor, conflicting versions or Dart selectors',
    () {
      for (final args in [
        ['--platform=android'],
        ['--flavor=unknown', '--platform=android'],
        ['--flavor=dev', '--platform=android', '--build-number=999'],
        ['--flavor=dev', '--platform=android', '--build-name=9.9.9'],
        [
          '--flavor=dev',
          '--platform=android',
          '--dart-defines=${base64Encode(utf8.encode('APP_ENV=prod'))}',
        ],
        ['--flavor=dev', '--platform=android', '--dart-defines=not-base64'],
      ]) {
        final result = run(args);
        expect(result.exitCode, 2, reason: '$args: ${result.stderr}');
      }
    },
  );
  test('rejects stale config, managed edits and interrupted sync', () {
    File(p.join(root.path, 'owned.txt')).writeAsStringSync('manual');
    expect(run(['--flavor=dev', '--platform=android']).exitCode, 2);
    File(p.join(root.path, 'owned.txt')).writeAsStringSync('managed');
    File(p.join(root.path, '.antsf/transaction.json')).writeAsStringSync('{}');
    expect(run(['--flavor=dev', '--platform=android']).exitCode, 2);
    File(p.join(root.path, '.antsf/transaction.json')).deleteSync();
    File(p.join(root.path, 'antsf_flavors.json')).writeAsStringSync('{}');
    expect(run(['--flavor=dev', '--platform=android']).exitCode, 2);
  });
}
