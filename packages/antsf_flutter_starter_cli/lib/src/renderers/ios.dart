import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'ios_pods.dart';

/// Renders managed iOS text files from a Flutter template without writing files.
///
/// The original build configurations remain a stable cloning source on sync,
/// but are deliberately unusable: every Runner build must pass the flavor
/// guard. Signing credentials and launcher icon assets are managed elsewhere.
Map<String, String> renderIos(Map<String, dynamic> config, Directory project) {
  String read(String path) =>
      File(p.join(project.path, path))
          .readAsStringSync()
          .replaceAll('\r\n', '\n');
  final flavors = (config['flavors'] as Map).keys.cast<String>().toList()
    ..sort();
  if (!flavors.contains('dev') ||
      !flavors.contains('prod') ||
      flavors.any((name) => !['dev', 'stg', 'prod'].contains(name))) {
    throw const FormatException(
      'Expected dev, prod and optional stg iOS flavors.',
    );
  }
  var pbx = _removeGenerated(read('ios/Runner.xcodeproj/project.pbxproj'));
  var schemeTemplate = read(
    'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme',
  );
  if (!schemeTemplate.contains('<LaunchAction')) {
    final previous = XmlDocument.parse(
      read('ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme'),
    );
    for (final element in previous.descendants.whereType<XmlElement>()) {
      final mode = element.getAttribute('buildConfiguration');
      if (mode != null) {
        element.setAttribute('buildConfiguration', mode.split('-').first);
      }
      final script = element.getAttribute('scriptText');
      if (script != null && script.contains('xcode_backend.sh')) {
        element.setAttribute(
          'scriptText',
          script.substring(script.indexOf('/bin/sh')),
        );
      }
    }
    schemeTemplate = previous.toXmlString(pretty: true);
  }
  final objects = _objects(pbx);
  final configurations = objects
      .where((o) => o.type == 'XCBuildConfiguration')
      .toList();
  final lists = objects.where((o) => o.type == 'XCConfigurationList').toList();
  final appConfigurations = configurations
      .where((o) => o.text.contains('INFOPLIST_FILE = Runner/Info.plist;'))
      .toList();
  if (configurations.length != 9 ||
      lists.length != 3 ||
      appConfigurations.length != 3 ||
      appConfigurations.any(
        (o) => !o.text.contains('baseConfigurationReference = '),
      ) ||
      !schemeTemplate.contains('xcode_backend.sh') ||
      [
        'PBXFileReference',
        'PBXShellScriptBuildPhase',
        'XCBuildConfiguration',
      ].any((section) => !pbx.contains('/* End $section section */'))) {
    throw StateError(
      'Unsupported Flutter iOS template: expected Runner, RunnerTests and Flutter build configuration sections.',
    );
  }
  final clones = StringBuffer();
  final xcconfigRefs = StringBuffer();
  final result = <String, String>{};
  final plistTemplate = read('ios/Runner/Info.plist');
  for (final flavor in flavors) {
    final values = (config['flavors'] as Map)[flavor] as Map;
    final api = Uri.parse(values['apiBaseUrl'] as String);
    if ((flavor != 'dev' && values['allowLocalHttp'] == true) ||
        (api.scheme != 'https' &&
            !(flavor == 'dev' &&
                values['allowLocalHttp'] == true &&
                api.scheme == 'http' &&
                _localHost(api.host)))) {
      throw FormatException(
        '$flavor: HTTPS required except explicitly enabled local dev HTTP.',
      );
    }
    final ios = values['ios'] as Map;
    final bundleId =
        '${(config['project'] as Map)['applicationId']}${values['applicationIdSuffix']}';
    final plist = XmlDocument.parse(plistTemplate);
    final dict = plist.rootElement.getElement('dict')!;
    _plistSet(
      dict,
      'CFBundleDisplayName',
      XmlElement(XmlName('string'), [], [
        XmlText(values['displayName'] as String),
      ]),
    );
    _plistSet(
      dict,
      'CFBundleShortVersionString',
      XmlElement(XmlName('string'), [], [
        XmlText(ios['versionName'] as String),
      ]),
    );
    _plistSet(
      dict,
      'CFBundleVersion',
      XmlElement(XmlName('string'), [], [
        XmlText(ios['buildNumber'].toString()),
      ]),
    );
    if (flavor == 'dev' &&
        values['allowLocalHttp'] == true &&
        api.scheme == 'http') {
      _plistSet(
        dict,
        'NSAppTransportSecurity',
        _plistDict({
          'NSAllowsLocalNetworking': XmlElement(XmlName('true')),
          'NSExceptionDomains': _plistDict({
            api.host: _plistDict({
              'NSExceptionAllowsInsecureHTTPLoads': XmlElement(XmlName('true')),
            }),
          }),
        }),
      );
      _plistSet(
        dict,
        'NSLocalNetworkUsageDescription',
        XmlElement(XmlName('string'), [], [
          XmlText(
            'Connect to the explicitly configured local development API.',
          ),
        ]),
      );
    }
    final links = values['links'] as Map?;
    if (links != null) {
      final entitlements = XmlDocument.parse(
        '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict/></plist>',
      );
      _plistSet(
        entitlements.rootElement.getElement('dict')!,
        'com.apple.developer.associated-domains',
        XmlElement(XmlName('array'), [], [
          XmlElement(XmlName('string'), [], [
            XmlText('applinks:${links['host']}'),
          ]),
        ]),
      );
      result['ios/Runner/Runner-$flavor.entitlements'] =
          '${entitlements.toXmlString(pretty: true)}\n';
    }
    result['ios/Runner/Info-$flavor.plist'] =
        '${plist.toXmlString(pretty: true)}\n';
    for (final mode in ['Debug', 'Profile', 'Release']) {
      final filename = '$mode-$flavor.xcconfig';
      xcconfigRefs.writeln(
        '\t\t${_id(filename)} /* $filename */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Flutter/$filename; sourceTree = SOURCE_ROOT; };',
      );
      result['ios/Flutter/$filename'] =
          '#include? "../Pods/Target Support Files/Pods-Runner/Pods-Runner.${mode.toLowerCase()}-$flavor.xcconfig"\n'
          '#include "Generated.xcconfig"\n'
          'FLAVOR = $flavor\n'
          'ANTSF_BUNDLE_ID = $bundleId\n'
          'ANTSF_APP_ICON = AppIcon-$flavor\n'
          'ANTSF_IOS_VERSION = ${ios['versionName']}\n'
          'ANTSF_IOS_BUILD_NUMBER = ${ios['buildNumber']}\n';
    }
  }
  for (final original in configurations) {
    for (final flavor in flavors) {
      final name = _configurationName(original.text);
      final id = _id('${original.id}:$flavor');
      var clone = original.text
          .replaceFirst(original.id, id)
          .replaceFirst('/* $name */', '/* $name-$flavor */')
          .replaceFirst('name = $name;', 'name = "$name-$flavor";');
      if (original.text.contains('INFOPLIST_FILE = Runner/Info.plist;')) {
        clone = clone.replaceFirst(
          RegExp(r'baseConfigurationReference = [^;]+;'),
          'baseConfigurationReference = ${_id('$name-$flavor.xcconfig')} /* $name-$flavor.xcconfig */;',
        );
        clone = _setting(
          clone,
          'PRODUCT_BUNDLE_IDENTIFIER',
          r'"$(ANTSF_BUNDLE_ID)"',
        );
        clone = _setting(
          clone,
          'ASSETCATALOG_COMPILER_APPICON_NAME',
          r'"$(ANTSF_APP_ICON)"',
        );
        clone = _setting(
          clone,
          'CURRENT_PROJECT_VERSION',
          r'"$(ANTSF_IOS_BUILD_NUMBER)"',
        );
        clone = _setting(clone, 'MARKETING_VERSION', r'"$(ANTSF_IOS_VERSION)"');
        clone = _setting(
          clone,
          'INFOPLIST_FILE',
          '"Runner/Info-$flavor.plist"',
        );
        if (((config['flavors'] as Map)[flavor] as Map)['links'] != null) {
          clone = _setting(
            clone,
            'CODE_SIGN_ENTITLEMENTS',
            '"Runner/Runner-$flavor.entitlements"',
          );
        }
      }
      clones.writeln(clone);
    }
  }
  pbx = pbx.replaceFirst(
    '/* End XCBuildConfiguration section */',
    '$clones/* End XCBuildConfiguration section */',
  );
  for (final list in lists) {
    final entries = RegExp(
      r'buildConfigurations = \((.*?)\);',
      dotAll: true,
    ).firstMatch(list.text)!;
    final refs = RegExp(r'([A-F0-9]{24}) /\* (Debug|Profile|Release) \*/')
        .allMatches(entries.group(1)!)
        .toList();
    if (refs.length != 3) {
      throw StateError('Unsupported Flutter iOS configuration list.');
    }
    final added = StringBuffer(entries.group(1)!);
    for (final flavor in flavors) {
      for (final ref in refs) {
        added.writeln(
          '\t\t\t\t${_id('${ref.group(1)}:$flavor')} /* ${ref.group(2)}-$flavor */,',
        );
      }
    }
    final replacement = list.text.replaceRange(
      entries.start,
      entries.end,
      'buildConfigurations = (${added.toString()}\t\t\t);',
    );
    pbx = pbx.replaceFirst(list.text, replacement);
  }
  pbx = pbx.replaceFirst(
    '/* End PBXFileReference section */',
    '$xcconfigRefs/* End PBXFileReference section */',
  );
  final runner = objects.singleWhere(
    (o) => o.type == 'PBXNativeTarget' && o.text.contains('name = Runner;'),
  );
  final guardId = _id('guard');
  pbx = pbx.replaceFirst(
    runner.text,
    runner.text.replaceFirst(
      'buildPhases = (',
      'buildPhases = (\n\t\t\t\t$guardId /* Antsf Flavor Guard */,',
    ),
  );
  pbx = pbx.replaceFirst('/* End PBXShellScriptBuildPhase section */', '''
\t\t$guardId /* Antsf Flavor Guard */ = {
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\tinputPaths = ();
\t\t\tname = "Antsf Flavor Guard";
\t\t\toutputPaths = ();
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = ${jsonEncode(_guard(flavors))};
\t\t};
/* End PBXShellScriptBuildPhase section */''');
  result['ios/Runner.xcodeproj/project.pbxproj'] = pbx;
  result['ios/Podfile'] = _podfile(flavors);
  result['tool/ios_pods_integration.dart'] = renderIosPodsIntegration();
  final disabled = XmlDocument.parse(schemeTemplate);
  disabled.rootElement.children.removeWhere(
    (node) => node is XmlElement && node.name.local != 'BuildAction',
  );
  for (final action in disabled.findAllElements('ActionContent')) {
    action.setAttribute('title', 'Select an explicit flavor');
    action.setAttribute(
      'scriptText',
      'echo "error: Select an explicit flavor (${flavors.join(', ')}) using --flavor or its shared Xcode scheme." >&2\nexit 1\n',
    );
  }
  result['ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme'] =
      '${disabled.toXmlString(pretty: true)}\n';
  for (final flavor in flavors) {
    final scheme = XmlDocument.parse(schemeTemplate);
    for (final element in scheme.descendants.whereType<XmlElement>()) {
      final mode = element.getAttribute('buildConfiguration');
      if (mode != null) {
        element.setAttribute('buildConfiguration', '$mode-$flavor');
      }
    }
    for (final action in scheme.findAllElements('ActionContent')) {
      final script = action.getAttribute('scriptText');
      if (script != null && script.contains('xcode_backend.sh')) {
        action.setAttribute('scriptText', '${_guard([flavor])}\n$script');
      }
    }
    result['ios/Runner.xcodeproj/xcshareddata/xcschemes/$flavor.xcscheme'] =
        '${scheme.toXmlString(pretty: true)}\n';
  }
  return result;
}

