import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'config.dart';
import 'flutter_tool.dart';
import 'generator.dart';
import 'synchronizer.dart';
import 'version.dart';

ArgParser cliParser() {
  final parser = ArgParser()..addFlag('help', abbr: 'h', negatable: false);
  final create = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addOption('name', mandatory: true)
    ..addOption('org', mandatory: true)
    ..addOption('display-name', mandatory: true)
    ..addOption('dev-api', mandatory: true)
    ..addOption('prod-api', mandatory: true)
    ..addOption('stg-api')
    ..addOption(
      'starter-path',
      help: 'Local starter checkout for development; default is the reviewed Git commit.',
    )
    ..addOption('icon')
    ..addFlag('allow-dev-http', defaultsTo: false, negatable: false)
    ..addFlag('setup', defaultsTo: true)
    ..addMultiOption('link-path', defaultsTo: ['/open']);
  for (final flavor in ['dev', 'stg', 'prod']) {
    create.addOption('$flavor-icon');
    create.addOption('$flavor-link-host');
  }
  parser.addCommand('create', create);
  for (final command in [
    'validate',
    'sync',
    'recover',
    'version',
    'run',
    'build',
  ]) {
    final args = ArgParser()
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addOption('project', defaultsTo: '.');
    if (['version', 'run', 'build'].contains(command)) {
      args.addOption('flavor', mandatory: true);
    }
    if (command == 'version') {
      args
        ..addOption('platform', allowed: ['android', 'ios'], mandatory: true)
        ..addOption('name', mandatory: true)
        ..addOption('build', mandatory: true);
    }
    if (command == 'build') {
      args
        ..addOption('platform', allowed: ['android', 'ios'], mandatory: true)
        ..addFlag('simulator', negatable: false)
        ..addFlag('codesign', defaultsTo: true);
    }
    if (command == 'run' || command == 'build') {
      args.addOption(
        'mode',
        allowed: ['debug', 'profile', 'release'],
        defaultsTo: 'debug',
      );
    }
    if (command == 'run') {
      args.addOption('device');
      args.addOption(
        'platform',
        allowed: ['android', 'ios'],
        defaultsTo: Platform.isMacOS ? 'ios' : 'android',
      );
    }
    parser.addCommand(command, args);
  }
  return parser;
}

