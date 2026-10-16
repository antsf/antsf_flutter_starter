import 'dart:io';

import 'package:xml/xml.dart';

/// Renders managed Android files without changing the Flutter-created project.
Map<String, String> renderAndroid(
  Map<String, dynamic> config,
  Directory project,
) {
  final flavors = config['flavors'] as Map<String, dynamic>;
  final identity = config['project'] as Map<String, dynamic>;
  var gradle = File('${project.path}/android/app/build.gradle.kts')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  // Gradle exposes a `java` extension that shadows qualified Java type names.
  // Import types before the plugins block and use their simple names instead.
  final imports = [
    'import java.io.File',
    'import java.util.Properties',
  ].where((line) => !gradle.split('\n').contains(line)).join('\n');
  if (imports.isNotEmpty) gradle = '$imports\n$gradle';
  gradle = gradle.replaceAll(
    RegExp(r'// BEGIN ANTSF SIGNING\n.*?// END ANTSF SIGNING\n', dotAll: true),
    '',
  );
  gradle = gradle.replaceAll(
    RegExp(r'\n// BEGIN ANTSF GUARD\n.*?// END ANTSF GUARD\n', dotAll: true),
    '',
  );
  gradle = gradle.replaceAll(
    RegExp(r'// BEGIN ANTSF FLAVORS\n.*?// END ANTSF FLAVORS', dotAll: true),
    'buildTypes { release {} }',
  );
  final flavorBlocks = StringBuffer(
    '    flavorDimensions += "app"\n    productFlavors {\n',
  );
  for (final entry in flavors.entries) {
    final flavor = entry.value as Map<String, dynamic>;
    final android = flavor['android'] as Map<String, dynamic>;
    final code = android['versionCode'];
    final version = android['versionName'];
    final suffix = android['versionNameSuffix'];
    if (code is! int || code < 1 || version is! String || suffix is! String) {
      throw FormatException(
        'Flavor ${entry.key} needs its own Android versionName, positive versionCode, and versionNameSuffix.',
      );
    }
    flavorBlocks.writeln('        create(${_kotlin(entry.key)}) {');
    flavorBlocks.writeln('            dimension = "app"');
    flavorBlocks.writeln(
      '            applicationId = ${_kotlin(identity['applicationId'] as String)}',
    );
    flavorBlocks.writeln(
      '            applicationIdSuffix = ${_kotlin(flavor['applicationIdSuffix'] as String)}',
    );
    flavorBlocks.writeln('            versionCode = $code');
    flavorBlocks.writeln('            versionName = ${_kotlin(version)}');
    flavorBlocks.writeln(
      '            versionNameSuffix = ${_kotlin(suffix.replaceAll('{build}', '$code'))}',
    );
    flavorBlocks.writeln(
      entry.key == 'prod'
          ? '            signingConfig = signingConfigs.findByName("antsfProdRelease")'
          : '            signingConfig = signingConfigs.getByName("debug")',
    );
    flavorBlocks.writeln('        }');
  }
  flavorBlocks.writeln('    }');
  gradle = gradle.replaceAll(
    RegExp(
      r'^\s*version(?:Code|Name)\s*=\s*flutter\.version(?:Code|Name)\s*$',
      multiLine: true,
    ),
    '',
  );
  gradle = _replaceBlock(
    gradle,
    'buildTypes',
    '// BEGIN ANTSF FLAVORS\n$_signingConfigs\n$flavorBlocks\n    buildTypes {\n        release {\n            signingConfig = null\n        }\n    }\n    // END ANTSF FLAVORS',
  );
  gradle = gradle.replaceFirst(
    RegExp(r'\bandroid\s*\{'),
    '// BEGIN ANTSF SIGNING\n${_signingProperties.trim()}\n// END ANTSF SIGNING\nandroid {',
  );
  gradle =
      '$gradle\n// BEGIN ANTSF GUARD\n${_nativeGuard(flavors.keys).trim()}\n// END ANTSF GUARD\n';
  final manifest = XmlDocument.parse(
    File('${project.path}/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync(),
  );
  final application = manifest.rootElement.getElement('application')!;
  application.setAttribute('android:label', '@string/app_name');
  application.setAttribute('android:icon', '@mipmap/ic_launcher');
  application.setAttribute('android:usesCleartextTraffic', 'false');
  application.setAttribute(
    'android:networkSecurityConfig',
    '@xml/antsf_network_security_config',
  );
  if (!manifest.rootElement
      .findElements('uses-permission')
      .any(
        (e) => e.getAttribute('android:name') == 'android.permission.INTERNET',
      )) {
    manifest.rootElement.children.insert(
      0,
      XmlElement(XmlName('uses-permission'), [
        XmlAttribute(XmlName('name', 'android'), 'android.permission.INTERNET'),
      ]),
    );
  }
  final result = <String, String>{
    'android/app/build.gradle.kts': gradle,
    'android/app/src/main/AndroidManifest.xml':
        '${manifest.toXmlString(pretty: true)}\n',
  };
  for (final entry in flavors.entries) {
    final flavor = entry.value as Map<String, dynamic>;
    final resources = XmlElement(XmlName('resources'), [], [
      XmlElement(
        XmlName('string'),
        [XmlAttribute(XmlName('name'), 'app_name')],
        [XmlText(_androidString(flavor['displayName'] as String))],
      ),
    ]);
    result['android/app/src/${entry.key}/res/values/strings.xml'] =
        '${resources.toXmlString(pretty: true)}\n';
    result['android/app/src/${entry.key}/res/xml/antsf_network_security_config.xml'] =
        _networkPolicy(entry.key, flavor);
    result['android/app/src/${entry.key}/AndroidManifest.xml'] =
        _flavorManifest(flavor);
  }
  return result;
}

String _kotlin(String value) =>
    '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$').replaceAll('\n', r'\n').replaceAll('\r', r'\r')}"';

