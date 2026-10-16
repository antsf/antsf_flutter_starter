import 'dart:convert';
import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/synchronizer.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('antsf_sync_test_');
    File('${root.path}/antsf_flavors.json').writeAsStringSync('{}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'records source asset hashes without owning or overwriting source assets',
    () {
      final sync = Synchronizer(root);
      File('${root.path}/source.png').writeAsBytesSync([1, 2, 3]);
      sync.apply(
        {
          'icon.png': [4, 5],
        },
        initialize: true,
        inputs: {
          'source.png': [1, 2, 3],
        },
      );
      final state = jsonDecode(
        File('${root.path}/.antsf/managed.json').readAsStringSync(),
      );
      expect(state['inputs']['source.png'], digest([1, 2, 3]));
      expect(state['files'].containsKey('source.png'), isFalse);
    },
  );

  test('initial sync records hashes and a repeated sync is idempotent', () {
    final sync = Synchronizer(root);
    final output = {
      'lib/core/config/flavors.g.dart': utf8.encode('generated\n'),
    };
    sync.apply(output, initialize: true);
    final manifest = File('${root.path}/.antsf/managed.json')
        .readAsStringSync();
    sync.apply(output);
    expect(
      File('${root.path}/.antsf/managed.json').readAsStringSync(),
      manifest,
    );
  });

  test('manual conflict prevents ALL writes and preserves feature code', () {
    final sync = Synchronizer(root);
    sync.apply({
      'a.txt': utf8.encode('A'),
      'b.txt': utf8.encode('B'),
    }, initialize: true);
    File('${root.path}/a.txt').writeAsStringSync('manual');
    File('${root.path}/feature.dart').writeAsStringSync('handwritten');
    expect(
      () => sync.apply({
        'a.txt': utf8.encode('new A'),
        'b.txt': utf8.encode('new B'),
      }),
      throwsStateError,
    );
    expect(File('${root.path}/b.txt').readAsStringSync(), 'B');
    expect(File('${root.path}/feature.dart').readAsStringSync(), 'handwritten');
  });

  test('failed writes restore old config, outputs and manifest', () {
    final sync = Synchronizer(root);
    sync.apply({'a.txt': utf8.encode('old')}, initialize: true);
    final manifest = File('${root.path}/.antsf/managed.json')
        .readAsStringSync();
    expect(
      () => sync.apply(
        {'a.txt': utf8.encode('new')},
        updatedConfig: '{"new":true}\n',
        afterWrite: (_) => throw StateError('injected failure'),
      ),
      throwsStateError,
    );
    expect(File('${root.path}/a.txt').readAsStringSync(), 'old');
    expect(File('${root.path}/antsf_flavors.json').readAsStringSync(), '{}\n');
    expect(
      File('${root.path}/.antsf/managed.json').readAsStringSync(),
      manifest,
    );
    expect(File('${root.path}/.antsf/transaction.json').existsSync(), isFalse);
  });

  test('rejects path traversal and unowned file collisions before writes', () {
    final sync = Synchronizer(root);
    expect(
      () => sync.apply({
        '../escape.txt': [1],
      }, initialize: true),
      throwsFormatException,
    );
    sync.apply({
      'owned.txt': [1],
    }, initialize: true);
    File('${root.path}/other.txt').writeAsStringSync('handwritten');
    expect(
      () => sync.apply({
        'owned.txt': [2],
        'other.txt': [3],
      }),
      throwsStateError,
    );
    expect(File('${root.path}/owned.txt').readAsBytesSync(), [1]);
  });

  test('stale configuration race is rejected without changing output', () {
    final sync = Synchronizer(root);
    sync.apply({
      'a.txt': [1],
    }, initialize: true);
    File('${root.path}/antsf_flavors.json')
        .writeAsStringSync('{"changed":true}');
    expect(
      () => sync.apply({
        'a.txt': [2],
      }, expectedConfig: '{}\n'),
      throwsStateError,
    );
    expect(File('${root.path}/a.txt').readAsBytesSync(), [1]);
  });
}
