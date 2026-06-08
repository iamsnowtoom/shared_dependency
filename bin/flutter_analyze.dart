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
  final analyzeSh = '$pkgRoot/scripts/quality/flutter-analyze.sh';

  if (!File(analyzeSh).existsSync()) {
    stderr.writeln('flutter-analyze.sh not found at: $analyzeSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [analyzeSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'PROJECT_ROOT': Directory.current.path,
    },
  );
  exit(await proc.exitCode);
}
