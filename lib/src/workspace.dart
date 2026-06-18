import 'dart:io';
import 'dart:isolate';

/// Packages excluded from every gate script (the host app shell). The workspace
/// root is never a package here because discovery only looks at sub-directories.
const ignoredPackages = {'app'};

String basename(Directory d) =>
    d.uri.pathSegments.where((s) => s.isNotEmpty).last;

/// Resolves shared_dependency's package root (where scripts/ lives).
Future<String> toolRoot() async {
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:shared_dependency/'),
  );
  if (uri == null) {
    stderr.writeln('Cannot resolve package:shared_dependency/');
    exit(1);
  }
  return Directory.fromUri(uri).parent.path;
}

String scriptPath(String toolRoot, String name) =>
    '$toolRoot/scripts/quality/$name';

/// Direct sub-directories of [root] that contain a pubspec.yaml, excluding
/// dot-directories and [ignore]. This replaces melos's package resolution so
/// gate tools can run from the workspace root (where the tool resolves) instead
/// of via `melos exec` inside each package (where it would not).
List<Directory> discoverPackages(
  Directory root, {
  Set<String> ignore = ignoredPackages,
}) {
  final out = <Directory>[];
  for (final entry in root.listSync()) {
    if (entry is! Directory) continue;
    final name = basename(entry);
    if (name.startsWith('.')) continue;
    if (ignore.contains(name)) continue;
    if (File('${entry.path}/pubspec.yaml').existsSync()) out.add(entry);
  }
  out.sort((a, b) => basename(a).compareTo(basename(b)));
  return out;
}

/// Splits CLI args into an optional target package name (first non-flag arg)
/// and the remaining flags to forward to the shell script.
({String? package, List<String> shArgs}) parseArgs(List<String> args) {
  String? package;
  final shArgs = <String>[];
  for (final a in args) {
    if (a.startsWith('-')) {
      shArgs.add(a);
    } else if (package == null) {
      package = a;
    } else {
      shArgs.add(a);
    }
  }
  return (package: package, shArgs: shArgs);
}

/// Resolves which packages to operate on: all discovered, or just [target].
List<Directory> selectPackages(
  Directory root,
  String? target, {
  Set<String> ignore = ignoredPackages,
}) {
  final all = discoverPackages(root, ignore: ignore);
  if (target == null) return all;
  final match = all.where((d) => basename(d) == target).toList();
  if (match.isEmpty) {
    stderr.writeln(
        'Package "$target" not found or is ignored. Available: '
        '${all.map(basename).join(', ')}');
    exit(1);
  }
  return match;
}

/// Runs [sh] once per package (sequentially), replicating the environment that
/// `melos exec` used to provide (CWD = package, MELOS_* + QUALITY_* vars).
/// Returns the number of packages that failed.
Future<int> runPerPackage(
  String sh,
  List<String> args,
  Directory root,
  List<Directory> packages, {
  Map<String, String> Function(Directory pkg)? extraEnv,
  bool cleanLocalReports = false,
}) async {
  var failed = 0;
  for (final pkg in packages) {
    final name = basename(pkg);

    if (cleanLocalReports) {
      final local = Directory('${pkg.path}/reports');
      if (local.existsSync()) local.deleteSync(recursive: true);
    }

    final env = <String, String>{
      ...Platform.environment,
      'MELOS_ROOT_PATH': root.path,
      'MELOS_PACKAGE_NAME': name,
      'MELOS_PACKAGE_PATH': pkg.path,
      'QUALITY_PKG_REPORT_DIR': '${root.path}/reports/$name',
      if (extraEnv != null) ...extraEnv(pkg),
    };

    stdout.writeln('\n━━ $name ━━');
    final proc = await Process.start(
      'bash',
      [sh, ...args],
      workingDirectory: pkg.path,
      mode: ProcessStartMode.inheritStdio,
      environment: env,
    );
    final code = await proc.exitCode;
    if (code != 0) {
      failed++;
      stderr.writeln('✗ $name failed (exit $code)');
    } else {
      stdout.writeln('✓ $name');
    }
  }
  return failed;
}
