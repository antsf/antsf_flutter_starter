import 'dart:convert';
import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/renderers/ios.dart';
import 'package:antsf_flutter_starter_cli/src/guard.dart';
import 'package:antsf_flutter_starter_cli/src/synchronizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

Map<String, dynamic> config({bool staging = false}) => {
  'schemaVersion': 1,
  'project': {
    'name': 'sample_app',
    'organization': 'com.example',
    'applicationId': 'com.example.sample_app',
    'displayName': 'Sample',
    'starter': <String, dynamic>{},
  },
  'icon': null,
  'flavors': {
    for (final flavor in ['dev', if (staging) 'stg', 'prod'])
      flavor: {
        'applicationIdSuffix': flavor == 'prod' ? '' : '.$flavor',
        'displayName': flavor == 'prod'
            ? 'Sample'
            : '[${flavor.toUpperCase()}] Sample',
        'apiBaseUrl': 'https://$flavor.example.net',
        'allowLocalHttp': false,
        'logMetadata': flavor != 'prod',
        'icon': null,
        'android': {
          'versionName': '1.0.4',
          'versionCode': 51,
          'versionNameSuffix': '-b{build}',
        },
        'ios': {
          'versionName': flavor == 'dev' ? '2.3.4' : '1.2.0',
          'buildNumber': flavor == 'dev' ? '7' : '2',
        },
        'links': null,
      },
  },
};

ProcessResult runShell(String script, Map<String, String> environment) {
  final file = File(
    p.join(
      Platform.environment['TMPDIR'] ?? Directory.systemTemp.path,
      'antsf_guard_${pid}_${DateTime.now().microsecondsSinceEpoch}.sh',
    ),
  );
  file.writeAsStringSync(script);
  // Use native Git Bash on Windows, not the WSL launcher (which drops env).
  final gitBash = p.join(
    Platform.environment['ProgramFiles'] ?? 'C:/Program Files',
    'Git/bin/bash.exe',
  );
  final shell = Platform.isWindows && File(gitBash).existsSync()
      ? gitBash
      : '/bin/sh';
  try {
    return Process.runSync(shell, [
      file.path.replaceAll('\\', '/'),
    ], environment: environment);
  } finally {
    file.deleteSync();
  }
}

// A small independent OpenStep syntax reader for PBX graph assertions. This is
// not an Xcode build and intentionally does not claim semantic Apple validation.
class OpenStepParser {
  OpenStepParser(String text)
    : tokens =
          RegExp(
                r'"(?:\\.|[^"\\])*"|/\*[\s\S]*?\*/|//[^\n]*|[{}()=;,]|[^\s{}()=;,]+',
              )
              .allMatches(text)
              .map((m) => m.group(0)!)
              .where(
                (token) => !token.startsWith('//') && !token.startsWith('/*'),
              )
              .toList();
  final List<String> tokens;
  int index = 0;

  Object parse() {
    final value = _value();
    if (index != tokens.length) {
      throw FormatException('Trailing PBX tokens: ${tokens.sublist(index)}');
    }
    return value;
  }

  String _take() {
    if (index >= tokens.length) {
      throw const FormatException('Unexpected PBX end');
    }
    return tokens[index++];
  }

  void _expect(String token) {
    final actual = _take();
    if (actual != token) throw FormatException('Expected $token, got $actual');
  }

  Object _value() {
    final token = _take();
    if (token == '{') {
      final result = <String, Object>{};
      while (tokens[index] != '}') {
        final key = _take();
        final decoded = key.startsWith('"') ? jsonDecode(key) as String : key;
        _expect('=');
        final value = _value();
        if (result.containsKey(decoded)) {
          throw FormatException('Duplicate PBX key $decoded');
        }
        result[decoded] = value;
        _expect(';');
      }
      _expect('}');
      return result;
    }
    if (token == '(') {
      final result = <Object>[];
      while (tokens[index] != ')') {
        result.add(_value());
        if (tokens[index] == ',') {
          _expect(',');
        } else if (tokens[index] != ')') {
          throw const FormatException('Missing PBX comma');
        }
      }
      _expect(')');
      return result;
    }
    if (token.startsWith('"')) return jsonDecode(token) as String;
    if (['}', ')', '=', ';', ','].contains(token)) {
      throw FormatException('Unexpected PBX token $token');
    }
    return token;
  }
}

