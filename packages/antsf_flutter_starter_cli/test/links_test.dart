import 'dart:convert';

import 'package:antsf_flutter_starter_cli/src/config.dart';
import 'package:antsf_flutter_starter_cli/src/links.dart';
import 'package:test/test.dart';

void main() {
  ProjectConfig config() => ProjectConfig.create(
    name: 'sample',
    organization: 'com.example',
    displayName: 'Sample',
    apiUrls: {
      'dev': 'https://dev.example.net',
      'prod': 'https://api.example.net',
    },
  );
  test('disabled links create no association files or domain prerequisite', () {
    expect(renderLinks(config().data).keys, ['docs/flavor-links.md']);
  });
  test(
    'incomplete association remains explicit, with no fake signing identities',
    () {
      final c = config();
      c.flavors['dev']['links'] = {
        'host': 'dev.example.net',
        'paths': ['/open'],
        'appleTeamId': null,
        'sha256CertFingerprints': <String>[],
      };
      c.validate();
      final files = renderLinks(c.data);
      final asset = jsonDecode(
        files['server-associations/dev/assetlinks.json.template']!,
      ) as List;
      expect(asset.single['target']['package_name'], 'com.example.sample.dev');
      expect(asset.single['target']['sha256_cert_fingerprints'], isEmpty);
      final apple = jsonDecode(
        files['server-associations/dev/apple-app-site-association.template']!,
      );
      expect(apple['applinks']['details'], isEmpty);
      expect(files['docs/flavor-links.md'], contains('INCOMPLETE'));
      expect(files['docs/flavor-links.md'], contains('not verified'));
    },
  );
}
