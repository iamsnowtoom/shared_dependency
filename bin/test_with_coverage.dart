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
  final testSh = '$pkgRoot/scripts/quality/test-with-coverage.sh';

  if (!File(testSh).existsSync()) {
    stderr.writeln('test-with-coverage.sh not found at: $testSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [testSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
    },
  );
  exit(await proc.exitCode);
}
