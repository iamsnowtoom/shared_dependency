import 'dart:io';
import 'dart:isolate';

/// Generates melos.yaml at the current directory (workspace root) from the
/// template in shared_dependency, then locks the file (chmod 444 + chflags
/// uchg on macOS) so it can only change through regeneration.
Future<void> main(List<String> args) async {
  final packageUri = await Isolate.resolvePackageUri(
    Uri.parse('package:shared_dependency/'),
  );
  if (packageUri == null) {
    stderr.writeln('Cannot resolve package:shared_dependency/');
    exit(1);
  }

  final pkgRoot = Directory.fromUri(packageUri).parent.path;
  final templateFile = File('$pkgRoot/scripts/quality/melos.template.yaml');
  if (!templateFile.existsSync()) {
    stderr.writeln('melos.template.yaml not found at: ${templateFile.path}');
    exit(1);
  }

  final root = Directory.current;

  // Workspace name: root pubspec.yaml name, falling back to directory name.
  var name = root.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
  final rootPubspec = File('${root.path}/pubspec.yaml');
  if (rootPubspec.existsSync()) {
    final m = RegExp(r'^name:\s*(\S+)', multiLine: true)
        .firstMatch(rootPubspec.readAsStringSync());
    if (m != null) name = m.group(1)!;
  }

  // Discover packages: direct subdirectories containing a pubspec.yaml.
  final packages = <String>[];
  for (final entry in root.listSync()) {
    if (entry is! Directory) continue;
    final dirName = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (dirName.startsWith('.')) continue;
    if (File('${entry.path}/pubspec.yaml').existsSync()) packages.add(dirName);
  }
  packages.sort();
  if (packages.isEmpty) {
    stderr.writeln('No packages with pubspec.yaml found under ${root.path}');
    exit(1);
  }

  final body = templateFile
      .readAsStringSync()
      .replaceAll('{{NAME}}', name)
      .replaceAll('{{PACKAGES}}', packages.map((p) => '  - $p').join('\n'));
  final content = '# GENERATED FILE — DO NOT EDIT.\n'
      '# Source: shared_dependency/scripts/quality/melos.template.yaml\n'
      '# Regenerate with: melos run sync:melos\n'
      '#   (or: dart run shared_dependency:sync_melos)\n'
      '$body';

  final out = File('${root.path}/melos.yaml');
  _unlock(out);
  out.writeAsStringSync(content);
  _lock(out);
  stdout.writeln(
      '✓ melos.yaml generated (${packages.length} packages: ${packages.join(', ')}) and locked');
}

void _unlock(File f) {
  if (!f.existsSync()) return;
  if (Platform.isMacOS) Process.runSync('chflags', ['nouchg', f.path]);
  Process.runSync('chmod', ['u+w', f.path]);
}

void _lock(File f) {
  Process.runSync('chmod', ['444', f.path]);
  if (Platform.isMacOS) Process.runSync('chflags', ['uchg', f.path]);
}
