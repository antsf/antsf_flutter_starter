import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/cli.dart';
import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:antsf_flutter_starter_cli/src/flutter_tool.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FailingFlutterTool extends FlutterTool {
  _FailingFlutterTool() : super('unused');

  @override
  Future<int> dart(
    List<String> args,
    String directory, {
    bool inheritStdio = true,
  }) async => 0;

  @override
  Future<int> flutter(
    List<String> args,
    String directory, {
    bool inheritStdio = true,
  }) async {
    throw const ProcessException('flutter', [], 'fixture launch failure');
  }
}

void main() {
  test('run and build report asynchronous launch failures without escaping the CLI', () async {
    final root = Directory.systemTemp.createTempSync('antsf_cli_launch_');
    addTearDown(() => root.deleteSync(recursive: true));
    final config = ProjectConfig.create(
      name: 'sample',
      organization: 'com.example',
      displayName: 'Sample',
      apiUrls: {
        'dev': 'https://dev.example.net',
        'prod': 'https://api.example.net',
      },
    );
    File(p.join(root.path, 'antsf_flavors.json'))
        .writeAsStringSync(config.encode());
    for (final command in ['run', 'build']) {
      final error = StringBuffer();
      expect(
        await runCli(
          [
            command,
            '--project',
            root.path,
            '--flavor',
            'dev',
            '--platform',
            'android',
          ],
          error: error,
          flutterTool: _FailingFlutterTool(),
        ),
        2,
      );
      expect(error.toString(), contains('Could not launch'));
      expect(error.toString(), isNot(contains('fixture launch failure')));
    }
  });
  test('help works without mandatory creation flags', () async {
    final output = StringBuffer();
    expect(await runCli(['create', '--help'], output: output), 0);
    expect(output.toString(), contains('--dev-api'));
  });
  test(
    'run/build/version require explicit flavor and reject arbitrary overrides',
    () async {
      for (final args in [
        ['build', '--platform', 'android'],
        ['run'],
        ['version', '--platform', 'ios', '--name', '1.0.0', '--build', '2'],
        [
          'build',
          '--platform',
          'android',
          '--flavor',
          'dev',
          '--build-number',
          '99',
        ],
      ]) {
        expect(await runCli(args, error: StringBuffer()), 2);
      }
    },
  );
  test('validation reads actual source without discovering SDK or claiming build success', () async {
    final root = Directory.systemTemp.createTempSync('antsf_cli_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final config = ProjectConfig.create(
      name: 'sample',
      organization: 'com.example',
      displayName: 'Sample',
      apiUrls: {
        'dev': 'https://dev.example.net',
        'prod': 'https://api.example.net',
      },
    );
    File(p.join(root.path, 'antsf_flavors.json'))
        .writeAsStringSync(config.encode());
    final output = StringBuffer();
    expect(
      await runCli(['validate', '--project', root.path], output: output),
      0,
    );
    expect(
      output.toString(),
      contains('not build/signing/domain verification'),
    );
    config.flavors['prod']['apiBaseUrl'] = 'http://unsafe.example.net';
    File(p.join(root.path, 'antsf_flavors.json'))
        .writeAsStringSync(config.encode());
    expect(
      await runCli(['validate', '--project', root.path], error: StringBuffer()),
      2,
    );
  });
}
