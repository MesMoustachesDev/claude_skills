// dup_check.dart — détecte la roue réinventée : une déclaration du package cible qui existe déjà
// ailleurs dans le workspace, par le NOM (fonction top-level, membre d'extension, méthode statique,
// classe, extension, enum, typedef publics) ou par le CORPS (même séquence de tokens à renommage et
// littéraux près — clone de type 2), y compris à l'intérieur du package.
//
// Usage : dart run bin/dup_check.dart --root <features_root> --package <package_dir>
//         [--min-tokens 25] [--ignore-names a,b,c]
// Exit 0 si rien, 1 si des doublons sont trouvés. Une déclaration précédée ou suivie sur sa ligne
// d'un commentaire contenant `gauntlet-ignore` est ignorée.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

const _skipNames = {
  // overrides et conventions Flutter/Dart : jamais des doublons
  'build', 'props', 'toString', 'call', 'fromJson', 'toJson', 'copyWith', 'initState', 'dispose',
  'close', 'main', 'createState', 'didChangeDependencies', 'didUpdateWidget', 'debugFillProperties',
  'noSuchMethod', 'compareTo', 'when', 'map', 'maybeWhen', 'maybeMap', 'fold', 'toEntity', 'toModel',
  'toDomain', 'toData', 'run', 'watch', 'fetch', 'get', 'save', 'delete', 'update', 'create',
  // statiques conventionnels : Modal.show(context), Foo.of(context), Bar.instance, init()
  'show', 'of', 'instance', 'init', 'parse', 'from', 'empty', 'initial',
};

class Decl {
  Decl(this.kind, this.name, this.file, this.line, this.pkg, this.isPublic, this.nameChecked,
      this.fingerprint, this.tokens);
  final String kind, name, file, pkg;
  final int line, tokens;
  final bool isPublic, nameChecked;
  final int? fingerprint; // null : pas de corps (classe, enum, abstrait)
  String get where => '$file:$line';
}

void main(List<String> args) {
  String? root, package;
  var minTokens = 40;
  final ignore = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--root':
        root = args[++i];
      case '--package':
        package = args[++i];
      case '--min-tokens':
        minTokens = int.parse(args[++i]);
      case '--ignore-names':
        ignore.addAll(args[++i].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }
  }
  if (root == null || package == null) {
    stderr.writeln('usage: dup_check.dart --root <features_root> --package <package_dir>');
    exit(2);
  }
  final rootDir = Directory(root);
  final pkgDir = p.normalize(p.absolute(package));

  final decls = <Decl>[];
  for (final f in rootDir.listSync(recursive: true).whereType<File>()) {
    final path = f.path;
    if (!path.endsWith('.dart')) continue;
    if (path.endsWith('.g.dart') || path.endsWith('.freezed.dart')) continue;
    if (path.contains('/.dart_tool/') || path.contains('/build/') || path.contains('/test/')) continue;
    if (!path.contains('/lib/')) continue;
    final pkgName = _packageOf(path, rootDir.path);
    final content = f.readAsStringSync();
    final unit = parseString(content: content, path: path, featureSet: FeatureSet.latestLanguageVersion(),
            throwIfDiagnostics: false)
        .unit;
    final inTarget = p.normalize(p.absolute(path)).startsWith('$pkgDir/');
    unit.accept(_Collector(decls, content, p.relative(path, from: rootDir.path), pkgName, unit, inTarget));
  }

  final target = decls.where((d) => d.pkg == _packageOf(pkgDir, rootDir.path) || _inDir(d.file, pkgDir, rootDir.path)).toList();
  final others = decls.where((d) => !target.contains(d)).toList();

  final findings = <String>[];

  // 1. Collision de nom public hors du package.
  final byName = <String, List<Decl>>{};
  for (final d in others) {
    if (d.isPublic && d.nameChecked) byName.putIfAbsent(d.name, () => []).add(d);
  }
  for (final d in target) {
    if (!d.isPublic || !d.nameChecked || d.name.length < 4) continue;
    final bare = d.name.contains('.') ? d.name.split('.').last : d.name;
    if (_skipNames.contains(bare) || ignore.contains(bare)) continue;
    final same = byName[d.name];
    if (same == null) continue;
    for (final o in same.take(3)) {
      findings.add('nom    ${d.kind} ${d.name}  ${d.where}  existe déjà : ${o.where} (${o.pkg})');
    }
  }

  // 2. Clone de corps (type 2) : dans le workspace et dans le package lui-même.
  final byFp = <int, List<Decl>>{};
  for (final d in decls) {
    if (d.fingerprint != null && d.tokens >= minTokens) byFp.putIfAbsent(d.fingerprint!, () => []).add(d);
  }
  final seen = <String>{};
  for (final d in target) {
    if (d.fingerprint == null || d.tokens < minTokens) continue;
    final bare = d.name.contains('.') ? d.name.split('.').last : d.name;
    if (_skipNames.contains(bare) || ignore.contains(bare)) continue; // copyWith, call… : boilerplate
    for (final o in byFp[d.fingerprint!] ?? const <Decl>[]) {
      if (identical(o, d) || o.where == d.where) continue;
      final key = [d.where, o.where]..sort();
      if (!seen.add(key.join('|'))) continue;
      findings.add('corps  ${d.kind} ${d.name}  ${d.where}  ≡ ${o.kind} ${o.name}  ${o.where} (${o.pkg}, ${d.tokens} tokens)');
    }
  }

  stdout.writeln('   ${target.length} déclaration(s) du package, ${others.length} ailleurs, ${findings.length} doublon(s)');
  for (final f in findings) {
    stdout.writeln('   ✗ $f');
  }
  exit(findings.isEmpty ? 0 : 1);
}

