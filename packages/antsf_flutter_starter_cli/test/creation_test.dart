import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/creation.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('antsf_create_test_'));
  tearDown(() => root.deleteSync(recursive: true));
  test(
    'non-empty destination is rejected before invoking population',
    () async {
      final dest = Directory(p.join(root.path, 'app'))..createSync();
      final existing = File(p.join(dest.path, 'existing.dart'))
        ..writeAsStringSync('untouched');
      var called = false;
      await expectLater(
        createInDestination(dest, (_) async {
          called = true;
        }),
        throwsStateError,
      );
      expect(called, isFalse);
      expect(existing.readAsStringSync(), 'untouched');
    },
  );
  test(
    'failure does not publish a partial project or delete pre-existing files',
    () async {
      final dest = Directory(p.join(root.path, 'app'))..createSync();
      await expectLater(
        createInDestination(dest, (staging) async {
          staging.createSync();
          File(p.join(staging.path, 'partial')).writeAsStringSync('partial');
          throw StateError('subprocess failed');
        }),
        throwsStateError,
      );
      expect(dest.existsSync(), isTrue);
      expect(dest.listSync(), isEmpty);
      expect(root.listSync().map((e) => p.basename(e.path)), ['app']);
    },
  );
  test(
    'publishes completed output only, preserving destination changes on a race',
    () async {
      final dest = Directory(p.join(root.path, 'app'));
      await createInDestination(dest, (staging) async {
        staging.createSync();
        File(p.join(staging.path, 'ready')).writeAsStringSync('ready');
      });
      expect(File(p.join(dest.path, 'ready')).readAsStringSync(), 'ready');
      final raced = Directory(p.join(root.path, 'raced'));
      await expectLater(
        createInDestination(raced, (staging) async {
          staging.createSync();
          raced.createSync();
          File(p.join(raced.path, 'external')).writeAsStringSync('external');
        }),
        throwsStateError,
      );
      expect(
        File(p.join(raced.path, 'external')).readAsStringSync(),
        'external',
      );
    },
  );
}
