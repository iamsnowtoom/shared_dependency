import 'dart:io';

void main(List<String> args) async {
  final script = File(Platform.script.toFilePath());
  final scriptRoot = script.parent.parent.path;
  final lintSh = '$scriptRoot/scripts/quality/flutter-lint.sh';

  if (!File(lintSh).existsSync()) {
    stderr.writeln('flutter-lint.sh not found at: $lintSh');
    exit(1);
  }

  final proc = await Process.start(
    'bash', [lintSh, ...args],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await proc.exitCode);
}