String _packageOf(String path, String root) {
  final rel = p.relative(path, from: root);
  final parts = p.split(rel);
  final libIdx = parts.indexOf('lib');
  return libIdx > 0 ? parts.sublist(0, libIdx).join('/') : parts.first;
}

bool _inDir(String relFile, String absDir, String root) => p.normalize(p.join(root, relFile)).startsWith('$absDir/');

class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.out, this.content, this.file, this.pkg, this.unit, this.inTarget);
  final List<Decl> out;
  final String content, file, pkg;
  final CompilationUnit unit;
  final bool inTarget;

  int _line(AstNode n) => unit.lineInfo.getLocation(n.offset).lineNumber;

  bool _ignored(AstNode n) {
    final line = _line(n);
    final lines = content.split('\n');
    bool has(int l) => l >= 1 && l <= lines.length && lines[l - 1].contains('gauntlet-ignore');
    return has(line) || has(line - 1);
  }

  void _add(String kind, String name, AstNode node, {FunctionBody? body, bool nameChecked = true}) {
    if (_ignored(node)) return;
    int? fp;
    var count = 0;
    if (body != null && body is! EmptyFunctionBody) {
      final norm = _normalize(body);
      count = norm.length;
      fp = norm.join(' ').hashCode;
    }
    out.add(Decl(kind, name, file, _line(node), pkg, !name.startsWith('_'), nameChecked, fp, count));
  }

  // Type 2 : identifiants et littéraux effacés — sauf les membres appelés après un `.`, gardés
  // tels quels. Un copier-coller renommé appelle les mêmes API et matche encore ; une simple
  // délégation `repository.fetch(id)` vs `repository.save(x)` ne matche plus.
  static List<String> _normalize(FunctionBody body) {
    final toks = <String>[];
    Token? t = body.beginToken;
    final end = body.endToken;
    while (t != null) {
      if (t.type == TokenType.IDENTIFIER) {
        final prev = t.previous;
        toks.add(prev != null && (prev.type == TokenType.PERIOD || prev.type == TokenType.QUESTION_PERIOD) ? t.lexeme : 'I');
      } else if (t.type == TokenType.STRING || t.type == TokenType.INT || t.type == TokenType.DOUBLE ||
          t.type == TokenType.HEXADECIMAL || t.type == TokenType.STRING_INTERPOLATION_IDENTIFIER) {
        toks.add('L');
      } else if (t.type != TokenType.EOF) {
        toks.add(t.lexeme);
      }
      if (t == end) break;
      t = t.next;
    }
    return toks;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is CompilationUnit) {
      _add('fonction', node.name.lexeme, node, body: node.functionExpression.body);
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final ext = node.thisOrAncestorOfType<ExtensionDeclaration>();
    final isStatic = node.isStatic;
    // Nom vérifié seulement pour extensions et statiques ; les méthodes d'instance ne sont
    // comparées que par leur corps (un `fetch` sur deux repositories n'est pas un doublon).
    // Un membre d'extension est qualifié par le type étendu : `String.capitalize` collisionne avec
    // `String.capitalize`, pas `CategoryEntity.toDao` avec `RecipeEntity.toDao`.
    if (ext != null) {
      final on = ext.onClause?.extendedType.toSource() ?? '?';
      _add('extension sur $on', '$on.${node.name.lexeme}', node, body: node.body);
    } else {
      _add(isStatic ? 'static' : 'méthode', node.name.lexeme, node, body: node.body, nameChecked: isStatic);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _add('classe', node.namePart.typeName.lexeme, node);
    super.visitClassDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final n = node.name?.lexeme;
    if (n != null) _add('extension', n, node);
    super.visitExtensionDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _add('enum', node.namePart.typeName.lexeme, node);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _add('mixin', node.name.lexeme, node);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _add('typedef', node.name.lexeme, node);
    super.visitGenericTypeAlias(node);
  }
}
