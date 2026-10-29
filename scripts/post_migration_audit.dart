// Run from repository root with the existing Flutter dev package graph:
// dart --packages=apps/client/.dart_tool/package_config.json scripts/post_migration_audit.dart before|after
// Read-only inventory. A zero-reference result is a REVIEW candidate, never an
// automatic deletion decision. Conditional imports/exports are all traversed.
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

String relative(String file) => p.relative(file).replaceAll('\\', '/');
final classes = <Map<String, dynamic>>[];
final declarations = <Map<String, dynamic>>[];
final references = <String, List<Map<String, dynamic>>>{};
final resources = <Map<String, dynamic>>[];
final calls = <String, int>{};

class InventoryVisitor extends RecursiveAstVisitor<void> {
  InventoryVisitor(this.file, this.unit);
  final String file;
  final CompilationUnit unit;
  String? owner(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ClassDeclaration) return current.namePart.typeName.lexeme;
      current = current.parent;
    }
    return null;
  }

  int line(AstNode node) => unit.lineInfo.getLocation(node.offset).lineNumber;
  void reference(String name, AstNode node) =>
      references.putIfAbsent(name, () => []).add({
        'file': file,
        'line': line(node),
        'offset': node.offset,
        'owner': owner(node),
      });
  void allocation(String type, AstNode node) {
    if (RegExp(
      r'(Controller$|^ValueNotifier$|^Timer$|^StreamController$|^RealtimeFeed$|^PatientUpdates$|^FlutterTts$)',
    ).hasMatch(type)) {
      resources.add({
        'file': file,
        'line': line(node),
        'type': type,
        'owner': owner(node),
      });
    }
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final value = <String, dynamic>{
      'name': node.namePart.typeName.lexeme,
      'file': file,
      'line': line(node),
      'offset': node.offset,
      'end': node.end,
      'superclass': node.extendsClause?.superclass.name.lexeme,
      'mixins':
          node.withClause?.mixinTypes.map((t) => t.name.lexeme).toList() ?? [],
      'abstract': node.abstractKeyword != null,
    };
    classes.add(value);
    declarations.add({...value, 'kind': 'class'});
    super.visitClassDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit)
      declarations.add({
        'name': node.name.lexeme,
        'file': file,
        'line': line(node),
        'offset': node.offset,
        'end': node.end,
        'kind': 'function',
      });
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (file.startsWith('apps/client/lib/')) {
      calls.update('methodDeclarations', (n) => n + 1, ifAbsent: () => 1);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    reference(node.name, node);
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNamedType(NamedType node) {
    reference(node.name.lexeme, node);
    super.visitNamedType(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (file.startsWith('apps/client/lib/'))
      allocation(node.constructorName.type.name.lexeme, node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (file.startsWith('apps/client/lib/')) {
      final name = node.methodName.name;
      calls.update(name, (n) => n + 1, ifAbsent: () => 1);
      // parseString can retain constructor-like invocations until resolution.
      allocation(name, node);
      if (node.target?.toSource() == 'Timer' && name == 'periodic')
        allocation('Timer', node);
      if (name == 'listen')
        resources.add({
          'file': file,
          'line': line(node),
          'type': 'stream.listen',
          'owner': owner(node),
        });
    }
    super.visitMethodInvocation(node);
  }
}

Future<void> main(List<String> args) async {
  final stage = args.single;
  if (!['before', 'after'].contains(stage)) throw ArgumentError('before|after');
  final tracked =
      (await Process.run('git', ['ls-files', '--', 'apps/client'])).stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .where((f) => f.endsWith('.dart') && File(f).existsSync())
          .toList()
        ..sort();
  final production = tracked
      .where((f) => f.startsWith('apps/client/lib/'))
      .toSet();
  final edges = <String, Set<String>>{},
      packages = <String, Set<String>>{},
      platformEdges = <Map<String, String>>[];
  final parseErrors = <Map<String, dynamic>>[];
  String? target(String from, String uri) {
    if (uri.startsWith('package:queueb_client/'))
      return 'apps/client/lib/${uri.substring('package:queueb_client/'.length)}';
    if (Uri.parse(uri).hasScheme) return null;
    return p.normalize(p.join(p.dirname(from), uri)).replaceAll('\\', '/');
  }

  for (final file in tracked) {
    final result = parseString(
      content: File(file).readAsStringSync(),
      path: p.absolute(file),
      throwIfDiagnostics: false,
    );
    if (result.errors.isNotEmpty)
      parseErrors.add({
        'file': file,
        'diagnostics': result.errors.map((e) => e.diagnosticCode.name).toList(),
      });
    result.unit.accept(InventoryVisitor(file, result.unit));
    final links = edges.putIfAbsent(file, () => {});
    for (final directive in result.unit.directives) {
      if (directive is UriBasedDirective) {
        final uris = <String>[
          if (directive.uri.stringValue case final String uri) uri,
        ];
        if (directive is NamespaceDirective) {
          for (final config in directive.configurations) {
            if (config.uri.stringValue case final String uri) {
              uris.add(uri);
              platformEdges.add({
                'file': file,
                'condition': config.name.toSource(),
                'uri': uri,
              });
            }
          }
        }
        for (final uri in uris) {
          if (uri.startsWith('package:'))
            packages
                .putIfAbsent(uri.substring(8).split('/').first, () => {})
                .add(file);
          final destination = target(file, uri);
          if (destination != null) links.add(destination);
        }
      }
    }
  }
  Set<String> reachable(Iterable<String> roots) {
    final seen = <String>{}, queue = roots.toList();
    while (queue.isNotEmpty) {
      final file = queue.removeLast();
      if (!seen.add(file)) continue;
      queue.addAll(edges[file] ?? {});
    }
    return seen;
  }

  final appReachable = reachable(['apps/client/lib/main.dart']);
  final testReachable = reachable(
    tracked.where(
      (f) =>
          f.startsWith('apps/client/test/') ||
          f.startsWith('apps/client/integration_test/'),
    ),
  );
  bool inherits(Map<String, dynamic> c, String base, [Set<String>? visited]) {
    final parent = c['superclass'];
    if (parent == base) return true;
    final seen = visited ?? <String>{};
    if (parent == null || !seen.add(parent)) return false;
    final parents = classes.where((v) => v['name'] == parent);
    return parents.any((v) => inherits(v, base, seen));
  }

  final appClasses = classes
      .where((v) => production.contains(v['file']))
      .toList();
  final review = <Map<String, dynamic>>[];
  for (final d in declarations.where(
    (v) =>
        production.contains(v['file']) && !v['name'].toString().startsWith('_'),
  )) {
    final refs = (references[d['name']] ?? [])
        .where(
          (r) =>
              !(r['file'] == d['file'] &&
                  r['offset'] >= d['offset'] &&
                  r['offset'] < d['end']),
        )
        .toList();
    if (refs.isEmpty && d['name'] != 'main')
      review.add({
        ...d,
        'externalIdentifierReferences': 0,
        'decision': 'REVIEW; inspect config/generated/dynamic/untracked consumers manually',
      });
  }
  final pubspec =
      loadYaml(File('apps/client/pubspec.yaml').readAsStringSync()) as YamlMap;
  final deps = <Map<String, dynamic>>[];
  for (final group in ['dependencies', 'dev_dependencies']) {
    for (final entry in (pubspec[group] as YamlMap).entries) {
      deps.add({
        'name': entry.key,
        'group': group,
        'spec': entry.value.toString(),
        'dartImporters': (packages[entry.key] ?? {}).toList()..sort(),
      });
    }
  }
  final output = {
    'stage': stage,
    'measuredAt': DateTime.now().toUtc().toIso8601String(),
    'method': 'analyzer13.3 parse AST; git-tracked Dart; all conditional branches; lexical identifier candidates require manual resolution; counts are declaration/allocation sites, not live instances',
    'parseDiagnostics': parseErrors,
    'trackedDartFiles': tracked.length,
    'productionFiles': production.length,
    'appReachableProductionFiles': production.intersection(appReachable).length,
    'productionFilesOutsideEntryGraph':
        production.difference(appReachable).toList()..sort(),
    'productionFilesOutsideEntryAndTestGraph':
        production.difference(appReachable.union(testReachable)).toList()
          ..sort(),
    'counts': {
      'classDeclarations': appClasses.length,
      'repositories': appClasses
          .where((c) => c['name'].toString().endsWith('Repository'))
          .length,
      'repositoryConcrete': appClasses
          .where(
            (c) =>
                c['name'].toString().endsWith('Repository') && !c['abstract'],
          )
          .length,
      'cubitsIncludingLocalSubclasses': appClasses
          .where((c) => inherits(c, 'Cubit'))
          .length,
      'blocsIncludingLocalSubclasses': appClasses
          .where((c) => inherits(c, 'Bloc'))
          .length,
      'changeNotifierExplicitLocalHierarchy': appClasses
          .where((c) => inherits(c, 'ChangeNotifier'))
          .length,
      'setStateCallSites': calls['setState'] ?? 0,
      'resourceAllocationSites': resources.length,
      'addListenerCallSites': calls['addListener'] ?? 0,
      'removeListenerCallSites': calls['removeListener'] ?? 0,
    },
    'classes': appClasses,
    'zeroReferenceReviewCandidates': review,
    'declarationReferences': {
      for (final d in declarations.where((v) => production.contains(v['file'])))
        d['name'] as String: references[d['name']] ?? [],
    },
    'resources': resources,
    'productionMethodCalls': calls,
    'dependencies': deps,
    'conditionalDirectives': platformEdges,
    'edges': {
      for (final entry in edges.entries)
        entry.key: entry.value.toList()..sort(),
    },
  };
  final destination = File(
    'docs/frontend/cleanup-evidence/$stage-architecture.json',
  );
  destination.parent.createSync(recursive: true);
  destination.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(output)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'stage': stage,
      'counts': output['counts'],
      'tracked': tracked.length,
      'production': production.length,
      'unreachable': output['productionFilesOutsideEntryGraph'],
      'review': review.map((d) => '${d['name']}@${d['file']}').toList(),
      'parseDiagnostics': parseErrors,
    }),
  );
}
