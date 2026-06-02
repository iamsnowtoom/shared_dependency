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
  final qualitySh = '$pkgRoot/scripts/quality/local-quality.sh';

  if (!File(qualitySh).existsSync()) {
    stderr.writeln('local-quality.sh not found at: $qualitySh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [qualitySh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'QUALITY_PROJECT_ROOT': Directory.current.path,
    },
  );
  exit(await proc.exitCode);
}
