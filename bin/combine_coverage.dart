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
  final combineSh = '$pkgRoot/scripts/quality/combine-coverage.sh';

  if (!File(combineSh).existsSync()) {
    stderr.writeln('combine-coverage.sh not found at: $combineSh');
    exit(1);
  }

  final projectRoot = args.isNotEmpty ? args[0] : Directory.current.path;

  final proc = await Process.start(
    'bash', [combineSh, projectRoot],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
    },
  );
  exit(await proc.exitCode);
}
