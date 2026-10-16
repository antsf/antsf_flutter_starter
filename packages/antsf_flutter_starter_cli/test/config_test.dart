import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:test/test.dart';

void main() {
  test('default configuration validates two native flavors', () {
    final config = ProjectConfig.create(
      name: 'sample_app',
      organization: 'com.example',
      displayName: 'Sample',
      apiUrls: {
        'dev': 'https://dev.example.net',
        'prod': 'https://api.example.net',
      },
    );
    expect(config.flavors.keys, ['dev', 'prod']);
    expect(config.data['project']['applicationId'], 'com.example.sampleapp');
    expect(config.flavors['dev']['android']['versionCode'], 1);
    expect(config.flavors['dev']['ios']['buildNumber'], '1');
  });
  test('production rejects unsafe or placeholder API URLs', () {
    for (final unsafe in [
      'http://api.example.net',
      'https://user:pass@api.example.net',
      'https://api.example.net?token=secret',
      'https://api.example.net/#fragment',
      'https://YOUR_API_HOST',
      'https://todo.invalid',
    ]) {
      expect(
        () => ProjectConfig.create(
          name: 'sample_app',
          organization: 'com.example',
          displayName: 'Sample',
          apiUrls: {'dev': 'https://dev.example.net', 'prod': unsafe},
        ),
        throwsFormatException,
        reason: unsafe,
      );
    }
  });
  test('malformed schema, identity, flavor and version data fail closed', () {
    final mutations = <void Function(Map<String, dynamic>)>[
      (d) => d['schemaVersion'] = 2,
      (d) => d['project']['name'] = '../escape',
      (d) => d['project']['applicationId'] = 'com.example.bad_id',
      (d) => d['project']['displayName'] = 'Bad\nName',
      (d) => d['flavors'].remove('prod'),
      (d) => d['flavors']['dev']['applicationIdSuffix'] = '',
      (d) => d['flavors']['prod']['logMetadata'] = true,
      (d) => d['flavors']['dev']['android']['versionCode'] = 0,
      (d) => d['flavors']['dev']['android']['versionName'] = '1.0.0-b2',
      (d) => d['flavors']['dev']['ios']['buildNumber'] = '-1',
      (d) => d['flavors']['dev']['ios']['versionName'] = '1.0.0-b2',
      (d) => d['password'] = 'should-not-be-here',
      (d) => d['flavors']['dev']['links'] = {
        'host': 'host/path',
        'paths': ['/open'],
      },
    ];
    for (final mutate in mutations) {
      final good = ProjectConfig.create(
        name: 'sample',
        organization: 'com.example',
        displayName: 'Sample',
        apiUrls: {
          'dev': 'https://dev.example.net',
          'prod': 'https://api.example.net',
        },
      );
      mutate(good.data);
      expect(good.validate, throwsFormatException);
    }
  });
  test(
    'HTTP opt-in accepts local addresses, not lookalike public DNS names',
    () {
      for (final host in ['10.evil.net', '192.168.evil.net', '127.evil.net']) {
        expect(
          () => ProjectConfig.create(
            name: 'sample',
            organization: 'com.example',
            displayName: 'Sample',
            allowLocalHttp: true,
            apiUrls: {
              'dev': 'http://$host:8080',
              'prod': 'https://api.example.net',
            },
          ),
          throwsFormatException,
        );
      }
      for (final host in [
        'localhost',
        '127.0.0.1',
        '10.0.2.2',
        '192.168.1.10',
        '172.20.1.1',
      ]) {
        expect(
          () => ProjectConfig.create(
            name: 'sample',
            organization: 'com.example',
            displayName: 'Sample',
            allowLocalHttp: true,
            apiUrls: {
              'dev': 'http://$host:8080',
              'prod': 'https://api.example.net',
            },
          ),
          returnsNormally,
        );
      }
    },
  );
}
