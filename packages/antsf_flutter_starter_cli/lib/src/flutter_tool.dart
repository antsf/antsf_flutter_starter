import 'dart:io';

import 'package:path/path.dart' as p;

/// Executes the installed Flutter snapshot through its Dart VM, never a shell.
class FlutterTool {
  FlutterTool(this.root);
  final String root;
  String get dartExecutable => p.join(
    root,
    'bin',
    'cache',
    'dart-sdk',
    'bin',
    Platform.isWindows ? 'dart.exe' : 'dart',
  );
  String get flutterSnapshot =>
      p.join(root, 'bin', 'cache', 'flutter_tools.snapshot');

  static FlutterTool discover() {
    final candidates = <String>[
      if (Platform.environment['FLUTTER_ROOT'] case final String root) root,
      p.normalize(
        p.join(p.dirname(Platform.resolvedExecutable), '..', '..', '..', '..'),
      ),
    ];
    for (final entry
        in (Platform.environment['PATH'] ?? Platform.environment['Path'] ?? '')
            .split(Platform.isWindows ? ';' : ':')) {
      for (final name in ['flutter', if (Platform.isWindows) 'flutter.bat']) {
        final file = File(p.join(entry, name));
        if (file.existsSync()) {
          candidates.add(p.dirname(p.dirname(file.resolveSymbolicLinksSync())));
        }
      }
    }
    for (final root in candidates) {
      final tool = FlutterTool(root);
      if (File(tool.dartExecutable).existsSync() &&
          File(tool.flutterSnapshot).existsSync()) {
        return tool;
      }
    }
    throw StateError(
      'A bootstrapped Flutter SDK is required. Put flutter on PATH and run flutter --version.',
    );
  }

  Future<int> flutter(
    List<String> args,
    String directory, {
    bool inheritStdio = true,
  }) => dart([flutterSnapshot, ...args], directory, inheritStdio: inheritStdio);

  Future<int> dart(
    List<String> args,
    String directory, {
    bool inheritStdio = true,
  }) async {
    final process = await Process.start(
      dartExecutable,
      args,
      workingDirectory: directory,
      runInShell: false,
      environment: {'FLUTTER_ROOT': root},
      mode: inheritStdio
          ? ProcessStartMode.inheritStdio
          : ProcessStartMode.normal,
    );
    if (!inheritStdio) {
      // Drain both pipes even for a failed process to avoid a pipe-buffer deadlock.
      await Future.wait([
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ]);
    }
    return process.exitCode;
  }
}