Future<int> runCli(
  List<String> arguments, {
  StringSink? output,
  StringSink? error,
  FlutterTool? flutterTool,
}) async {
  final out = output ?? stdout;
  final err = error ?? stderr;
  final parser = cliParser();
  try {
    // Help remains available without satisfying mandatory create/build arguments.
    if (arguments.isEmpty ||
        arguments.contains('--help') ||
        arguments.contains('-h')) {
      final command = arguments.isEmpty
          ? null
          : parser.commands[arguments.first];
      out.writeln(
        'antsf_starter <create|validate|sync|version|recover|run|build>\n${(command ?? parser).usage}',
      );
      return 0;
    }
    final parsed = parser.parse(arguments);
    final args = parsed.command;
    if (args == null) {
      throw const FormatException('A command is required; use --help.');
    }
    if (args.name == 'create') {
      if (args.rest.length != 1) {
        throw const FormatException(
          'create requires exactly one destination directory.',
        );
      }
      final apis = <String, String>{
        'dev': args['dev-api'] as String,
        if (args['stg-api'] != null) 'stg': args['stg-api'] as String,
        'prod': args['prod-api'] as String,
      };
      final local = args['starter-path'] as String?;
      if (local != null &&
          !File(p.join(p.absolute(local), 'pubspec.yaml')).existsSync()) {
        throw const FormatException(
          'Local starter checkout is missing its pubspec.yaml.',
        );
      }
      final config = ProjectConfig.create(
        name: args['name'] as String,
        organization: args['org'] as String,
        displayName: args['display-name'] as String,
        apiUrls: apis,
        allowLocalHttp: args['allow-dev-http'] as bool,
        starter: local == null
            ? null
            : {'path': p.absolute(local).replaceAll('\\', '/')},
      );
      for (final flavor in ['dev', 'stg', 'prod']) {
        final host = args['$flavor-link-host'];
        if ((host != null || args['$flavor-icon'] != null) &&
            !apis.containsKey(flavor)) {
          throw const FormatException('Staging options require --stg-api.');
        }
        if (host != null) {
          config.flavors[flavor]['links'] = {
            'host': host,
            'paths': args['link-path'],
            'appleTeamId': null,
            'sha256CertFingerprints': <String>[],
          };
        }
      }
      config.validate();
      final sources = <String, String>{
        if (args['icon'] != null) 'base': p.absolute(args['icon'] as String),
        for (final flavor in apis.keys)
          if (args['$flavor-icon'] != null)
            flavor: p.absolute(args['$flavor-icon'] as String),
      };
      await ProjectGenerator(FlutterTool.discover()).create(
        Directory(args.rest.single),
        config,
        sourceIcons: sources,
        setup: args['setup'] as bool,
      );
      out.writeln(
        'Created ${p.absolute(args.rest.single)}${args['setup'] == true ? '' : ' (dependency resolution/code generation skipped; run the documented setup commands)'}',
      );
      return 0;
    }
    if (args.rest.isNotEmpty) {
      throw const FormatException(
        'Unexpected arguments; build/version overrides are not accepted. Use --help.',
      );
    }
    final root = Directory(p.absolute(args['project'] as String));
    if (args.name == 'recover') {
      Synchronizer(root).recover();
      out.writeln(
        'Recovered the interrupted transaction. Inspect restored files before syncing.',
      );
      return 0;
    }
    final source = File(p.join(root.path, configFilename)).readAsStringSync();
    final config = ProjectConfig.fromJson(source);
    if (args.name == 'validate') {
      out.writeln(
        'Configuration valid: ${config.flavors.keys.join(', ')}. This is not build/signing/domain verification.',
      );
      return 0;
    }
    final tool = flutterTool ?? FlutterTool.discover();
    final generator = ProjectGenerator(tool);
    if (args.name == 'sync') {
      await generator.synchronize(root, config, expectedConfig: source);
      out.writeln(
        'Synchronized managed flavor outputs; application-owned code untouched.',
      );
    } else if (args.name == 'version') {
      final updated = editVersion(
        config,
        flavor: args['flavor'] as String,
        platform: args['platform'] as String,
        versionName: args['name'] as String,
        buildNumber: args['build'] as String,
      );
      await generator.synchronize(
        root,
        updated,
        updatedConfig: updated.encode(),
        expectedConfig: source,
      );
      out.writeln(
        'Updated only ${args['flavor']}/${args['platform']} and synchronized managed output.',
      );
    } else {
      final flavor = args['flavor'] as String;
      if (!config.flavors.containsKey(flavor)) {
        throw const FormatException(
          'Unknown flavor; choose an enabled native flavor.',
        );
      }
      final platform = args['platform'] as String;
      final guarded = await tool.dart([
        'tool/flavor_guard.dart',
        '--flavor=$flavor',
        '--platform=$platform',
      ], root.path);
      if (guarded != 0) return guarded;
      final flags = <String>['--flavor', flavor, '--${args['mode']}'];
      if (args.name == 'run') {
        if (args['device'] != null) {
          flags.addAll(['--device-id', args['device'] as String]);
        }
        return await tool.flutter(['run', ...flags], root.path);
      }
      if (platform == 'ios') {
        if (args['simulator'] == true) flags.add('--simulator');
        if (args['codesign'] == false) flags.add('--no-codesign');
      }
      return await tool.flutter([
        'build',
        platform == 'android' ? 'apk' : 'ios',
        ...flags,
      ], root.path);
    }
    return 0;
  } on ArgParserException {
    err.writeln('Invalid command options. Run antsf_starter <command> --help.');
    return 2;
  } on FormatException catch (e) {
    err.writeln(e.message);
    return 2;
  } on StateError catch (e) {
    err.writeln(e.message);
    return 2;
  } on FileSystemException catch (e) {
    err.writeln(
      'Filesystem operation failed: ${e.message}. Check the project path and generated state.',
    );
    return 2;
  } on ProcessException {
    err.writeln(
      'Could not launch the installed Flutter/Dart toolchain. Check SDK prerequisites.',
    );
    return 2;
  }
}