void main() {
  late Directory template;
  late String originalPbx;
  setUpAll(() {
    template = Directory(
      p.join(
        Platform.environment['TMPDIR'] ?? Directory.systemTemp.path,
        'antsf_ios_renderer_${pid}_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    final result = Process.runSync(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      [
        'create',
        '--no-pub',
        '--platforms=ios',
        '--project-name=sample_app',
        template.path,
      ],
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    originalPbx = File(
      p.join(template.path, 'ios/Runner.xcodeproj/project.pbxproj'),
    ).readAsStringSync();
  });
  tearDownAll(() {
    if (template.existsSync()) template.deleteSync(recursive: true);
  });

  test('CocoaPods integration remains guarded and survives subsequent sync', () {
    final files = renderIos(config(), template);
    expect(files, contains('tool/ios_pods_integration.dart'));
    final root = Directory.systemTemp.createTempSync('antsf_pods_test_');
    addTearDown(() => root.deleteSync(recursive: true));
    final inputs = <String, List<int>>{};
    for (final entity in Directory(
      p.join(template.path, 'ios'),
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      final path =
          '.antsf/native-base/${p.relative(entity.path, from: template.path).replaceAll('\\', '/')}';
      final copy = File(p.join(root.path, path));
      copy.parent.createSync(recursive: true);
      copy.writeAsBytesSync(entity.readAsBytesSync());
      inputs[path] = copy.readAsBytesSync();
    }
    File(p.join(root.path, 'antsf_flavors.json'))
        .writeAsStringSync(jsonEncode(config()));
    final sync = Synchronizer(root);
    sync.apply(
      {
        for (final e in files.entries) e.key: utf8.encode(e.value),
        'tool/flavor_guard.dart': utf8.encode(renderGuard()),
      },
      initialize: true,
      inputs: inputs,
    );
    final packages = p.absolute('.dart_tool/package_config.json');
    ProcessResult run(String script, List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      ['--packages=$packages', 'tool/$script.dart', ...args],
      workingDirectory: root.path,
    );
    final begin = run('ios_pods_integration', ['begin']);
    expect(begin.exitCode, 0, reason: '${begin.stdout}\n${begin.stderr}');
    expect(
      File(p.join(root.path, '.antsf/transaction.json')).existsSync(),
      isTrue,
    );
    final pbx = File(p.join(root.path, 'ios/Runner.xcodeproj/project.pbxproj'));
    pbx.writeAsStringSync(
      pbx.readAsStringSync().replaceFirst(
        '/* End PBXFileReference section */',
        '\t\tABCDEFABCDEFABCDEFABCDEF /* Pods_Runner.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; path = Pods_Runner.framework; sourceTree = BUILT_PRODUCTS_DIR; };\n/* End PBXFileReference section */',
      ),
    );
    final integrated = pbx.readAsStringSync();
    final complete = run('ios_pods_integration', ['complete']);
    expect(
      complete.exitCode,
      0,
      reason: '${complete.stdout}\n${complete.stderr}',
    );
    expect(
      File(p.join(root.path, '.antsf/transaction.json')).existsSync(),
      isFalse,
    );
    final guard = run('flavor_guard', ['--flavor=dev', '--platform=ios']);
    expect(guard.exitCode, 0, reason: '${guard.stderr}');
    expect(
      File(
        p.join(
          root.path,
          '.antsf/native-base/ios/Runner.xcodeproj/project.pbxproj',
        ),
      ).readAsStringSync(),
      integrated,
    );
    final next = renderIos(
      config(),
      Directory(p.join(root.path, '.antsf/native-base')),
    );
    expect(
      next['ios/Runner.xcodeproj/project.pbxproj'],
      contains('Pods_Runner.framework'),
    );
    inputs['.antsf/native-base/ios/Runner.xcodeproj/project.pbxproj'] = utf8
        .encode(integrated);
    sync.apply({
      for (final e in next.entries) e.key: utf8.encode(e.value),
      'tool/flavor_guard.dart': utf8.encode(renderGuard()),
    }, inputs: inputs);
    expect(run('flavor_guard', ['--flavor=dev', '--platform=ios']).exitCode, 0);
    final synchronized = pbx.readAsStringSync();
    pbx.writeAsStringSync('${pbx.readAsStringSync()}\n// manual edit\n');
    expect(run('ios_pods_integration', ['begin']).exitCode, 2);
    expect(
      File(p.join(root.path, '.antsf/transaction.json')).existsSync(),
      isFalse,
    );
    pbx.writeAsStringSync(synchronized);
    expect(run('ios_pods_integration', ['begin']).exitCode, 0);
    pbx.writeAsStringSync('$synchronized\n// interrupted integration\n');
    expect(run('flavor_guard', ['--flavor=dev', '--platform=ios']).exitCode, 2);
    expect(() => sync.apply({}), throwsStateError);
    sync.recover();
    expect(pbx.readAsStringSync(), synchronized);
    expect(run('flavor_guard', ['--flavor=dev', '--platform=ios']).exitCode, 0);
    // A different managed write during pod install may not be adopted.
    expect(run('ios_pods_integration', ['begin']).exitCode, 0);
    final settings = File(p.join(root.path, 'ios/Flutter/Debug-dev.xcconfig'));
    final originalSettings = settings.readAsStringSync();
    settings.writeAsStringSync(
      '$originalSettings\n// concurrent manual edit\n',
    );
    pbx.writeAsStringSync('$synchronized\n// integration candidate\n');
    expect(run('ios_pods_integration', ['complete']).exitCode, 2);
    expect(
      File(p.join(root.path, '.antsf/transaction.json')).existsSync(),
      isTrue,
    );
    sync.recover();
    expect(pbx.readAsStringSync(), synchronized);
    expect(settings.readAsStringSync(), contains('// concurrent manual edit'));
    settings.writeAsStringSync(originalSettings);
    expect(run('flavor_guard', ['--flavor=dev', '--platform=ios']).exitCode, 0);
  });

  test('renders shared flavor schemes with real target/configuration references', () {
    final files = renderIos(config(staging: true), template);
    final pbx = files['ios/Runner.xcodeproj/project.pbxproj']!;
    final definedConfigs = RegExp(
      r'([A-F0-9]{24}) /\* ([^*]+) \*/ = \{\s*isa = XCBuildConfiguration;',
    ).allMatches(pbx).map((m) => m.group(1)).toSet();
    final lists = RegExp(
      r'buildConfigurations = \((.*?)\);',
      dotAll: true,
    ).allMatches(pbx);
    expect(lists, hasLength(3));
    for (final list in lists) {
      final ids = RegExp(r'([A-F0-9]{24}) /\* ([^*]+) \*/')
          .allMatches(list.group(1)!);
      for (final id in ids) {
        expect(definedConfigs, contains(id.group(1)));
      }
      for (final flavor in ['dev', 'stg', 'prod']) {
        for (final mode in ['Debug', 'Profile', 'Release']) {
          expect(list.group(1), contains('/* $mode-$flavor */'));
        }
      }
    }
    final runnerId = RegExp(
      r'([A-F0-9]{24}) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;',
    ).firstMatch(pbx)!.group(1);
    for (final flavor in ['dev', 'stg', 'prod']) {
      final scheme = XmlDocument.parse(
        files['ios/Runner.xcodeproj/xcshareddata/xcschemes/$flavor.xcscheme']!,
      );
      for (final action in ['LaunchAction', 'TestAction', 'AnalyzeAction']) {
        expect(
          scheme
              .findAllElements(action)
              .single
              .getAttribute('buildConfiguration'),
          'Debug-$flavor',
        );
      }
      expect(
        scheme
            .findAllElements('ProfileAction')
            .single
            .getAttribute('buildConfiguration'),
        'Profile-$flavor',
      );
      expect(
        scheme
            .findAllElements('ArchiveAction')
            .single
            .getAttribute('buildConfiguration'),
        'Release-$flavor',
      );
      expect(
        scheme
            .findAllElements('BuildableReference')
            .where((e) => e.getAttribute('BlueprintName') == 'Runner')
            .every((e) => e.getAttribute('BlueprintIdentifier') == runnerId),
        isTrue,
      );
    }
    expect(
      File(p.join(template.path, 'ios/Runner.xcodeproj/project.pbxproj'))
          .readAsStringSync(),
      originalPbx,
    );
    expect(renderIos(config(staging: true), template), files);
  });

  test('rejects absent/unknown flavors before Flutter, with no runnable Runner scheme', () {
    final files = renderIos(config(), template);
    final pbx = files['ios/Runner.xcodeproj/project.pbxproj']!;
    final guard = RegExp(
      r'([A-F0-9]{24}) /\* Antsf Flavor Guard \*/ = \{(.*?)^\t\t\};',
      multiLine: true,
      dotAll: true,
    ).firstMatch(pbx)!;
    final script = jsonDecode(
      RegExp(r'shellScript = ("(?:\\.|[^"\\])*");')
          .firstMatch(guard.group(2)!)!
          .group(1)!,
    ) as String;
    final runner = RegExp(
      r'/\* Runner \*/ = \{\s*isa = PBXNativeTarget;(.*?)^\t\t\};',
      multiLine: true,
      dotAll: true,
    ).firstMatch(pbx)!.group(1)!;
    expect(
      runner.indexOf('/* Antsf Flavor Guard */'),
      lessThan(runner.indexOf('/* Run Script */')),
    );
    expect(
      script,
      contains(
        r'"$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" run tool/flavor_guard.dart',
      ),
    );
    expect(script, contains(r'"--build-name=${FLUTTER_BUILD_NAME:-}"'));
    expect(script, contains(r'"--build-number=${FLUTTER_BUILD_NUMBER:-}"'));
    expect(script, contains('--platform=ios'));
    expect(script, contains(r'"--dart-defines=${DART_DEFINES:-}"'));
    for (final configuration in ['', 'Debug', 'Release-unknown']) {
      final result = runShell(script, {'CONFIGURATION': configuration});
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('explicit flavor'));
    }
    final disabled = XmlDocument.parse(
      files['ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme']!,
    );
    expect(disabled.findAllElements('BuildableProductRunnable'), isEmpty);
    expect(disabled.findAllElements('LaunchAction'), isEmpty);
    expect(disabled.toXmlString(), contains('explicit flavor'));
    final defaultScript = disabled
        .findAllElements('ActionContent')
        .single
        .getAttribute('scriptText')!;
    final defaultBuild = runShell(defaultScript, {'CONFIGURATION': 'Release'});
    expect(defaultBuild.exitCode, isNot(0));
    expect(defaultBuild.stderr, contains('explicit flavor'));
    final dev = XmlDocument.parse(
      files['ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme']!,
    );
    final prepare = dev
        .findAllElements('ActionContent')
        .first
        .getAttribute('scriptText')!;
    expect(
      prepare.indexOf('tool/flavor_guard.dart'),
      lessThan(prepare.indexOf('xcode_backend.sh')),
    );
    expect(prepare, contains('Debug-dev|Profile-dev|Release-dev'));
  });

  test(
    'guard forwards arguments intact and propagates rejection before prepare',
    () {
      final files = renderIos(config(), template);
      final devScheme = XmlDocument.parse(
        files['ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme']!,
      );
      final script = devScheme
          .findAllElements('ActionContent')
          .first
          .getAttribute('scriptText')!;
      final sdk = Directory(
        p.join(template.path, 'spy Flutter SDK with spaces'),
      );
      final dart = File(p.join(sdk.path, 'bin/cache/dart-sdk/bin/dart'));
      dart.parent.createSync(recursive: true);
      // This spy verifies the shell contract, not the parent-owned Dart guard.
      dart.writeAsStringSync(
        '#!/bin/sh\nprintf \'%s\\n\' "\$@"\nexit "\${SPY_EXIT:-0}"\n',
      );
      final prepare = File(
        p.join(sdk.path, 'packages/flutter_tools/bin/xcode_backend.sh'),
      );
      prepare.parent.createSync(recursive: true);
      prepare.writeAsStringSync('#!/bin/sh\nprintf \'PREPARED\\n\'\n');
      if (!Platform.isWindows) {
        final chmod = Process.runSync('chmod', ['+x', dart.path]);
        expect(chmod.exitCode, 0, reason: '${chmod.stderr}');
      }
      final defines = [
        'APP_ENV=dev',
        'OTHER=a,b',
      ].map((e) => base64Encode(utf8.encode(e))).join(',');
      final environment = {
        'CONFIGURATION': 'Release-dev',
        'SRCROOT': p.join(template.path, 'ios').replaceAll('\\', '/'),
        'FLUTTER_ROOT': sdk.path.replaceAll('\\', '/'),
        'FLUTTER_BUILD_NAME': '2.3.4',
        'FLUTTER_BUILD_NUMBER': '7',
        'DART_DEFINES': defines,
      };
      final accepted = runShell(script, environment);
      expect(accepted.exitCode, 0, reason: '${accepted.stderr}');
      expect(const LineSplitter().convert(accepted.stdout as String), [
        'run',
        'tool/flavor_guard.dart',
        '--flavor=dev',
        '--platform=ios',
        '--build-name=2.3.4',
        '--build-number=7',
        '--dart-defines=$defines',
        'PREPARED',
      ]);
      final rejected = runShell(script, {...environment, 'SPY_EXIT': '17'});
      expect(rejected.exitCode, 17);
      expect(rejected.stdout, isNot(contains('PREPARED')));
      final contradictory = runShell(script, {
        ...environment,
        'CONFIGURATION': 'Release-prod',
      });
      expect(contradictory.exitCode, isNot(0));
      expect(contradictory.stderr, contains('explicit flavor'));
      expect(contradictory.stdout, isEmpty);
      final staleFlavor = runShell(script, {...environment, 'FLAVOR': 'prod'});
      expect(staleFlavor.exitCode, isNot(0));
      expect(staleFlavor.stderr, contains('conflicts'));
      expect(staleFlavor.stdout, isEmpty);
    },
  );

  test('syncing rendered native files is byte-stable and never clones generated configs', () {
    final c = config(staging: true);
    final first = renderIos(c, template);
    final originals = <String, String?>{};
    try {
      for (final entry in first.entries) {
        final file = File(p.join(template.path, entry.key));
        originals[entry.key] = file.existsSync()
            ? file.readAsStringSync()
            : null;
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(entry.value);
      }
      final second = renderIos(c, template);
      expect(second, first);
      final pbx = second['ios/Runner.xcodeproj/project.pbxproj']!;
      expect(
        RegExp(r'isa = XCBuildConfiguration;').allMatches(pbx),
        hasLength(36),
      );
      expect(pbx, isNot(contains('Debug-dev-dev')));
      final changed = config(staging: true);
      (changed['flavors'] as Map)['dev']['ios']['buildNumber'] = '8';
      final third = renderIos(changed, template);
      expect(
        third['ios/Runner/Info-dev.plist'],
        contains('<string>8</string>'),
      );
      expect(
        third['ios/Runner/Info-prod.plist'],
        first['ios/Runner/Info-prod.plist'],
      );
    } finally {
      for (final entry in originals.entries) {
        final file = File(p.join(template.path, entry.key));
        if (entry.value == null) {
          file.deleteSync();
        } else {
          file.writeAsStringSync(entry.value!);
        }
      }
    }
  });

  test('links and local transport are opt-in, isolated and XML-safe', () {
    final c = config();
    final dev = (c['flavors'] as Map)['dev'] as Map;
    dev['displayName'] = '[DEV] A & B <QA> "App"';
    dev['allowLocalHttp'] = true;
    dev['apiBaseUrl'] = 'http://api.local:8080';
    dev['links'] = {
      'host': 'dev.example.net',
      'paths': ['/open'],
      'appleTeamId': null,
      'sha256CertFingerprints': <String>[],
    };
    final files = renderIos(c, template);
    final devPlist = XmlDocument.parse(files['ios/Runner/Info-dev.plist']!);
    final keys = devPlist
        .findAllElements('key')
        .map((e) => e.innerText)
        .toList();
    expect(
      keys,
      containsAll([
        'NSAppTransportSecurity',
        'NSAllowsLocalNetworking',
        'NSExceptionDomains',
        'api.local',
        'NSExceptionAllowsInsecureHTTPLoads',
      ]),
    );
    expect(keys, isNot(contains('NSAllowsArbitraryLoads')));
    expect(
      devPlist.findAllElements('string').map((e) => e.innerText),
      contains('[DEV] A & B <QA> "App"'),
    );
    final entitlements = XmlDocument.parse(
      files['ios/Runner/Runner-dev.entitlements']!,
    );
    expect(entitlements.findAllElements('string').map((e) => e.innerText), [
      'applinks:dev.example.net',
    ]);
    expect(
      files['ios/Runner.xcodeproj/project.pbxproj'],
      contains('CODE_SIGN_ENTITLEMENTS = "Runner/Runner-dev.entitlements";'),
    );
    expect(files.keys, isNot(contains('ios/Runner/Runner-prod.entitlements')));
    expect(
      files['ios/Runner/Info-prod.plist'],
      isNot(contains('NSAppTransportSecurity')),
    );
    expect(
      files['ios/Runner.xcodeproj/project.pbxproj'],
      isNot(contains('DEVELOPMENT_TEAM =')),
    );
    final disabled = renderIos(config(), template);
    expect(
      disabled.keys.where((key) => key.endsWith('.entitlements')),
      isEmpty,
    );
    expect(
      disabled['ios/Runner/Info-dev.plist'],
      isNot(contains('NSAppTransportSecurity')),
    );
    final unsafe = config();
    (unsafe['flavors'] as Map)['prod']['allowLocalHttp'] = true;
    expect(() => renderIos(unsafe, template), throwsFormatException);
  });

  test('refuses unknown flavors and remote insecure dev APIs', () {
    final unknown = config();
    (unknown['flavors'] as Map)['qa'] = (unknown['flavors'] as Map)['dev'];
    expect(() => renderIos(unknown, template), throwsFormatException);
    final insecure = config();
    (insecure['flavors'] as Map)['dev']['allowLocalHttp'] = true;
    (insecure['flavors'] as Map)['dev']['apiBaseUrl'] =
        'http://remote.example.net';
    expect(() => renderIos(insecure, template), throwsFormatException);
  });

  test(
    'unsupported native template shape fails instead of emitting dangling refs',
    () {
      final file = File(
        p.join(template.path, 'ios/Runner.xcodeproj/project.pbxproj'),
      );
      try {
        file.writeAsStringSync(
          originalPbx.replaceFirst(
            '/* End PBXShellScriptBuildPhase section */',
            '/* missing section */',
          ),
        );
        expect(() {
          renderIos(config(), template);
        }, throwsStateError);
      } finally {
        file.writeAsStringSync(originalPbx);
      }
    },
  );

  test('generated PBX syntax parses and every configuration/phase reference resolves', () {
    final files = renderIos(config(staging: true), template);
    final root =
        OpenStepParser(files['ios/Runner.xcodeproj/project.pbxproj']!).parse()
            as Map;
    final objects = root['objects'] as Map;
    for (final object in objects.values.cast<Map>()) {
      for (final key in [
        'buildConfigurationList',
        'baseConfigurationReference',
      ]) {
        if (object.containsKey(key)) {
          expect(objects, contains(object[key]), reason: key);
        }
      }
      for (final key in ['buildConfigurations', 'buildPhases']) {
        for (final id in (object[key] as List? ?? [])) {
          expect(objects, contains(id), reason: key);
        }
      }
      if (object['isa'] == 'XCBuildConfiguration' &&
          (object['name'] as String).contains('-')) {
        final name = object['name'] as String;
        final settings = object['buildSettings'] as Map;
        if (settings.containsKey('INFOPLIST_FILE')) {
          expect(files, contains('ios/${settings['INFOPLIST_FILE']}'));
          expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], r'$(ANTSF_BUNDLE_ID)');
          final file = objects[object['baseConfigurationReference']] as Map;
          expect(files, contains('ios/${file['path']}'));
          expect(file['path'], 'Flutter/$name.xcconfig');
          expect(file['sourceTree'], 'SOURCE_ROOT');
        }
      }
    }
    for (final entry in files.entries.where(
      (e) =>
          e.key.endsWith('.plist') ||
          e.key.endsWith('.xcscheme') ||
          e.key.endsWith('.entitlements'),
    )) {
      expect(
        () => XmlDocument.parse(entry.value),
        returnsNormally,
        reason: entry.key,
      );
    }
  });

  test('wires per-flavor xcconfigs, identities, icons and independent iOS versions', () {
    final files = renderIos(config(), template);
    final pbx = files['ios/Runner.xcodeproj/project.pbxproj']!;
    for (final flavor in ['dev', 'prod']) {
      final plist = XmlDocument.parse(files['ios/Runner/Info-$flavor.plist']!);
      String value(String key) => plist
          .findAllElements('key')
          .singleWhere((e) => e.innerText == key)
          .nextElementSibling!
          .innerText;
      expect(
        value('CFBundleDisplayName'),
        flavor == 'dev' ? '[DEV] Sample' : 'Sample',
      );
      expect(
        value('CFBundleShortVersionString'),
        flavor == 'dev' ? '2.3.4' : '1.2.0',
      );
      expect(value('CFBundleVersion'), flavor == 'dev' ? '7' : '2');
      expect(value('CFBundleIdentifier'), r'$(PRODUCT_BUNDLE_IDENTIFIER)');
      expect(
        plist.findAllElements('key').map((e) => e.innerText),
        contains('UIApplicationSceneManifest'),
      );
      for (final mode in ['Debug', 'Profile', 'Release']) {
        final xcconfig = files['ios/Flutter/$mode-$flavor.xcconfig']!;
        expect(xcconfig, contains('#include "Generated.xcconfig"'));
        expect(
          xcconfig,
          contains('Pods-Runner.${mode.toLowerCase()}-$flavor.xcconfig'),
        );
        expect(
          xcconfig,
          contains(
            'ANTSF_BUNDLE_ID = com.example.sample_app${flavor == 'dev' ? '.dev' : ''}',
          ),
        );
        expect(xcconfig, contains('ANTSF_APP_ICON = AppIcon-$flavor'));
        expect(xcconfig, contains('FLAVOR = $flavor'));
        final ref = RegExp('([A-F0-9]{24}) /\\* $mode-$flavor.xcconfig \\*/ =')
            .firstMatch(pbx);
        expect(ref, isNotNull);
        expect(
          pbx,
          contains(
            'baseConfigurationReference = ${ref!.group(1)} /* $mode-$flavor.xcconfig */;',
          ),
        );
      }
    }
    expect(pbx, contains(r'PRODUCT_BUNDLE_IDENTIFIER = "$(ANTSF_BUNDLE_ID)";'));
    expect(
      pbx,
      contains(r'CURRENT_PROJECT_VERSION = "$(ANTSF_IOS_BUILD_NUMBER)";'),
    );
    expect(pbx, contains('INFOPLIST_FILE = "Runner/Info-dev.plist";'));
    expect(pbx, isNot(contains('-b51')));
    final podfile = files['ios/Podfile']!;
    for (final mode in ['Debug', 'Profile', 'Release']) {
      expect(
        podfile,
        contains("'$mode-dev' => :${mode == 'Debug' ? 'debug' : 'release'}"),
      );
    }
    expect(podfile, contains('flutter_install_all_ios_pods'));
  });
}
