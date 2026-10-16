import 'dart:convert';
import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:antsf_flutter_starter_cli/src/flutter_tool.dart';
import 'package:antsf_flutter_starter_cli/src/generator.dart';
import 'package:antsf_flutter_starter_cli/src/synchronizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('all guarded bytes survive a normal Git add and checkout', () async {
    final root = Directory.systemTemp.createTempSync('antsf_git_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final app = Directory(p.join(root.path, 'app'));
    await ProjectGenerator(FlutterTool.discover()).create(
      app,
      ProjectConfig.create(
        name: 'git_sample',
        organization: 'com.example',
        displayName: 'Git Sample',
        apiUrls: {
          'dev': 'https://dev.example.net',
          'prod': 'https://api.example.net',
        },
      ),
      setup: false,
    );
    ProcessResult git(List<String> args) => Process.runSync(
      'git',
      args,
      workingDirectory: app.path,
      environment: {
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': Platform.isWindows ? 'NUL' : '/dev/null',
      },
    );
    for (final args in [
      ['init'],
      ['config', 'core.autocrlf', 'true'],
      ['add', '.'],
    ]) {
      final result = git(args);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final manifest = jsonDecode(
      File(p.join(app.path, '.antsf/managed.json')).readAsStringSync(),
    ) as Map<String, dynamic>;
    final tracked = <String, dynamic>{
      ...manifest['files'] as Map,
      ...manifest['inputs'] as Map,
    };
    final staged = (git(['ls-files', '-z']).stdout as String)
        .split('\u0000')
        .toSet();
    expect(
      tracked.keys.where((path) => !staged.contains(path)),
      isEmpty,
      reason: 'Every guard input and output must be tracked without force-add.',
    );
    final restored = Directory(p.join(root.path, 'restored'))..createSync();
    final checkout = git([
      'checkout-index',
      '--all',
      '--prefix=${restored.path.replaceAll('\\', '/')}/',
    ]);
    expect(checkout.exitCode, 0, reason: '${checkout.stderr}');
    for (final entry in tracked.entries) {
      final file = File(p.join(restored.path, entry.key));
      expect(file.existsSync(), isTrue, reason: entry.key);
      expect(
        digest(file.readAsBytesSync()),
        entry.value,
        reason: 'Git line ending conversion changed ${entry.key}',
      );
    }
    expect(
      File(p.join(restored.path, 'antsf_flavors.json')).readAsBytesSync(),
      File(p.join(app.path, 'antsf_flavors.json')).readAsBytesSync(),
    );
    final guard = Process.runSync(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool/package_config.json')}',
      'tool/flavor_guard.dart',
      '--flavor=dev',
      '--platform=android',
    ], workingDirectory: restored.path);
    expect(guard.exitCode, 0, reason: '${guard.stdout}\n${guard.stderr}');
  });
}