String _androidString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll('@', r'\@')
    .replaceAll('?', r'\?');

String _networkPolicy(String name, Map<String, dynamic> flavor) {
  final api = Uri.tryParse(flavor['apiBaseUrl'] as String);
  final localHttp = flavor['allowLocalHttp'] == true;
  if (api == null ||
      api.host.isEmpty ||
      (api.scheme != 'https' &&
          !(name == 'dev' && localHttp && api.scheme == 'http')) ||
      (name != 'dev' && localHttp)) {
    throw FormatException(
      'Flavor $name requires HTTPS; HTTP exceptions require explicit dev opt-in.',
    );
  }
  final policy = XmlElement(XmlName('network-security-config'), [], [
    XmlElement(XmlName('base-config'), [
      XmlAttribute(XmlName('cleartextTrafficPermitted'), 'false'),
    ]),
    if (name == 'dev' && localHttp && api.scheme == 'http')
      XmlElement(
        XmlName('domain-config'),
        [XmlAttribute(XmlName('cleartextTrafficPermitted'), 'true')],
        [
          XmlElement(
            XmlName('domain'),
            [XmlAttribute(XmlName('includeSubdomains'), 'false')],
            [XmlText(api.host)],
          ),
        ],
      ),
  ]);
  return '${policy.toXmlString(pretty: true)}\n';
}

String _flavorManifest(Map<String, dynamic> flavor) {
  final manifest = XmlElement(XmlName('manifest'), [
    XmlAttribute(
      XmlName('android', 'xmlns'),
      'http://schemas.android.com/apk/res/android',
    ),
  ]);
  final links = flavor['links'] as Map<String, dynamic>?;
  if (links != null) {
    final activity = XmlElement(XmlName('activity'), [
      XmlAttribute(XmlName('name', 'android'), '.MainActivity'),
    ]);
    for (final path in links['paths'] as List) {
      activity.children.add(
        XmlElement(
          XmlName('intent-filter'),
          [XmlAttribute(XmlName('autoVerify', 'android'), 'true')],
          [
            XmlElement(XmlName('action'), [
              XmlAttribute(
                XmlName('name', 'android'),
                'android.intent.action.VIEW',
              ),
            ]),
            XmlElement(XmlName('category'), [
              XmlAttribute(
                XmlName('name', 'android'),
                'android.intent.category.DEFAULT',
              ),
            ]),
            XmlElement(XmlName('category'), [
              XmlAttribute(
                XmlName('name', 'android'),
                'android.intent.category.BROWSABLE',
              ),
            ]),
            XmlElement(XmlName('data'), [
              XmlAttribute(XmlName('scheme', 'android'), 'https'),
              XmlAttribute(XmlName('host', 'android'), links['host'] as String),
              XmlAttribute(XmlName('pathPrefix', 'android'), path as String),
            ]),
          ],
        ),
      );
    }
    manifest.children.add(XmlElement(XmlName('application'), [], [activity]));
  }
  return '${manifest.toXmlString(pretty: true)}\n';
}

const _signingProperties = r'''
// Keep configured version codes exact, including Flutter split-per-ABI APKs.
extra["force-version-code-ignoring-abi"] = "true"
// Supply secrets outside the generated project: Gradle properties, environment,
// or an external .properties file selected explicitly by path.
val antsfSigningProperties = Properties()
val antsfSigningPropertiesPath = providers.gradleProperty("antsf.signingProperties").orNull
    ?: System.getenv("ANTSF_ANDROID_SIGNING_PROPERTIES")
if (!antsfSigningPropertiesPath.isNullOrBlank()) {
    val signingPropertiesFile = file(antsfSigningPropertiesPath)
    if (!signingPropertiesFile.isFile) {
        throw GradleException("External Android signing properties file is missing.")
    }
    signingPropertiesFile.inputStream().use { antsfSigningProperties.load(it) }
}
fun antsfSigningValue(key: String, environment: String): String? =
    providers.gradleProperty("antsf.android.$key").orNull
        ?: System.getenv(environment)
        ?: antsfSigningProperties.getProperty(key)
val antsfStoreFile = antsfSigningValue("storeFile", "ANTSF_ANDROID_STORE_FILE")
val antsfStorePassword = antsfSigningValue("storePassword", "ANTSF_ANDROID_STORE_PASSWORD")
val antsfKeyAlias = antsfSigningValue("keyAlias", "ANTSF_ANDROID_KEY_ALIAS")
val antsfKeyPassword = antsfSigningValue("keyPassword", "ANTSF_ANDROID_KEY_PASSWORD")
val antsfSigningReady = listOf(antsfStoreFile, antsfStorePassword, antsfKeyAlias, antsfKeyPassword)
    .all { !it.isNullOrBlank() }
''';

