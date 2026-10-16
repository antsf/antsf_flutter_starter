import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

String digest(List<int> bytes) => sha256.convert(bytes).toString();

/// A journaled, conflict-detecting writer. Never owns handwritten feature files.
class Synchronizer {
  Synchronizer(this.root);
  final Directory root;

  File _file(String path) => File(p.joinAll([root.path, ...path.split('/')]));

  void _safe(String relative, {bool internal = false}) {
    if (relative.isEmpty ||
        relative.contains('\\') ||
        relative.contains(':') ||
        p.posix.isAbsolute(relative) ||
        p.posix.normalize(relative) != relative ||
        relative
            .split('/')
            .any((part) => part == '..' || part == '.' || part.isEmpty) ||
        relative == '.git' ||
        relative.startsWith('.git/') ||
        (!internal &&
            (relative.startsWith('.antsf/') ||
                relative == 'antsf_flavors.json'))) {
      throw FormatException('Unsafe managed path: $relative');
    }
    var current = root.path;
    for (final part in relative.split('/')) {
      current = p.join(current, part);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Refusing symbolic link in managed path: $relative');
      }
    }
  }

  T _locked<T>(T Function() operation) {
    _safe('.antsf/sync.lock', internal: true);
    final lock = _file('.antsf/sync.lock');
    lock.parent.createSync(recursive: true);
    final handle = lock.openSync(mode: FileMode.append);
    try {
      handle.lockSync(FileLock.exclusive);
      return operation();
    } finally {
      handle.closeSync();
    }
  }

  void apply(
    Map<String, List<int>> outputs, {
    bool initialize = false,
    Map<String, List<int>> inputs = const {},
    String? updatedConfig,
    String? expectedConfig,
    void Function(String path)? afterWrite,
  }) => _locked(() {
    final journal = _file('.antsf/transaction.json');
    if (journal.existsSync()) {
      throw StateError(
        'Interrupted synchronization: run antsf_starter recover first.',
      );
    }
    final configFile = _file('antsf_flavors.json');
    final originalConfig = configFile.readAsStringSync();
    if (expectedConfig != null && originalConfig != expectedConfig) {
      throw StateError(
        'Configuration changed during rendering; retry without overwriting it.',
      );
    }
    final manifestFile = _file('.antsf/managed.json');
    if (initialize && manifestFile.existsSync()) {
      throw StateError('Project is already initialized.');
    }
    if (!initialize && !manifestFile.existsSync()) {
      throw StateError('Not a generated project: managed manifest is absent.');
    }
    final previous = manifestFile.existsSync()
        ? (jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>)
        : <String, dynamic>{'schemaVersion': 1, 'files': <String, dynamic>{}};
    if (previous['schemaVersion'] != 1 || previous['files'] is! Map) {
      throw StateError('Unsupported managed manifest.');
    }
    final oldHashes = Map<String, dynamic>.from(previous['files'] as Map);
    final allPaths = {...oldHashes.keys, ...outputs.keys}.toList()..sort();
    for (final path in allPaths) {
      _safe(path);
      final file = _file(path);
      if (oldHashes.containsKey(path)) {
        if (!file.existsSync() ||
            digest(file.readAsBytesSync()) != oldHashes[path]) {
          throw StateError(
            'Managed file conflict: $path. Restore the generated baseline or move your edits before sync.',
          );
        }
      } else if (!initialize && file.existsSync()) {
        throw StateError('Refusing to overwrite an unowned file: $path');
      }
    }
    for (final entry in inputs.entries) {
      _safe(entry.key, internal: entry.key.startsWith('.antsf/native-base/'));
      final file = _file(entry.key);
      if (!file.existsSync() ||
          digest(file.readAsBytesSync()) != digest(entry.value)) {
        throw StateError('Source asset changed during rendering; retry sync.');
      }
    }
    final nextConfig = updatedConfig ?? originalConfig;
    final manifest =
        '${const JsonEncoder.withIndent('  ').convert({
          'schemaVersion': 1,
          'configSha256': digest(utf8.encode(nextConfig)),
          'inputs': {for (final path in (inputs.keys.toList()..sort())) path: digest(inputs[path]!)},
          'files': {for (final path in (outputs.keys.toList()..sort())) path: digest(outputs[path]!)},
        })}\n';
    final writes = <String, List<int>?>{
      for (final path in allPaths) path: outputs[path],
      if (updatedConfig != null) 'antsf_flavors.json': utf8.encode(nextConfig),
      '.antsf/managed.json': utf8.encode(manifest),
    };
    final backups = <String, String?>{};
    for (final path in writes.keys) {
      _safe(path, internal: true);
      final file = _file(path);
      backups[path] = file.existsSync()
          ? base64Encode(file.readAsBytesSync())
          : null;
    }
    journal.writeAsStringSync(
      jsonEncode({'schemaVersion': 1, 'backups': backups}),
      flush: true,
    );
    try {
      for (final entry in writes.entries) {
        _write(entry.key, entry.value);
        afterWrite?.call(entry.key);
      }
      journal.deleteSync();
    } catch (_) {
      _restore(backups);
      journal.deleteSync();
      rethrow;
    }
  });

  void recover() => _locked(() {
    final file = _file('.antsf/transaction.json');
    if (!file.existsSync()) {
      throw StateError('No interrupted synchronization to recover.');
    }
    final journal = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (journal['schemaVersion'] != 1 || journal['backups'] is! Map) {
      throw StateError('Invalid recovery journal.');
    }
    final backups = Map<String, String?>.from(journal['backups'] as Map);
    // Validate the entire journal before applying any restore operation.
    for (final entry in backups.entries) {
      _safe(entry.key, internal: true);
      if (entry.value != null) base64Decode(entry.value!);
    }
    _restore(backups);
    file.deleteSync();
  });

  void _restore(Map<String, String?> backups) {
    for (final entry in backups.entries) {
      _write(
        entry.key,
        entry.value == null ? null : base64Decode(entry.value!),
      );
    }
  }

  void _write(String path, List<int>? bytes) {
    _safe(path, internal: true);
    final file = _file(path);
    if (bytes == null) {
      if (file.existsSync()) file.deleteSync();
    } else {
      file.parent.createSync(recursive: true);
      if (!file.existsSync() ||
          digest(file.readAsBytesSync()) != digest(bytes)) {
        file.writeAsBytesSync(bytes, flush: true);
      }
    }
  }
}
