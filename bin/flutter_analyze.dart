import 'dart:io';

import 'package:shared_dependency/src/workspace.dart';

/// Runs `flutter analyze` (strict) on every package (or one, if a package name
/// is passed), driven from the workspace root.
void main(List<String> args) async {
  final sh = scriptPath(await toolRoot(), 'flutter-analyze.sh');
  if (!File(sh).existsSync()) {
    stderr.writeln('flutter-analyze.sh not found at: $sh');
    exit(1);
  }

  final root = Directory.current;
  final parsed = parseArgs(args);
  final packages = selectPackages(root, parsed.package);
  if (packages.isEmpty) {
    stderr.writeln('No packages found under ${root.path}');
    exit(1);
  }

  final failed = await runPerPackage(
    sh,
    parsed.shArgs,
    root,
    packages,
    extraEnv: (pkg) => {'PROJECT_ROOT': pkg.path},
  );
  exit(failed == 0 ? 0 : 1);
}
