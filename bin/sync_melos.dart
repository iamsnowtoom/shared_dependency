import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// The shared tool package name — provides local_sonar / flutter_analyze /
/// etc. Must be resolvable inside each package for `melos exec -- dart run
/// <tool>:...` to work, so we inject it into every package's dev_dependencies.
const _tool = 'shared_dependency';

/// Generates melos.yaml at the current directory (workspace root) from the
/// template in shared_dependency, then locks the file (chmod 444 + chflags
/// uchg on macOS) so it can only change through regeneration. Also injects the
/// shared tool into each package's dev_dependencies so per-package gate scripts
/// (run via `melos exec`) can resolve it.
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

  _injectToolDependency(root, packages);
}

/// Ensures every package declares the shared tool as a dev_dependency, copying
/// the exact spec the workspace root uses. Idempotent — packages that already
/// declare it (in dependencies or dev_dependencies) are left untouched.
void _injectToolDependency(Directory root, List<String> packages) {
  final rootPubspec = File('${root.path}/pubspec.yaml');
  if (!rootPubspec.existsSync()) return;

  final rootYaml = loadYaml(rootPubspec.readAsStringSync());
  dynamic spec;
  for (final section in const ['dependencies', 'dev_dependencies']) {
    final m = (rootYaml is Map) ? rootYaml[section] : null;
    if (m is Map && m.containsKey(_tool)) {
      spec = m[_tool];
      break;
    }
  }
  if (spec == null) {
    stderr.writeln(
        '⚠ $_tool not declared in root pubspec — skipping per-package injection');
    return;
  }
  final plainSpec = _toPlain(spec);

  final injected = <String>[];
  for (final pkg in packages) {
    final pf = File('${root.path}/$pkg/pubspec.yaml');
    if (!pf.existsSync()) continue;
    final text = pf.readAsStringSync();
    final doc = loadYaml(text);

    bool declaredIn(String section) {
      final m = (doc is Map) ? doc[section] : null;
      return m is Map && m.containsKey(_tool);
    }

    if (declaredIn('dependencies') || declaredIn('dev_dependencies')) continue;

    final editor = YamlEditor(text);
    final hasDevSection = (doc is Map) && doc['dev_dependencies'] is Map;
    if (hasDevSection) {
      editor.update(['dev_dependencies', _tool], plainSpec);
    } else {
      editor.update(['dev_dependencies'], {_tool: plainSpec});
    }
    pf.writeAsStringSync(editor.toString());
    injected.add(pkg);
  }

  if (injected.isNotEmpty) {
    stdout.writeln(
        '✓ injected $_tool dev_dependency into: ${injected.join(', ')}');
    stdout.writeln(
        '  → run `melos bootstrap` (or flutter pub get) to resolve');
  }
}

/// Deep-convert YamlMap/YamlList nodes to plain Dart structures so yaml_edit
/// can re-serialize them.
dynamic _toPlain(dynamic node) {
  if (node is YamlMap) {
    return {for (final e in node.entries) e.key.toString(): _toPlain(e.value)};
  }
  if (node is YamlList) {
    return [for (final v in node) _toPlain(v)];
  }
  return node;
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
