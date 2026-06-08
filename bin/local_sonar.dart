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
  final sonarSh = '$pkgRoot/scripts/quality/local-sonar.sh';

  if (!File(sonarSh).existsSync()) {
    stderr.writeln('local-sonar.sh not found at: $sonarSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [sonarSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'QUALITY_PROJECT_ROOT': Directory.current.path,
    },
  );
  exit(await proc.exitCode);
}
