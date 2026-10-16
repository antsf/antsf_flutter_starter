import 'dart:convert';

Map<String, String> renderLinks(Map<String, dynamic> config) {
  final files = <String, String>{};
  final notes = StringBuffer(
    '# Verified HTTPS links\n\nGenerated templates are not verified domain associations. Deploy manually only\nafter supplying real signing/team data and testing the real domain.\n\n',
  );
  for (final entry in (config['flavors'] as Map<String, dynamic>).entries) {
    final links = entry.value['links'] as Map<String, dynamic>?;
    if (links == null) {
      notes.writeln('## ${entry.key}\n\nDisabled; no domain prerequisite.\n');
      continue;
    }
    final appId =
        '${config['project']['applicationId']}${entry.value['applicationIdSuffix']}';
    final fingerprints = links['sha256CertFingerprints'] as List;
    final team = links['appleTeamId'] as String?;
    String encode(Object value) =>
        '${const JsonEncoder.withIndent('  ').convert(value)}\n';
    files['server-associations/${entry.key}/assetlinks.json.template'] = encode(
      [
        {
          'relation': ['delegate_permission/common.handle_all_urls'],
          'target': {
            'namespace': 'android_app',
            'package_name': appId,
            'sha256_cert_fingerprints': fingerprints,
          },
        },
      ],
    );
    files['server-associations/${entry.key}/apple-app-site-association.template'] =
        encode({
          'applinks': {
            'apps': <String>[],
            'details': [
              if (team != null)
                {
                  'appIDs': ['$team.$appId'],
                  'components': [
                    for (final path in links['paths'] as List) {'/': '$path*'},
                  ],
                },
            ],
          },
        });
    notes.writeln(
      '## ${entry.key}\n\nHost: `${links['host']}`. Paths: ${(links['paths'] as List).join(', ')}.\n',
    );
    notes.writeln(
      'Android: ${fingerprints.isEmpty ? 'INCOMPLETE: supply real SHA-256 signing certificate fingerprints.' : 'Template contains supplied fingerprints; live association is not verified.'}\n',
    );
    notes.writeln(
      'iOS: ${team == null ? 'INCOMPLETE: supply a real Apple Team ID and configure signing/provisioning.' : 'Template contains the supplied Team ID; live association is not verified.'}\n',
    );
    notes.writeln(
      'Publish the reviewed Android template as `https://${links['host']}/.well-known/assetlinks.json` and the reviewed iOS template as `https://${links['host']}/.well-known/apple-app-site-association`, without the `.template` suffix. Serve valid JSON over HTTPS without redirects and verify device association using the actual signed application. Combine entries when multiple app identities share a domain. Do not deploy empty/incomplete templates.\n',
    );
  }
  files['docs/flavor-links.md'] = notes.toString();
  return files;
}
