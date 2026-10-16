import 'dart:io';

import 'package:path/path.dart' as p;

/// Stages a new app beside the destination; publishes only complete output.
Future<void> createInDestination(
  Directory destination,
  Future<void> Function(Directory) populate,
) async {
  final path = p.normalize(p.absolute(destination.path));
  if (p.dirname(path) == path) {
    throw const FormatException(
      'Filesystem root is not a project destination.',
    );
  }
  for (var cursor = path; ; cursor = p.dirname(cursor)) {
    if (FileSystemEntity.typeSync(cursor, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError(
        'Project destination must not traverse a symbolic link.',
      );
    }
    if (p.dirname(cursor) == cursor) break;
  }
  final target = Directory(path);
  void check() {
    final kind = FileSystemEntity.typeSync(path, followLinks: false);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.directory) {
      throw StateError('Destination is not a directory.');
    }
    if (target.existsSync() && target.listSync().isNotEmpty) {
      throw StateError('Destination is non-empty; no files were overwritten.');
    }
  }

  check();
  target.parent.createSync(recursive: true);
  final staging = target.parent.createTempSync('.antsf-create-');
  try {
    final app = Directory(p.join(staging.path, 'app'));
    await populate(app);
    if (!app.existsSync()) {
      throw StateError('Creation did not produce an application.');
    }
    check();
    if (target.existsSync()) {
      target.deleteSync(); // Non-recursive: racing content cannot be deleted.
    }
    app.renameSync(path);
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}
