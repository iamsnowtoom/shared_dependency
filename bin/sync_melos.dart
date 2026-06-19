import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// The shared tool package name. It is injected into every package's
/// dev_dependencies so that `melos exec -- dart run <tool>:...` resolves the
/// tool no matter how deeply the package is nested.
const _tool = 'shared_dependency';

/// Packages excluded from gate scripts (matched by directory name). They never
/// run the tool, so they don't get the dependency injected.
const _ignoredNames = {'app'};

/// Directory names we never descend into while scanning for packages.
const _skipDirs = {'build'};

/// Generates melos.yaml at the current directory (workspace root) from the
/// template, then locks it. Discovers packages RECURSIVELY (a package is any
/// directory containing pubspec.yaml, at any depth) and injects the shared tool
/// into each so per-package gate scripts can resolve it.
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

  // Recursive package discovery (relative paths from root).
  final packages = discoverPackages(root);
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
      '✓ melos.yaml generated (${packages.length} packages) and locked');

  _injectToolDependency(root, packages);
}

/// Recursively finds packages under [root]: the topmost directory in each
/// branch that contains a pubspec.yaml. Descent stops at a found package, so
/// nested example/ios/android/build pubspecs are ignored. Returns paths
/// relative to [root], sorted.
List<String> discoverPackages(Directory root) {
  final found = <String>[];
  void walk(Directory dir) {
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync();
    } catch (_) {
      return; // unreadable dir
    }
    for (final e in entries) {
      if (e is! Directory) continue;
      final dirName = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (dirName.startsWith('.')) continue;
      if (_skipDirs.contains(dirName)) continue;
      if (File('${e.path}/pubspec.yaml').existsSync()) {
        found.add(_relative(root.path, e.path)); // package — do not descend
      } else {
        walk(e); // intermediate folder — keep looking deeper
      }
    }
  }

  walk(root);
  found.sort();
  return found;
}

String _relative(String root, String path) {
  var rel = path.startsWith(root) ? path.substring(root.length) : path;
  while (rel.startsWith('/')) {
    rel = rel.substring(1);
  }
  return rel;
}

String _basename(String relPath) => relPath.split('/').last;

/// Ensures every package (except ignored ones) declares the shared tool as a
/// dev_dependency, copying the exact spec the workspace root uses. Idempotent.
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
    if (_ignoredNames.contains(_basename(pkg))) continue;
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
    stdout.writeln('✓ injected $_tool into: ${injected.join(', ')}');
    stdout.writeln('  → run `melos bootstrap` (or flutter pub get) to resolve');
  }
}

/// Deep-convert YamlMap/YamlList nodes to plain Dart structures for yaml_edit.
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