// Only remove deterministic objects produced by this renderer. The original
// template configurations remain the cloning source on every sync.
String _removeGenerated(String pbx) {
  final generated = <String>{_id('guard')};
  for (final object in _objects(pbx)) {
    final match = RegExp(r'name = "(Debug|Profile|Release)-(dev|stg|prod)";')
        .firstMatch(object.text);
    if (object.id == _id('guard') ||
        (object.type == 'XCBuildConfiguration' && match != null)) {
      generated.add(object.id);
      pbx = pbx.replaceFirst('${object.text}\n', '');
    }
  }
  for (final flavor in ['dev', 'stg', 'prod']) {
    for (final mode in ['Debug', 'Profile', 'Release']) {
      final id = _id('$mode-$flavor.xcconfig');
      pbx = pbx.replaceAll(
        RegExp('^\\t\\t$id /\\* [^\\n]*\\n', multiLine: true),
        '',
      );
    }
  }
  for (final id in generated) {
    pbx = pbx.replaceAll(
      RegExp('^[\\t ]*$id /\\* [^\\n]*? \\*/,\\n', multiLine: true),
      '',
    );
  }
  return pbx;
}

String _id(String seed) => sha256
    .convert(utf8.encode('antsf-ios:$seed'))
    .toString()
    .substring(0, 24)
    .toUpperCase();