const _signingConfigs = r'''
    signingConfigs {
        if (antsfSigningReady) {
            create("antsfProdRelease") {
                storeFile = file(antsfStoreFile!!)
                storePassword = antsfStorePassword
                keyAlias = antsfKeyAlias
                keyPassword = antsfKeyPassword
            }
        }
    }
''';

String _nativeGuard(Iterable<String> flavors) =>
    r'''
// Evaluate the final task graph before any compilation or packaging can run.
// A generic assemble/bundle invocation must not implicitly select a flavor.
gradle.taskGraph.whenReady {
    val androidBuildRequested = allTasks.any {
        it.project == project && Regex("(?i).*(assemble|bundle|install|compile|package|pre.*build).*")
            .matches(it.name)
    }
    if (androidBuildRequested) {
        val requestedTasks = gradle.startParameter.taskNames.map { it.substringAfterLast(':') }
        val knownFlavors = listOf(__FLAVORS__)
        val selectedFlavors = knownFlavors.filter { flavor ->
            requestedTasks.any {
                Regex("(?i).*$flavor(Debug|Profile|Release).*").matches(it)
            }
        }
        if (selectedFlavors.size != 1) {
            throw GradleException("An explicit --flavor is required: build exactly one configured flavor (for example, flutter build apk --flavor dev).")
        }
        val selectedFlavor = selectedFlavors.single()
        // Reject aggregate tasks even if an explicit task was also supplied.
        val graphFlavors = knownFlavors.filter { flavor ->
            allTasks.any { it.project == project && Regex("(?i).*$flavor(Debug|Profile|Release).*").matches(it.name) }
        }
        if (graphFlavors.any { it != selectedFlavor }) {
            throw GradleException("Build exactly one explicit --flavor; aggregate multi-flavor tasks are not supported.")
        }
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (!localPropertiesFile.isFile) throw GradleException("Missing android/local.properties; run flutter pub get first.")
        localPropertiesFile.inputStream().use { localProperties.load(it) }
        val flutterSdk = localProperties.getProperty("flutter.sdk")
            ?: throw GradleException("Missing flutter.sdk in android/local.properties.")
        val dartExecutable = File(flutterSdk, "bin/cache/dart-sdk/bin/" +
            if (System.getProperty("os.name").startsWith("Windows", ignoreCase = true)) "dart.exe" else "dart")
        if (!dartExecutable.isFile) throw GradleException("Flutter SDK Dart executable is missing; check flutter.sdk.")
        val appRoot = rootProject.projectDir.parentFile
        val guardScript = File(appRoot, "tool/flavor_guard.dart")
        if (!guardScript.isFile) throw GradleException("Missing tool/flavor_guard.dart; restore generated files with antsf_starter sync.")
        val guardProcess = ProcessBuilder(
            dartExecutable.absolutePath, guardScript.absolutePath,
            "--flavor=$selectedFlavor", "--platform=android",
            "--build-name=${flutter.versionName}",
            "--build-number=${flutter.versionCode}",
            "--dart-defines=${project.findProperty("dart-defines") ?: ""}"
        ).directory(appRoot).redirectErrorStream(true).start()
        val guardOutput = guardProcess.inputStream.bufferedReader().use { it.readText() }.trim()
        if (guardProcess.waitFor() != 0) throw GradleException("Native flavor guard failed: $guardOutput")
        val prodReleaseRequested = allTasks.any {
            it.project == project && it.name.contains("ProdRelease", ignoreCase = true)
        }
        if (selectedFlavor == "prod" && prodReleaseRequested) {
            if (!antsfSigningReady || !file(antsfStoreFile!!).isFile) {
                throw GradleException("Production release signing is not configured. Supply antsf.android.storeFile/storePassword/keyAlias/keyPassword Gradle properties, ANTSF_ANDROID_STORE_FILE/STORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD environment variables, or an external properties file via ANTSF_ANDROID_SIGNING_PROPERTIES. Debug signing is never used for prod release.")
            }
        }
    }
}
'''
        .replaceAll('__FLAVORS__', flavors.map(_kotlin).join(', '));

String _replaceBlock(String source, String name, String replacement) {
  final match = RegExp('\\b$name\\s*\\{').firstMatch(source);
  if (match == null) {
    throw FormatException(
      'Unsupported Flutter Android template: missing $name block.',
    );
  }
  var depth = 1;
  var end = match.end;
  while (end < source.length && depth > 0) {
    if (source[end] == '{') depth++;
    if (source[end] == '}') depth--;
    end++;
  }
  if (depth != 0) {
    throw FormatException('Unbalanced $name block in Android template.');
  }
  return source.replaceRange(match.start, end, replacement.trimLeft());
}
