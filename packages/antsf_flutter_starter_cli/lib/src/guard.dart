/// Generated self-contained build guard; crypto is an application dev dependency.
String renderGuard() => r'''
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

Never fail(String message) => throw StateError(message);
String hash(List<int> bytes) => sha256.convert(bytes).toString();

void main(List<String> arguments) {
  try {
    final options = <String, String>{};
    for (final argument in arguments) {
      final separator = argument.indexOf('=');
      if (!argument.startsWith('--') || separator < 3) { fail('Expected --key=value build-guard arguments.'); }
      final key = argument.substring(2, separator);
      if (options.containsKey(key) || !{'flavor', 'platform', 'build-name', 'build-number', 'dart-defines'}.contains(key)) { fail('Unknown or duplicate build-guard argument.'); }
      options[key] = argument.substring(separator + 1);
    }
    final flavor = options['flavor'];
    final platform = options['platform'];
    if (flavor == null || flavor.isEmpty) { fail('Select a native flavor explicitly with --flavor.'); }
    if (platform != 'android' && platform != 'ios') { fail('A native platform is required.'); }
    final root = Directory.current;
    if (File('.antsf/transaction.json').existsSync()) { fail('Interrupted sync: run antsf_starter recover before building.'); }
    final configBytes = File('antsf_flavors.json').readAsBytesSync();
    final manifest = jsonDecode(File('.antsf/managed.json').readAsStringSync()) as Map<String, dynamic>;
    if (manifest['schemaVersion'] != 1 || manifest['configSha256'] != hash(configBytes)) { fail('Stale configuration: run antsf_starter sync.'); }
    final config = jsonDecode(utf8.decode(configBytes)) as Map<String, dynamic>;
    if (config['schemaVersion'] != 1) { fail('Unsupported configuration schema.'); }
    final flavors = config['flavors'] as Map<String, dynamic>;
    if (!flavors.containsKey(flavor)) { fail('Unknown native flavor.'); }
    final tracked = <String, dynamic>{...manifest['files'] as Map<String, dynamic>, ...?manifest['inputs'] as Map<String, dynamic>?};
    for (final entry in tracked.entries) {
      final path = entry.key;
      if (path.startsWith('/') || path.contains('\\') || path.contains(':') || path.split('/').any((p) => p == '..' || p == '.' || p.isEmpty)) { fail('Unsafe managed manifest path.'); }
      var cursor = root.path;
      for (final component in path.split('/')) {
        cursor = '$cursor${Platform.pathSeparator}$component';
        if (FileSystemEntity.typeSync(cursor, followLinks: false) == FileSystemEntityType.link) { fail('Managed output may not use symbolic links.'); }
      }
      final file = File(path);
      if (!file.existsSync() || hash(file.readAsBytesSync()) != entry.value) { fail('Managed output changed: $path. Reconcile edits before syncing.'); }
    }
    final target = flavors[flavor][platform] as Map<String, dynamic>;
    final expectedName = target['versionName'].toString();
    final expectedBuild = target[platform == 'android' ? 'versionCode' : 'buildNumber'].toString();
    final name = options['build-name'];
    final build = options['build-number'];
    // Flutter always forwards pubspec values. 0.0.0+1 is a non-authoritative
    // baseline, not a flavor's version; native output uses target values only.
    if (name != null && name.isNotEmpty && name != '0.0.0' && name != expectedName) { fail('Conflicting --build-name; edit the target flavor/platform configuration.'); }
    if (build != null && build.isNotEmpty && build != '1' && build != expectedBuild) { fail('Conflicting --build-number; edit the target flavor/platform configuration.'); }
    final defines = options['dart-defines'];
    if (defines != null && defines.isNotEmpty) {
      for (final encoded in defines.split(',')) {
        final decoded = utf8.decode(base64Decode(encoded));
        final separator = decoded.indexOf('=');
        if (separator < 1) { fail('Malformed Dart define.'); }
        final key = decoded.substring(0, separator);
        final value = decoded.substring(separator + 1);
        if ({'APP_ENV', 'FLAVOR', 'FLUTTER_APP_FLAVOR'}.contains(key) && value != flavor) { fail('Dart environment contradicts the native flavor.'); }
      }
    }
  } catch (error) {
    // Do not echo raw configuration or potentially credential-bearing URLs.
    stderr.writeln(error is StateError ? 'Flavor guard: ${error.message}' : 'Flavor guard: invalid or missing managed configuration; validate and sync the project.');
    exitCode = 2;
  }
}
''';
