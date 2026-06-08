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
  final checkSh = '$pkgRoot/scripts/quality/dart-check-very-good-test.sh';

  if (!File(checkSh).existsSync()) {
    stderr.writeln('dart-check-very-good-test.sh not found at: $checkSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [checkSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
    },
  );
  exit(await proc.exitCode);
}
