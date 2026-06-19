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

  final reportsDir = Directory('${Directory.current.path}/reports');
  if (reportsDir.existsSync()) {
    reportsDir.deleteSync(recursive: true);
  }

  // When run via melos exec, all reports go to <melos root>/reports/<package>/
  // (sonarqube/, coverage/, analyze/) instead of inside the package itself.
  final melosRoot = Platform.environment['MELOS_ROOT_PATH'];
  String? pkgReportDir;
  if (melosRoot != null && melosRoot.isNotEmpty) {
    final packageName = Platform.environment['MELOS_PACKAGE_NAME'] ??
        Directory.current.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    pkgReportDir = '$melosRoot/reports/$packageName';
  }

  final proc = await Process.start(
    'bash', [sonarSh, ...args],
    mode: ProcessStartMode.inheritStdio,
    environment: {
      ...Platform.environment,
      'QUALITY_PROJECT_ROOT': Directory.current.path,
      if (pkgReportDir != null) 'QUALITY_PKG_REPORT_DIR': pkgReportDir,
    },
  );
  exit(await proc.exitCode);
}
