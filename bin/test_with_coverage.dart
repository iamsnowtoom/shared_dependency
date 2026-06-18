import 'dart:io';

import 'package:shared_dependency/src/workspace.dart';

/// Runs Flutter tests with lcov coverage on every package that has a `test/`
/// directory (or one, if a package name is passed), driven from the workspace
/// root.
void main(List<String> args) async {
  final sh = scriptPath(await toolRoot(), 'test-with-coverage.sh');
  if (!File(sh).existsSync()) {
    stderr.writeln('test-with-coverage.sh not found at: $sh');
    exit(1);
  }

  final root = Directory.current;
  final parsed = parseArgs(args);
  final packages = selectPackages(root, parsed.package)
      // mirror melos `dirExists: test` — only packages with tests.
      .where((p) => Directory('${p.path}/test').existsSync())
      .toList();
  if (packages.isEmpty) {
    stderr.writeln('No packages with a test/ directory found under ${root.path}');
    exit(1);
  }

  final failed = await runPerPackage(sh, parsed.shArgs, root, packages);
  exit(failed == 0 ? 0 : 1);
}