String _configurationName(String text) {
  final match = RegExp(r'\n\s*name = (Debug|Profile|Release);')
      .firstMatch(text);
  if (match == null) throw StateError('Unsupported Flutter iOS configuration.');
  return match.group(1)!;
}

List<_Object> _objects(String pbx) => RegExp(
  r'^\t\t([A-F0-9]{24})(?: /\* [^\n]*? \*/)? = \{\n.*?^\t\t\};',
  multiLine: true,
  dotAll: true,
).allMatches(pbx).map((m) => _Object(m.group(1)!, m.group(0)!)).toList();

String _setting(String object, String key, String value) {
  final pattern = RegExp('\\b$key = [^;]+;');
  if (pattern.hasMatch(object)) {
    return object.replaceFirst(pattern, '$key = $value;');
  }
  return object.replaceFirst(
    'buildSettings = {',
    'buildSettings = {\n\t\t\t\t$key = $value;',
  );
}

bool _localHost(String host) =>
    host == 'localhost' ||
    host == '::1' ||
    host == '[::1]' ||
    host.startsWith('127.') ||
    host.startsWith('10.') ||
    host.startsWith('192.168.') ||
    host.endsWith('.local') ||
    RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(host);

String _guard(List<String> flavors) =>
    '''
set -eu
case "\${CONFIGURATION:-}" in
${[for (final flavor in flavors) '  Debug-$flavor|Profile-$flavor|Release-$flavor) antsf_flavor=$flavor ;;'].join('\n')}
  *) echo "error: Select an explicit flavor (${flavors.join(', ')}) using --flavor or its shared Xcode scheme." >&2; exit 1 ;;
esac
if [ -n "\${FLAVOR:-}" ] && [ "\$FLAVOR" != "\$antsf_flavor" ]; then
  echo "error: FLAVOR conflicts with the selected explicit flavor \$antsf_flavor." >&2
  exit 1
fi
cd "\$SRCROOT/.."
"\$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" run tool/flavor_guard.dart "--flavor=\$antsf_flavor" --platform=ios "--build-name=\${FLUTTER_BUILD_NAME:-}" "--build-number=\${FLUTTER_BUILD_NUMBER:-}" "--dart-defines=\${DART_DEFINES:-}"
''';

