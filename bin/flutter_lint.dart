import 'dart:io';
import 'dart:isolate';

void main(List<String> args) async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:shared_dependency/'),
  );
  if (packageUri == null) {
    stderr.writeln('Cannot resolve package:shared_dependency/');
    exit(1);
  }

  final pkgRoot = Directory.fromUri(packageUri).parent.path;
  final lintSh = '$pkgRoot/scripts/quality/flutter-lint.sh';

  if (!File(lintSh).existsSync()) {
    stderr.writeln('flutter-lint.sh not found at: $lintSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [lintSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'PROJECT_ROOT': Directory.current.path,
    },
  );
  exit(await proc.exitCode);
}
