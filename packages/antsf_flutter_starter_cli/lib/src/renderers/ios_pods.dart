/// A journaled boundary for CocoaPods' legitimate Runner project integration.
/// Keep this independent of the CLI so pod install needs only the app's Dart SDK.
String renderIosPodsIntegration() => r'''
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'flavor_guard.dart' as guard;

const project = 'ios/Runner.xcodeproj/project.pbxproj';
const baseline = '.antsf/native-base/$project';
const manifestPath = '.antsf/managed.json';
const journalPath = '.antsf/transaction.json';

String hash(List<int> bytes) => sha256.convert(bytes).toString();
Never fail(String message) => throw StateError(message);

File checkedFile(String path) {
  if (path.startsWith('/') || path.contains('\\') || path.contains(':') ||
      path.split('/').any((p) => p == '..' || p == '.' || p.isEmpty)) {
    fail('Unsafe CocoaPods integration path.');
  }
  var cursor = Directory.current.path;
  for (final component in path.split('/')) {
    cursor = '$cursor${Platform.pathSeparator}$component';
    if (FileSystemEntity.typeSync(cursor, followLinks: false) == FileSystemEntityType.link) {
      fail('CocoaPods integration may not follow symbolic links.');
    }
  }
  return File(path);
}

void main(List<String> arguments) {
  RandomAccessFile? lock;
  try {
    if (arguments.length != 1 || !{'begin', 'complete'}.contains(arguments.single)) {
      fail('Expected begin or complete from the generated Podfile.');
    }
    lock = checkedFile('.antsf/sync.lock').openSync(mode: FileMode.append);
    lock.lockSync(FileLock.exclusive);
    final journalFile = checkedFile(journalPath);
    if (arguments.single == 'begin') {
      if (journalFile.existsSync()) fail('Interrupted integration: run antsf_starter recover before pod install.');
      guard.main(['--flavor=dev', '--platform=ios']);
      if (exitCode != 0) return;
      final backups = <String, String>{
        for (final path in [project, baseline, manifestPath])
          path: base64Encode(checkedFile(path).readAsBytesSync()),
      };
      journalFile.writeAsStringSync(jsonEncode({
        'schemaVersion': 1, 'operation': 'ios-cocoapods', 'backups': backups,
      }), flush: true);
      return;
    }
    final journal = jsonDecode(journalFile.readAsStringSync()) as Map<String, dynamic>;
    if (journal['schemaVersion'] != 1 || journal['operation'] != 'ios-cocoapods') {
      fail('Invalid CocoaPods integration journal; recover the interrupted operation.');
    }
    final backups = Map<String, String>.from(journal['backups'] as Map);
    if (backups.length != 3 || ![project, baseline, manifestPath].every(backups.containsKey)) {
      fail('Unexpected CocoaPods integration backup set.');
    }
    final manifestBytes = base64Decode(backups[manifestPath]!);
    if (hash(checkedFile(manifestPath).readAsBytesSync()) != hash(manifestBytes)) {
      fail('Managed state changed during pod install; recover before retrying.');
    }
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    if (hash(checkedFile('antsf_flavors.json').readAsBytesSync()) != manifest['configSha256']) {
      fail('Configuration changed during pod install; recover before retrying.');
    }
    final tracked = <String, dynamic>{
      ...manifest['files'] as Map<String, dynamic>,
      ...manifest['inputs'] as Map<String, dynamic>,
    };
    // CocoaPods may change only the Runner project, not generated settings,
    // icons, source assets, configuration or the prior native baseline.
    for (final entry in tracked.entries) {
      if (entry.key != project && hash(checkedFile(entry.key).readAsBytesSync()) != entry.value) {
        fail('Managed input/output changed during pod install: ${entry.key}. Recover before retrying.');
      }
    }
    final integrated = checkedFile(project).readAsBytesSync();
    // Preserve standard CocoaPods groups, framework references and [CP] phases
    // as the next rendering baseline. Flavor configuration is still regenerated.
    checkedFile(baseline).writeAsBytesSync(integrated, flush: true);
    (manifest['inputs'] as Map)[baseline] = hash(integrated);
    (manifest['files'] as Map)[project] = hash(integrated);
    checkedFile(manifestPath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n', flush: true,
    );
    journalFile.deleteSync();
  } catch (_) {
    // Never expose configuration, signing data or raw subprocess errors.
    stderr.writeln('CocoaPods integration stopped. Restore any changed managed files, then run antsf_starter recover if a transaction exists and retry pod install.');
    exitCode = 2;
  } finally {
    lock?.closeSync();
  }
}
''';
