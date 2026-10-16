import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/renderers/android.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

Map<String, dynamic> fixture() => {
  'project': {
    'name': 'sample_app',
    'applicationId': 'com.example.sample_app',
    'displayName': 'Sample',
  },
  'flavors': {
    for (final name in ['dev', 'prod'])
      name: {
        'applicationIdSuffix': name == 'prod' ? '' : '.$name',
        'displayName': name == 'prod' ? 'Sample' : '[DEV] Sample',
        'apiBaseUrl': 'https://$name.example.net',
        'allowLocalHttp': false,
        'android': {
          'versionName': name == 'dev' ? '1.2.3' : '4.5.6',
          'versionCode': name == 'dev' ? 51 : 8,
          'versionNameSuffix': name == 'dev' ? '-b{build}' : '',
        },
        'links': null,
      },
  },
};

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('android_renderer_');
    final gradle = File('${project.path}/android/app/build.gradle.kts');
    gradle.parent.createSync(recursive: true);
    gradle.writeAsStringSync('''
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}
android {
    namespace = "com.example.sample_app"
    compileSdk = flutter.compileSdkVersion
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.example.sample_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
flutter {
    source = "../.."
}
''');
    final manifest = File(
      '${project.path}/android/app/src/main/AndroidManifest.xml',
    );
    manifest.parent.createSync(recursive: true);
    manifest.writeAsStringSync(r'''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="sample_app" android:name="${applicationName}" android:icon="@mipmap/ic_launcher">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
    </activity>
    <meta-data android:name="flutterEmbedding" android:value="2"/>
  </application>
</manifest>
''');
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('render is pure and idempotent when synchronizing managed output', () {
    final config = fixture();
    final before = File('${project.path}/android/app/build.gradle.kts')
        .readAsStringSync();
    final first = renderAndroid(config, project);
    expect(
      File('${project.path}/android/app/build.gradle.kts').readAsStringSync(),
      before,
    );
    for (final entry in first.entries) {
      final file = File('${project.path}/${entry.key}');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    expect(renderAndroid(config, project), first);
    config['flavors']['dev']['android']['versionCode'] = 52;
    final changed = renderAndroid(
      config,
      project,
    )['android/app/build.gradle.kts']!;
    expect(RegExp('create\\("dev"\\)').allMatches(changed), hasLength(1));
    expect(changed, contains('versionCode = 52'));
    expect(changed, isNot(contains('versionCode = 51')));
  });

  test('stg is independent, HTTPS-only, and never generated implicitly', () {
    final config = fixture();
    expect(
      renderAndroid(config, project).keys.any((key) => key.contains('/stg/')),
      isFalse,
    );
    config['flavors']['stg'] = {
      ...config['flavors']['dev'] as Map<String, dynamic>,
      'applicationIdSuffix': '.stg',
      'displayName': '[STG] Sample',
      'apiBaseUrl': 'https://stg.example.net',
      'android': {
        'versionName': '2.0.0',
        'versionCode': 99,
        'versionNameSuffix': '-b{build}',
      },
    };
    final output = renderAndroid(config, project);
    expect(output['android/app/build.gradle.kts'], contains('create("stg")'));
    expect(
      output['android/app/build.gradle.kts'],
      contains('versionCode = 99'),
    );
    expect(
      output['android/app/src/stg/res/values/strings.xml'],
      contains('[STG] Sample'),
    );
    config['flavors']['stg']['allowLocalHttp'] = true;
    expect(
      () => renderAndroid(config, project),
      throwsA(isA<FormatException>()),
    );
  });

  test('escapes display names for XML and Android resource compilation', () {
    final config = fixture();
    config['flavors']['dev']['displayName'] = 'Bob\'s "R&D"';
    final strings = renderAndroid(
      config,
      project,
    )['android/app/src/dev/res/values/strings.xml']!;
    final value = XmlDocument.parse(strings)
        .findAllElements('string')
        .single
        .innerText;
    expect(value, r'''Bob\'s \"R&D\"''');
    expect(strings, contains('&amp;'));
  });

  test(
    'uses the explicit application ID and preserves CRLF template toolchains',
    () {
      final config = fixture();
      config['project']['applicationId'] = 'net.acme.customapp';
      final gradleFile = File('${project.path}/android/app/build.gradle.kts');
      gradleFile.writeAsStringSync(
        gradleFile.readAsStringSync().replaceAll('\n', '\r\n'),
      );
      final gradle = renderAndroid(
        config,
        project,
      )['android/app/build.gradle.kts']!;
      expect(gradle, contains('applicationId = "net.acme.customapp"'));
      expect(gradle, contains('namespace = "com.example.sample_app"'));
      expect(gradle, contains('JavaVersion.VERSION_17'));
      expect(gradle, isNot(contains('versionCode = flutter.versionCode')));
    },
  );

  test(
    'reads a real fresh Flutter template without modifying it',
    () {
      final templatePath = Platform.environment['ANTSF_ANDROID_TEMPLATE'];
      if (templatePath == null) return;
      final template = Directory(templatePath);
      final gradleFile = File('$templatePath/android/app/build.gradle.kts');
      final manifestFile = File(
        '$templatePath/android/app/src/main/AndroidManifest.xml',
      );
      final beforeGradle = gradleFile.readAsStringSync();
      final beforeManifest = manifestFile.readAsStringSync();
      final output = renderAndroid(fixture(), template);
      expect(
        output['android/app/build.gradle.kts'],
        contains('JavaVersion.VERSION_17'),
      );
      expect(
        output['android/app/build.gradle.kts'],
        contains('JvmTarget.JVM_17'),
      );
      expect(
        output['android/app/build.gradle.kts'],
        contains('versionCode = 51'),
      );
      expect(
        output['android/app/build.gradle.kts'],
        isNot(contains('versionCode = flutter.versionCode')),
      );
      final main = XmlDocument.parse(
        output['android/app/src/main/AndroidManifest.xml']!,
      );
      expect(main.findAllElements('queries'), hasLength(1));
      expect(
        main.findAllElements('activity').single.getAttribute('android:name'),
        '.MainActivity',
      );
      expect(gradleFile.readAsStringSync(), beforeGradle);
      expect(manifestFile.readAsStringSync(), beforeManifest);
    },
    skip: Platform.environment['ANTSF_ANDROID_TEMPLATE'] == null
        ? 'Set ANTSF_ANDROID_TEMPLATE to a real flutter create project for template compatibility checking.'
        : false,
  );

  test('network policy denies HTTP by default for every flavor', () {
    final output = renderAndroid(fixture(), project);
    expect(
      output['android/app/src/main/AndroidManifest.xml'],
      contains('android:usesCleartextTraffic="false"'),
    );
    expect(
      output['android/app/src/main/AndroidManifest.xml'],
      contains('@xml/antsf_network_security_config'),
    );
    for (final flavor in ['dev', 'prod']) {
      final xml = XmlDocument.parse(
        output['android/app/src/$flavor/res/xml/antsf_network_security_config.xml']!,
      );
      expect(
        xml
            .findAllElements('base-config')
            .single
            .getAttribute('cleartextTrafficPermitted'),
        'false',
      );
      expect(xml.findAllElements('domain-config'), isEmpty);
    }
  });

  test('local HTTP is opt-in dev only and restricted to the exact API host', () {
    final config = fixture();
    config['flavors']['dev']['apiBaseUrl'] = 'http://10.0.2.2:8080/api';
    expect(
      () => renderAndroid(config, project),
      throwsA(isA<FormatException>()),
    );
    config['flavors']['dev']['allowLocalHttp'] = true;
    final output = renderAndroid(config, project);
    final xml = XmlDocument.parse(
      output['android/app/src/dev/res/xml/antsf_network_security_config.xml']!,
    );
    expect(
      xml
          .findAllElements('base-config')
          .single
          .getAttribute('cleartextTrafficPermitted'),
      'false',
    );
    expect(
      xml
          .findAllElements('domain-config')
          .single
          .getAttribute('cleartextTrafficPermitted'),
      'true',
    );
    expect(xml.findAllElements('domain').single.innerText, '10.0.2.2');
    expect(
      xml.findAllElements('domain').single.getAttribute('includeSubdomains'),
      'false',
    );
    expect(
      output['android/app/src/prod/res/xml/antsf_network_security_config.xml'],
      isNot(contains('10.0.2.2')),
    );
    config['flavors']['prod']['allowLocalHttp'] = true;
    expect(
      () => renderAndroid(config, project),
      throwsA(isA<FormatException>()),
    );
    config['flavors']['prod']['allowLocalHttp'] = false;
    config['flavors']['prod']['apiBaseUrl'] = 'http://prod.example.net';
    expect(
      () => renderAndroid(config, project),
      throwsA(isA<FormatException>()),
    );
  });

  test('links are disabled by default and enabled only in the selected flavor manifest', () {
    final config = fixture();
    final disabled = renderAndroid(config, project);
    expect(
      disabled.values.join(),
      isNot(contains('android.intent.category.BROWSABLE')),
    );
    config['flavors']['dev']['links'] = {
      'host': 'dev.example.net',
      'paths': ['/open', '/items'],
      'sha256CertFingerprints': <String>[],
    };
    final enabled = renderAndroid(config, project);
    final xml = XmlDocument.parse(
      enabled['android/app/src/dev/AndroidManifest.xml']!,
    );
    final filters = xml.findAllElements('intent-filter').toList();
    expect(filters, hasLength(2));
    for (final filter in filters) {
      expect(filter.getAttribute('android:autoVerify'), 'true');
      final data = filter.findElements('data').single;
      expect(data.getAttribute('android:scheme'), 'https');
      expect(data.getAttribute('android:host'), 'dev.example.net');
      expect(
        data.getAttribute('android:pathPrefix'),
        isIn(['/open', '/items']),
      );
    }
    expect(
      enabled['android/app/src/prod/AndroidManifest.xml'],
      isNot(contains('BROWSABLE')),
    );
    expect(
      enabled['android/app/src/main/AndroidManifest.xml'],
      isNot(contains('dev.example.net')),
    );
  });

  test(
    'requires one explicit flavor and invokes standalone guard before tasks',
    () {
      final gradle = renderAndroid(
        fixture(),
        project,
      )['android/app/build.gradle.kts']!;
      expect(gradle, contains('gradle.taskGraph.whenReady'));
      expect(gradle, contains('gradle.startParameter.taskNames'));
      expect(gradle, contains('selectedFlavors.size != 1'));
      expect(gradle, contains('explicit --flavor'));
      expect(gradle, isNot(contains('isDefault')));
      expect(gradle, contains('local.properties'));
      expect(gradle, contains('flutter.sdk'));
      expect(gradle, contains('bin/cache/dart-sdk/bin'));
      expect(gradle, contains('dart.exe'));
      expect(gradle, contains('ProcessBuilder('));
      expect(gradle, contains('tool/flavor_guard.dart'));
      expect(gradle, contains(r'"--flavor=$selectedFlavor"'));
      expect(gradle, contains('"--platform=android"'));
      expect(gradle, contains(r'"--build-name=${flutter.versionName}"'));
      expect(gradle, contains(r'"--build-number=${flutter.versionCode}"'));
      expect(
        gradle,
        contains(
          r'"--dart-defines=${project.findProperty("dart-defines") ?: ""}"',
        ),
      );
      expect(gradle, contains('.waitFor()'));
      expect(gradle, contains('guardProcess.waitFor() != 0'));
      expect(gradle, isNot(contains('cmd.exe')));
      expect(gradle, isNot(contains('sh -c')));
    },
  );

  test(
    'native guard failures retain their sanitized diagnostic in Gradle errors',
    () {
      final gradle = renderAndroid(
        fixture(),
        project,
      )['android/app/build.gradle.kts']!;
      expect(gradle, contains('.redirectErrorStream(true).start()'));
      expect(
        gradle,
        contains(
          'guardProcess.inputStream.bufferedReader().use { it.readText() }',
        ),
      );
      expect(
        gradle,
        contains(
          r'throw GradleException("Native flavor guard failed: $guardOutput")',
        ),
      );
      expect(gradle, isNot(contains('.inheritIO()')));
    },
  );

  test('Java types do not collide with the Gradle java extension', () {
    final gradle = renderAndroid(
      fixture(),
      project,
    )['android/app/build.gradle.kts']!;
    expect(
      gradle,
      startsWith('import java.io.File\nimport java.util.Properties\n'),
    );
    expect(gradle, contains('val antsfSigningProperties = Properties()'));
    expect(gradle, contains('val localProperties = Properties()'));
    expect(gradle, contains('val dartExecutable = File('));
    expect(gradle, contains('val guardScript = File('));
    expect(gradle, isNot(contains('java.util.Properties()')));
    expect(gradle, isNot(contains('java.io.File(')));
  });

  test('prod release requires external signing without debug fallback', () {
    final gradle = renderAndroid(
      fixture(),
      project,
    )['android/app/build.gradle.kts']!;
    expect(gradle, contains('ANTSF_ANDROID_STORE_FILE'));
    expect(gradle, contains('ANTSF_ANDROID_STORE_PASSWORD'));
    expect(gradle, contains('ANTSF_ANDROID_KEY_ALIAS'));
    expect(gradle, contains('ANTSF_ANDROID_KEY_PASSWORD'));
    expect(gradle, contains('antsf.android.storeFile'));
    expect(gradle, contains('ANTSF_ANDROID_SIGNING_PROPERTIES'));
    expect(gradle, contains('create("antsfProdRelease")'));
    expect(gradle, contains('signingConfigs.findByName("antsfProdRelease")'));
    expect(
      gradle,
      contains('selectedFlavor == "prod" && prodReleaseRequested'),
    );
    expect(gradle, contains('Production release signing is not configured'));
    expect(gradle, contains('release {\n            signingConfig = null'));
    expect(gradle, isNot(contains('?: signingConfigs.getByName("debug")')));
  });

  test('versions belong exclusively to each flavor and suffix uses its own counter', () {
    final config = fixture();
    final gradle = renderAndroid(
      config,
      project,
    )['android/app/build.gradle.kts']!;
    expect(gradle, contains('versionCode = 51'));
    expect(
      gradle,
      contains('extra["force-version-code-ignoring-abi"] = "true"'),
    );
    expect(gradle, contains('versionName = "1.2.3"'));
    expect(gradle, contains('versionNameSuffix = "-b51"'));
    expect(gradle, contains('versionCode = 8'));
    expect(gradle, contains('versionName = "4.5.6"'));
    expect(gradle, isNot(contains('versionCode = flutter.versionCode')));
    expect(gradle, isNot(contains('versionName = flutter.versionName')));
    final flavors = config['flavors'] as Map<String, dynamic>;
    flavors['dev']['android']['versionCode'] = 52;
    final changed = renderAndroid(
      config,
      project,
    )['android/app/build.gradle.kts']!;
    expect(changed, contains('versionNameSuffix = "-b52"'));
    expect(changed, contains('versionCode = 8'));
    expect(changed, contains('versionName = "4.5.6"'));
    flavors['dev']['android'].remove('versionCode');
    expect(
      () => renderAndroid(config, project),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'renders distinct flavor identities while preserving template toolchain',
    () {
      final output = renderAndroid(fixture(), project);
      final gradle = output['android/app/build.gradle.kts']!;
      expect(gradle, contains('flavorDimensions += "app"'));
      expect(gradle, contains('create("dev")'));
      expect(gradle, contains('applicationIdSuffix = ".dev"'));
      expect(gradle, contains('create("prod")'));
      expect(gradle, contains('sourceCompatibility = JavaVersion.VERSION_17'));
      expect(gradle, contains('JvmTarget.JVM_17'));
      final manifest = output['android/app/src/main/AndroidManifest.xml']!;
      expect(manifest, contains('android:label="@string/app_name"'));
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
      expect(manifest, contains(r'${applicationName}'));
      expect(manifest, contains('flutterEmbedding'));
      expect(manifest, contains('android.permission.INTERNET'));
      expect(
        output['android/app/src/dev/res/values/strings.xml'],
        contains('[DEV] Sample'),
      );
      expect(
        output['android/app/src/prod/res/values/strings.xml'],
        contains('>Sample<'),
      );
    },
  );
}
