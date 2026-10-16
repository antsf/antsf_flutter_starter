import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'creation.dart';
import 'flutter_tool.dart';
import 'guard.dart';
import 'links.dart';
import 'renderers/android.dart';
import 'renderers/app.dart';
import 'renderers/icons.dart';
import 'renderers/ios.dart';
import 'synchronizer.dart';

const configFilename = 'antsf_flavors.json';

class ProjectGenerator {
  ProjectGenerator(this.flutter);
  final FlutterTool flutter;

  Future<void> create(
    Directory destination,
    ProjectConfig config, {
    Map<String, String> sourceIcons = const {},
    bool setup = true,
  }) async {
    config.validate();
    // Validate all supplied assets before invoking flutter or touching destination.
    for (final path in sourceIcons.values) {
      if (!File(path).existsSync()) {
        throw const FormatException('An icon source does not exist.');
      }
    }
    await createInDestination(destination, (root) async {
      final project = config.data['project'] as Map<String, dynamic>;
      await _require(
        await flutter.flutter([
          'create',
          '--platforms=android,ios',
          '--org',
          project['organization'],
          '--project-name',
          project['name'],
          '--no-pub',
          root.path,
        ], root.parent.path),
        'flutter create',
      );
      final counterTest = File(p.join(root.path, 'test', 'widget_test.dart'));
      if (counterTest.existsSync()) counterTest.deleteSync();
      final nativeBase = Directory(p.join(root.path, '.antsf', 'native-base'));
      for (final platform in ['android', 'ios']) {
        final source = Directory(p.join(root.path, platform));
        for (final entity in source.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File ||
              {
                '.gitignore',
                'local.properties',
                'Generated.xcconfig',
                'flutter_export_environment.sh',
              }.contains(p.basename(entity.path))) {
            continue;
          }
          final relative = p.relative(entity.path, from: root.path);
          final target = File(p.join(nativeBase.path, relative));
          target.parent.createSync(recursive: true);
          entity.copySync(target.path);
        }
      }
      for (final entry in sourceIcons.entries) {
        final source = File(entry.value);
        final relative =
            'assets/branding/${entry.key}${p.extension(source.path).toLowerCase()}';
        final target = File(p.join(root.path, p.fromUri(relative)));
        target.parent.createSync(recursive: true);
        source.copySync(target.path);
        if (entry.key == 'base') {
          config.data['icon'] = relative;
        } else {
          config.flavors[entry.key]['icon'] = relative;
        }
      }
      File(p.join(root.path, configFilename))
          .writeAsStringSync(config.encode());
      final appFiles = renderApp(config.data, root);
      // Creation-only source becomes application-owned immediately. Future sync
      // never overwrites features/router/DI/theme/main/tests/pubspec dependencies.
      for (final entry in appFiles.entries) {
        if (_appManaged(entry.key)) continue;
        final file = File(p.join(root.path, p.fromUri(entry.key)));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
      final ignore = File(p.join(root.path, '.gitignore'));
      ignore.writeAsStringSync(
        '\n# Flavor tooling runtime state (keep manifest/native-base tracked).\n.antsf/sync.lock\n.antsf/transaction.json\nandroid/signing.properties\n*.jks\n*.keystore\n# Every baseline byte is a required versioned rendering input.\n!/.antsf/native-base/\n!/.antsf/native-base/**\n',
        mode: FileMode.append,
      );
      File(p.join(root.path, 'README.md'))
          .writeAsStringSync(_appReadme(config));
      await synchronize(root, config, initialize: true);
      if (setup) {
        await _require(
          await flutter.flutter(['pub', 'get'], root.path),
          'flutter pub get',
        );
        await _require(
          await flutter.dart(['run', 'build_runner', 'build'], root.path),
          'Dart code generation',
        );
      }
    });
  }

  bool _appManaged(String path) => path.startsWith('lib/core/config/');

