import 'config.dart';

/// Returns a validated copy; never increments counters or mutates another target.
ProjectConfig editVersion(
  ProjectConfig config, {
  required String flavor,
  required String platform,
  required String versionName,
  required String buildNumber,
}) {
  final next = ProjectConfig.fromJson(config.encode());
  if (!next.flavors.containsKey(flavor) ||
      !{'android', 'ios'}.contains(platform)) {
    throw const FormatException(
      'Version editing requires an enabled flavor and android or ios.',
    );
  }
  final target = next.flavors[flavor][platform] as Map<String, dynamic>;
  target['versionName'] = versionName;
  if (platform == 'android') {
    final build = int.tryParse(buildNumber);
    if (build == null || build.toString() != buildNumber) {
      throw const FormatException(
        'Android build must be a canonical positive integer.',
      );
    }
    target['versionCode'] = build;
  } else {
    target['buildNumber'] = buildNumber;
  }
  next.validate();
  return next;
}
