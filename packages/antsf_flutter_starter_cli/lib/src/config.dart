import 'dart:convert';
import 'dart:io';

/// The versioned, non-secret source of truth for a generated application.
class ProjectConfig {
  ProjectConfig._(this.data);

  final Map<String, dynamic> data;
  Map<String, dynamic> get flavors => data['flavors'] as Map<String, dynamic>;

  static ProjectConfig create({
    required String name,
    required String organization,
    required String displayName,
    required Map<String, String> apiUrls,
    Map<String, dynamic>? starter,
    bool allowLocalHttp = false,
  }) {
    final config = ProjectConfig._({
      'schemaVersion': 1,
      'project': {
        'name': name,
        'organization': organization,
        'applicationId': '$organization.${name.replaceAll('_', '')}',
        'displayName': displayName,
        'starter':
            starter ??
            {
              'git': {
                'url': 'https://github.com/antsf/antsf_flutter_starter.git',
                'ref': 'c0e8c4491cd46e91077402199b843903c92b3427',
              },
            },
      },
      'icon': null,
      'flavors': {
        for (final entry in apiUrls.entries)
          entry.key: {
            'applicationIdSuffix': entry.key == 'prod' ? '' : '.${entry.key}',
            'displayName': entry.key == 'prod'
                ? displayName
                : '[${entry.key.toUpperCase()}] $displayName',
            'apiBaseUrl': entry.value,
            'allowLocalHttp': entry.key == 'dev' && allowLocalHttp,
            'logMetadata': entry.key != 'prod',
            'icon': null,
            'android': {
              'versionName': '1.0.0',
              'versionCode': 1,
              'versionNameSuffix': entry.key == 'prod' ? '' : '-b{build}',
            },
            'ios': {'versionName': '1.0.0', 'buildNumber': '1'},
            'links': null,
          },
      },
    });
    config.validate();
    return config;
  }

