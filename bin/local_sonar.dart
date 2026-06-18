import 'dart:io';

import 'package:shared_dependency/src/workspace.dart';

/// Runs the SonarQube quality gate on every package (or one, if a package name
/// is passed). Invoked once from the workspace root — where shared_dependency
/// resolves — and drives local-sonar.sh per package, so packages no longer need
/// to depend on the tool themselves.
void main(List<String> args) async {
  final sh = scriptPath(await toolRoot(), 'local-sonar.sh');
  if (!File(sh).existsSync()) {
    stderr.writeln('local-sonar.sh not found at: $sh');
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
    cleanLocalReports: true,
    extraEnv: (pkg) => {'QUALITY_PROJECT_ROOT': pkg.path},
  );
  exit(failed == 0 ? 0 : 1);
}