  Future<void> synchronize(
    Directory root,
    ProjectConfig config, {
    bool initialize = false,
    String? updatedConfig,
    String? expectedConfig,
  }) async {
    config.validate();
    final base = Directory(p.join(root.path, '.antsf', 'native-base'));
    if (!base.existsSync()) {
      throw StateError(
        'Pristine native baseline is missing; this is not a supported generated project.',
      );
    }
    // Capture inputs BEFORE rendering and recheck inside the write lock.
    final inputs = <String, List<int>>{};
    for (final entity in base.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        inputs[p.relative(entity.path, from: root.path).replaceAll('\\', '/')] =
            entity.readAsBytesSync();
      }
    }
    final icons = [
      config.data['icon'],
      for (final flavor in config.flavors.values) flavor['icon'],
    ].whereType<String>().toSet();
    for (final icon in icons) {
      inputs[icon] = File(p.join(root.path, p.fromUri(icon))).readAsBytesSync();
    }
    final output = <String, List<int>>{};
    void text(Map<String, String> files) {
      for (final entry in files.entries) {
        if (output.containsKey(entry.key)) {
          throw StateError('Duplicate renderer output: ${entry.key}');
        }
        output[entry.key] = utf8.encode(entry.value);
      }
    }

    text(renderAndroid(config.data, base));
    text(renderIos(config.data, base));
    text(
      Map.fromEntries(
        renderApp(config.data, root).entries.where((e) => _appManaged(e.key)),
      ),
    );
    text(renderLinks(config.data));
    text({'tool/flavor_guard.dart': renderGuard()});
    for (final entry in renderIcons(config.data, root).entries) {
      if (output.containsKey(entry.key)) {
        throw StateError('Duplicate icon output.');
      }
      output[entry.key] = entry.value;
    }
    // Guarded bytes must not be normalized by core.autocrlf on another host.
    // Leave application-owned files under Git's ordinary attribute policy.
    final byteStable = {
      ...output.keys,
      ...inputs.keys,
      '.gitattributes',
      '.antsf/managed.json',
      configFilename,
    }.toList()..sort();
    output['.gitattributes'] = utf8.encode(
      '# Generated: preserve exact hashes across Git checkouts.\n'
      '${byteStable.map((path) => '${jsonEncode(path)} -text').join('\n')}\n',
    );
    Synchronizer(root).apply(
      output,
      initialize: initialize,
      inputs: inputs,
      updatedConfig: updatedConfig,
      expectedConfig: expectedConfig,
    );
  }

  Future<void> _require(int code, String step) async {
    if (code != 0) {
      throw StateError(
        '$step failed with exit code $code. No completed project was published.',
      );
    }
  }
}

String _appReadme(ProjectConfig config) =>
    '''# ${config.data['project']['displayName']}

Created with antsf Flutter Starter. Configuration: `$configFilename` (non-secret).
Native Android/iOS versions are independent per flavor and platform. The pubspec
version `0.0.0+1` is only a Flutter baseline, not the packaged application version.

## Commands

Install the CLI as described in its repository README, then from this project:

    antsf_starter validate
    antsf_starter sync
    antsf_starter run --flavor dev
    antsf_starter build --flavor dev --platform android --mode debug
    antsf_starter version --flavor dev --platform android --name 1.0.4 --build 51

Every run/build requires a flavor. Direct Flutter commands also require
`--flavor dev` (or another enabled flavor). Never override versions with Flutter
build flags: edit the selected flavor/platform using the configuration or CLI.
Flutter always forwards pubspec defaults; native guard accepts that baseline but
native metadata always comes from flavor configuration, not pubspec.

After editing configuration or replacing a source icon, run `antsf_starter sync`.
Configuration/core generated outputs, native configuration, icons, link templates,
and the build guard are managed. Feature/router/DI/theme/main/test code and
pubspec dependencies belong to you. Managed-file manual conflicts STOP sync;
restore the generated baseline or move your changes to an application-owned area.
Do not edit `.antsf/native-base` or the manifest by hand. An interrupted sync blocks
builds; use `antsf_starter recover`, inspect restored output, then sync again.

The initial API URLs need no live backend to generate/build this app. HTTP is
restricted to explicitly enabled local development. Production logging is off;
non-production logging excludes credentials, URL query data, and bodies.
Dev/stg icon labels and in-app banners remain enabled in release mode.

## Verification

    flutter pub get
    dart run build_runner build
    flutter analyze
    flutter test

Android prod debug builds are validation artifacts, NOT signed release artifacts.
For Android release signing, follow the comments in `android/app/build.gradle.kts`;
keep real signing material out of Git. Production release never falls back to a
debug key. iOS signing/provisioning requires your own Apple credentials on macOS;
an unsigned simulator build is not an App Store release.

Optional verified HTTPS links: see `docs/flavor-links.md`. Server files are only
templates and must not be called verified until actual signing/domain tests pass.
Firebase and production crash reporting are not installed automatically.
''';
