import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/flutter_tool.dart';
import 'package:test/test.dart';

void main() {
  test('discovers the actual Flutter SDK without shell execution', () {
    final tool = FlutterTool.discover();
    expect(File(tool.dartExecutable).existsSync(), isTrue);
    expect(File(tool.flutterSnapshot).existsSync(), isTrue);
  });
  test('a failed subprocess reports the real exit code', () async {
    final tool = FlutterTool.discover();
    final result = await tool.dart(
      ['--this-is-not-a-real-dart-flag'],
      Directory.current.path,
      inheritStdio: false,
    );
    expect(result, isNot(0));
  });
}
