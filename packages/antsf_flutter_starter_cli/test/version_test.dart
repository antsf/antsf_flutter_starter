import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:antsf_flutter_starter_cli/src/version.dart';
import 'package:test/test.dart';

void main() {
  ProjectConfig sample() => ProjectConfig.create(
    name: 'sample',
    organization: 'com.example',
    displayName: 'Sample',
    apiUrls: {
      'dev': 'https://dev.example.net',
      'stg': 'https://stg.example.net',
      'prod': 'https://api.example.net',
    },
  );
  test(
    'edits only the specified flavor and platform, preserving the input',
    () {
      final before = sample();
      final original = before.encode();
      final after = editVersion(
        before,
        flavor: 'dev',
        platform: 'android',
        versionName: '1.0.4',
        buildNumber: '51',
      );
      expect(before.encode(), original);
      expect(after.flavors['dev']['android']['versionCode'], 51);
      expect(after.flavors['dev']['android']['versionName'], '1.0.4');
      expect(after.flavors['dev']['ios'], before.flavors['dev']['ios']);
      expect(after.flavors['stg'], before.flavors['stg']);
      expect(after.flavors['prod'], before.flavors['prod']);
      final ios = editVersion(
        after,
        flavor: 'stg',
        platform: 'ios',
        versionName: '2.0.3',
        buildNumber: '88',
      );
      expect(ios.flavors['stg']['ios'], {
        'versionName': '2.0.3',
        'buildNumber': '88',
      });
      expect(ios.flavors['stg']['android'], after.flavors['stg']['android']);
    },
  );
  test('rejects unknown targets and invalid versions without mutation', () {
    final config = sample();
    final before = config.encode();
    for (final target in [
      ('oops', 'android', '1.0.0', '1'),
      ('dev', 'desktop', '1.0.0', '1'),
      ('dev', 'ios', '1.0.0-b2', '1'),
      ('dev', 'android', '1.0.0', '-1'),
    ]) {
      expect(
        () => editVersion(
          config,
          flavor: target.$1,
          platform: target.$2,
          versionName: target.$3,
          buildNumber: target.$4,
        ),
        throwsFormatException,
      );
    }
    expect(config.encode(), before);
  });
}