  factory ProjectConfig.fromJson(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a configuration object.');
      }
      final config = ProjectConfig._(decoded);
      config.validate();
      return config;
    } on TypeError {
      throw const FormatException('Invalid configuration types.');
    }
  }

  String encode() => '${const JsonEncoder.withIndent('  ').convert(data)}\n';

  void validate() {
    _keys(data, {
      'schemaVersion',
      'project',
      'icon',
      'flavors',
    }, 'configuration');
    if (data['schemaVersion'] != 1) {
      throw const FormatException('Unsupported schemaVersion; expected 1.');
    }
    final project = _map(data['project'], 'project');
    _keys(project, {
      'name',
      'organization',
      'applicationId',
      'displayName',
      'starter',
    }, 'project');
    final name = _text(project['name'], 'project.name');
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name) ||
        RegExp(r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])$').hasMatch(name) ||
        {
          'flutter',
          'dart',
          'test',
          'class',
          'import',
          'enum',
          'void',
          'null',
          'true',
          'false',
        }.contains(name)) {
      throw const FormatException(
        'Invalid Dart project name or reserved destination name.',
      );
    }
    final identity = RegExp(r'^[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*)+$');
    if (!identity.hasMatch(_text(project['organization'], 'organization')) ||
        !identity.hasMatch(_text(project['applicationId'], 'applicationId'))) {
      throw const FormatException(
        'Organization/application ID requires dotted alphanumeric components valid on both platforms.',
      );
    }
    _text(project['displayName'], 'displayName');
    final starter = _map(project['starter'], 'starter');
    if (starter.length != 1 ||
        (!starter.containsKey('git') && !starter.containsKey('path'))) {
      throw const FormatException(
        'starter requires one git or local path dependency.',
      );
    }
    if (starter.containsKey('git')) {
      final git = _map(starter['git'], 'starter.git');
      _keys(git, {'url', 'ref'}, 'starter.git');
      if (git['url'] != 'https://github.com/antsf/antsf_flutter_starter.git' ||
          !RegExp(r'^[a-f0-9]{40}$')
              .hasMatch(_text(git['ref'], 'starter.git.ref'))) {
        throw const FormatException(
          'Starter Git dependency must use the canonical repository and a full reviewed commit SHA.',
        );
      }
    } else {
      _text(starter['path'], 'starter.path');
    }
    _icon(data['icon']);
    final all = _map(data['flavors'], 'flavors');
    if (!all.containsKey('dev') || !all.containsKey('prod')) {
      throw const FormatException('dev and prod are required.');
    }
    final identities = <String>{};
    for (final entry in flavors.entries) {
      if (!RegExp(r'^[a-z][a-z0-9]*$').hasMatch(entry.key) ||
          entry.key.length > 24) {
        throw const FormatException('Invalid flavor name.');
      }
      final flavor = _map(entry.value, 'flavor ${entry.key}');
      _keys(flavor, {
        'applicationIdSuffix',
        'displayName',
        'apiBaseUrl',
        'allowLocalHttp',
        'logMetadata',
        'icon',
        'android',
        'ios',
        'links',
      }, entry.key);
      final suffix = flavor['applicationIdSuffix'];
      if (suffix != (entry.key == 'prod' ? '' : '.${entry.key}')) {
        throw FormatException('${entry.key}: invalid application ID suffix.');
      }
      if (!identities.add('${project['applicationId']}$suffix')) {
        throw const FormatException('Native identities must be unique.');
      }
      _text(flavor['displayName'], '${entry.key}.displayName');
      if (entry.key != 'prod' &&
          !(flavor['displayName'] as String).startsWith(
            '[${entry.key.toUpperCase()}] ',
          )) {
        throw const FormatException(
          'Non-production display names require a flavor marker.',
        );
      }
      if (flavor['allowLocalHttp'] is! bool ||
          flavor['logMetadata'] is! bool ||
          (entry.key != 'dev' && flavor['allowLocalHttp'] == true) ||
          (entry.key == 'prod' && flavor['logMetadata'] == true)) {
        throw const FormatException('Unsafe transport/logging policy.');
      }
      _icon(flavor['icon']);
      for (final platform in ['android', 'ios']) {
        final version = _map(flavor[platform], '$platform version');
        _keys(
          version,
          platform == 'android'
              ? {'versionName', 'versionCode', 'versionNameSuffix'}
              : {'versionName', 'buildNumber'},
          '$platform version',
        );
        if (!RegExp(r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$')
            .hasMatch(_text(version['versionName'], 'versionName'))) {
          throw const FormatException(
            'versionName must be a three-part numeric version without suffix.',
          );
        }
        if (platform == 'android') {
          if (version['versionCode'] is! int ||
              version['versionCode'] < 1 ||
              version['versionCode'] > 2100000000) {
            throw const FormatException(
              'Android versionCode must be a positive supported integer.',
            );
          }
          if (version['versionNameSuffix'] !=
              (entry.key == 'prod' ? '' : '-b{build}')) {
            throw const FormatException(
              'Version suffix must be empty for prod or -b{build} for non-prod.',
            );
          }
        } else if (!RegExp(r'^[1-9][0-9]{0,8}$')
            .hasMatch(_text(version['buildNumber'], 'iOS buildNumber'))) {
          throw const FormatException(
            'iOS buildNumber must be a positive numeric string.',
          );
        }
      }
      final links = flavor['links'];
      if (links != null) {
        final link = _map(links, 'links');
        _keys(link, {
          'host',
          'paths',
          'appleTeamId',
          'sha256CertFingerprints',
        }, 'links');
        if (!RegExp(r'^[a-z0-9]+([.-][a-z0-9]+)*\.[a-z]{2,}$')
            .hasMatch(_text(link['host'], 'links.host'))) {
          throw const FormatException(
            'Links host must be a hostname, without scheme or path.',
          );
        }
        if (link['paths'] is! List ||
            (link['paths'] as List).isEmpty ||
            (link['paths'] as List).any(
              (v) => v is! String || !RegExp(r'^/[a-zA-Z0-9/_-]*$').hasMatch(v),
            )) {
          throw const FormatException(
            'Links paths must be non-empty safe absolute path prefixes.',
          );
        }
        if (link['appleTeamId'] != null &&
            !RegExp(r'^[A-Z0-9]{10}$')
                .hasMatch(_text(link['appleTeamId'], 'Apple Team ID'))) {
          throw const FormatException('Invalid Apple Team ID.');
        }
        if (link['sha256CertFingerprints'] is! List ||
            (link['sha256CertFingerprints'] as List).any(
              (v) =>
                  v is! String ||
                  !RegExp(r'^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){31}$').hasMatch(v),
            )) {
          throw const FormatException(
            'Invalid SHA-256 certificate fingerprints.',
          );
        }
      }
      final url = flavor['apiBaseUrl'];
      final uri = url is String ? Uri.tryParse(url) : null;
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !RegExp(r'^[a-zA-Z0-9.:-]+$').hasMatch(uri.host) ||
          uri.host.endsWith('.invalid') ||
          !['https', 'http'].contains(uri.scheme)) {
        throw FormatException(
          '${entry.key}: invalid API base URL (no credentials/query/fragment/placeholders).',
        );
      }
      if (uri.scheme != 'https') {
        final host = uri.host.toLowerCase();
        final address = InternetAddress.tryParse(host);
        final octets = address?.rawAddress;
        final privateV4 =
            octets != null &&
            octets.length == 4 &&
            (octets[0] == 127 ||
                octets[0] == 10 ||
                (octets[0] == 192 && octets[1] == 168) ||
                (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31));
        final local =
            host == 'localhost' ||
            host == '::1' ||
            privateV4 ||
            host.endsWith('.local');
        if (entry.key != 'dev' || flavor['allowLocalHttp'] != true || !local) {
          throw FormatException(
            '${entry.key}: HTTPS required; only explicitly enabled local dev HTTP is allowed.',
          );
        }
      }
    }
  }

  static Map<String, dynamic> _map(dynamic value, String label) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$label must be an object.');
    }
    return value;
  }

  static String _text(dynamic value, String label) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > 300 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw FormatException(
        '$label must be non-empty text without control characters.',
      );
    }
    return value;
  }

  static void _keys(
    Map<String, dynamic> value,
    Set<String> allowed,
    String label,
  ) {
    if (value.keys.any((key) => !allowed.contains(key)) ||
        !value.keys.toSet().containsAll(allowed)) {
      throw FormatException(
        '$label has missing or unknown fields; do not store secrets here.',
      );
    }
  }

  static void _icon(dynamic value) {
    if (value == null) return;
    final path = _text(value, 'icon');
    if (path.startsWith('/') ||
        path.startsWith('\\') ||
        path.contains(':') ||
        path.split(RegExp(r'[/\\]')).contains('..')) {
      throw const FormatException(
        'Icons must use project-relative paths without traversal.',
      );
    }
  }
}