XmlElement _plistDict(Map<String, XmlElement> entries) =>
    XmlElement(XmlName('dict'), [], [
      for (final entry in entries.entries) ...[
        XmlElement(XmlName('key'), [], [XmlText(entry.key)]),
        entry.value,
      ],
    ]);

void _plistSet(XmlElement dict, String key, XmlElement value) {
  final keys = dict.findElements('key').where((e) => e.innerText == key);
  if (keys.isNotEmpty) {
    final oldValue = keys.single.nextElementSibling!;
    dict.children[dict.children.indexOf(oldValue)] = value;
  } else {
    dict.children.addAll([
      XmlElement(XmlName('key'), [], [XmlText(key)]),
      value,
    ]);
  }
}

String _podfile(List<String> flavors) =>
    '''
platform :ios, '13.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
${[
      for (final flavor in flavors)
        for (final mode in ['Debug', 'Profile', 'Release']) "  '$mode-$flavor' => :${mode == 'Debug' ? 'debug' : 'release'},",
    ].join('\n')}
}
def flutter_root
  settings = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  raise "Run flutter pub get before pod install" unless File.exist?(settings)
  File.foreach(settings) do |line|
    matches = line.match(/FLUTTER_ROOT\\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT missing in Generated.xcconfig"
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
def antsf_pods_integration(operation)
  root = File.expand_path('..', __dir__)
  dart = File.join(flutter_root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart')
  ok = system(dart, 'run', 'tool/ios_pods_integration.dart', operation, chdir: root)
  raise 'Managed CocoaPods integration failed; inspect diagnostics and recover before retrying.' unless ok
end
pre_integrate do |_installer|
  antsf_pods_integration('begin')
end
post_integrate do |_installer|
  antsf_pods_integration('complete')
end
target 'Runner' do
  use_frameworks!
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
  end
end
''';

class _Object {
  _Object(this.id, this.text);
  final String id;
  final String text;
  String? get type => RegExp(r'\bisa = (\w+);').firstMatch(text)?.group(1);
}
