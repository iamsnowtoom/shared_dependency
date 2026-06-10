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

  // When run via melos exec, analyze results go to
  // <melos root>/reports/<package>/analyze/ instead of inside the package.
  final melosRoot = Platform.environment['MELOS_ROOT_PATH'];
  String? pkgReportDir;
  if (melosRoot != null && melosRoot.isNotEmpty) {
    final packageName = Platform.environment['MELOS_PACKAGE_NAME'] ??
        Directory.current.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    pkgReportDir = '$melosRoot/reports/$packageName';
  }

  final proc = await Process.start(
    'bash', [analyzeSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'PROJECT_ROOT': Directory.current.path,
      if (pkgReportDir != null) 'QUALITY_PKG_REPORT_DIR': pkgReportDir,
    },
  );
  exit(await proc.exitCode);
}
