import 'dart:io';

import 'package:antsf_flutter_starter_cli/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runCli(arguments);
}
