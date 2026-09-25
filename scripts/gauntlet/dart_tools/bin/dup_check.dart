// dup_check.dart — détecte la roue réinventée : une déclaration du package cible qui existe déjà
// ailleurs dans le workspace, par le NOM (fonction top-level, membre d'extension, méthode statique,
// classe, extension, enum, typedef publics) ou par le CORPS (même séquence de tokens à renommage et
// littéraux près — clone de type 2), y compris à l'intérieur du package.
//
// Usage : dart run bin/dup_check.dart --root <features_root> --package <package_dir>
//         [--min-tokens 40] [--ignore-names a,b,c] [--candidates <out.json>]
// Exit 0 si rien, 1 si des doublons sont trouvés. Une déclaration précédée ou suivie sur sa ligne
// d'un commentaire contenant `gauntlet-ignore` est ignorée.
//
// --candidates : mode "roue réinventée par la responsabilité". Le script ne juge pas ; il écrit, pour
// chaque déclaration publique du package, les déclarations du workspace qui LUI RESSEMBLENT (tokens
// du nom, type étendu, signature, kind) avec leur signature et leur doc. Un agent lit ce JSON et
// tranche : même responsabilité, à étendre, ou distinct. L'IA là où elle détecte mieux, sur un
// espace de recherche que le script a réduit de 8 000 déclarations à quelques-unes.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
      this.fingerprint, this.tokens, this.signature, this.doc, this.onType);
  final String kind, name, file, pkg, signature, doc;
  final String? onType;
  final int line, tokens;
  final bool isPublic, nameChecked;
  final int? fingerprint; // null : pas de corps (classe, enum, abstrait)
  String get where => '$file:$line';
  String get bare => name.contains('.') ? name.split('.').last : name;

  Map<String, Object?> toJson() => {
        'kind': kind, 'name': name, 'file': file, 'line': line, 'package': pkg,
        'signature': signature, 'doc': doc, if (onType != null) 'on': onType,
      };
}

const _stopTokens = {
  'get', 'set', 'build', 'on', 'to', 'from', 'is', 'has', 'use', 'case', 'usecase', 'impl', 'entity',
  'model', 'dao', 'data', 'source', 'repository', 'remote', 'local', 'page', 'view', 'widget', 'bloc',
  'event', 'state', 'provider', 'di', 'keys', 'the', 'a', 'an', 'x', 'ext', 'extension', 'mapper',
  'screen', 'item', 'list', 'card', 'with', 'by', 'for', 'of', 'in', 'and', 'or', 'new', 'all',
};

/// `fetchUserProfile` → {fetch, user, profile} ; `HTTPClient` → {http, client}.
Set<String> _nameTokens(String name) {
  final bare = name.contains('.') ? name.split('.').last : name;
  final parts = bare
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}')
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'));
  return parts.where((t) => t.length > 1 && !_stopTokens.contains(t)).map(_stem).toSet();
}

String _stem(String t) {
  for (final suf in ['ies', 'ing', 'ers', 'er', 'es', 's']) {
    if (t.length > 4 && t.endsWith(suf)) return t.substring(0, t.length - suf.length) + (suf == 'ies' ? 'y' : '');
  }
  return t;
}

void main(List<String> args) {
  String? root, package, candidatesOut;
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
      case '--candidates':
        candidatesOut = args[++i];
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

  if (candidatesOut != null) {
    _writeCandidates(candidatesOut, target, others, ignore);
    return;
  }

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

/// Types de l'architecture : une feature en a forcément un jeu (entity, data model, DAO, mapper,
/// repository, bloc…). Ce ne sont pas des roues réinventées, et un doublon de NOM entre eux est
/// déjà attrapé par le mode normal. Restent les vraies candidates : utilitaires, extensions,
/// services, widgets, enums.
final _archSuffix = RegExp(
    r'(Impl|Bloc|Event|State|UseCase|Usecase|Page|Screen|Keys|Di|Route|Entity|DataModel|UiModel|Dao|DaoX|DataSource|Repository|Mapper|MapperX|Params|Request|Response|Funnel|Viewed|Tapped)$');

/// Candidats par ressemblance, pour l'agent feature-dedup. Score = somme des poids IDF des tokens de
/// nom partagés (un token présent partout ne vaut rien, un token rare vaut beaucoup), +2 même type
/// étendu, +1 même liste de types de paramètres. Même famille (type ↔ type, callable ↔ callable).
void _writeCandidates(String out, List<Decl> target, List<Decl> others, Set<String> ignore) {
  // Events et states de BLoC vivent sous /bloc/ : un jeu par feature, jamais des roues.
  bool reusable(Decl o) =>
      o.isPublic &&
      !(o.kind == 'méthode' && o.onType == null) &&
      !o.file.contains('/bloc/') &&
      !_archSuffix.hasMatch(o.bare) &&
      !_archSuffix.hasMatch(o.onType ?? '');
  final pool = others.where(reusable).map((o) => (o, _nameTokens(o.name))).toList();
  // IDF sur l'ensemble du workspace
  final df = <String, int>{};
  for (final (_, toks) in pool) {
    for (final t in toks) {
      df[t] = (df[t] ?? 0) + 1;
    }
  }
  final n = pool.length + 1;
  double w(String t) => log(n / ((df[t] ?? 0) + 1));

  final entries = <Map<String, Object?>>[];
  var pairs = 0;
  for (final d in target) {
    if (!reusable(d) || _skipNames.contains(d.bare) || ignore.contains(d.bare)) continue;
    if (_archSuffix.hasMatch(d.bare)) continue;
    final toks = _nameTokens(d.name);
    if (toks.isEmpty) continue;
    final scored = <(Decl, double)>[];
    for (final (o, otoks) in pool) {
      if (_family(d.kind) != _family(o.kind)) continue;
      var s = toks.intersection(otoks).fold(0.0, (acc, t) => acc + w(t));
      if (s <= 0) continue;
      if (d.onType != null && d.onType == o.onType) s += 2;
      if (d.signature.isNotEmpty && _paramTypes(d.signature) == _paramTypes(o.signature)) s += 1;
      if (s >= 3.0) scored.add((o, s));
    }
    if (scored.isEmpty) continue;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final top = scored.take(3).toList();
    pairs += top.length;
    entries.add({
      'target': d.toJson(),
      'candidates': [for (final (o, s) in top) {...o.toJson(), 'score': double.parse(s.toStringAsFixed(1))}],
    });
  }
  File(out).writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'package': target.isEmpty ? '' : target.first.pkg,
    'targets': entries.length,
    'pairs': pairs,
    'entries': entries,
  }));
  stdout.writeln('   ${entries.length} déclaration(s) avec candidat(s), $pairs paire(s) à juger → $out');
}

String _family(String kind) {
  if (kind.startsWith('extension')) return 'extension';
  if (kind == 'fonction' || kind == 'static' || kind == 'méthode') return 'callable';
  return 'type';
}

String _paramTypes(String signature) {
  // "(String id, {required int count})" → "String,int"
  final m = RegExp(r'\((.*)\)').firstMatch(signature);
  if (m == null) return '';
  return m.group(1)!
      .replaceAll(RegExp(r'[{}\[\]]|required |this\.'), '')
      .split(',')
      .map((p) => p.trim().split(RegExp(r'\s+')).first)
      .where((t) => t.isNotEmpty)
      .join(',');
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

  void _add(String kind, String name, AstNode node,
      {FunctionBody? body, bool nameChecked = true, String signature = '', String? onType}) {
    if (_ignored(node)) return;
    int? fp;
    var count = 0;
    if (body != null && body is! EmptyFunctionBody) {
      final norm = _normalize(body);
      count = norm.length;
      fp = norm.join(' ').hashCode;
    }
    final bare = name.contains('.') ? name.split('.').last : name;
    out.add(Decl(kind, name, file, _line(node), pkg, !bare.startsWith('_'), nameChecked, fp, count,
        signature, _doc(node), onType));
  }

  static String _doc(AstNode node) {
    final d = node is AnnotatedNode ? node.documentationComment : null;
    if (d == null) return '';
    return d.tokens.map((t) => t.lexeme.replaceFirst(RegExp(r'^///?\s?'), '')).join(' ').trim();
  }

  static String _sigOf(FormalParameterList? params, TypeAnnotation? ret) =>
      '${ret?.toSource() ?? ''} ${params?.toSource() ?? ''}'.trim();

  static String _classSig(ClassDeclaration node) {
    // analyzer ≥ 14 : les membres sont sous node.body.
    final members = node.body.members
        .whereType<MethodDeclaration>()
        .map((m) => m.name.lexeme)
        .where((n) => !n.startsWith('_'))
        .take(12)
        .join(', ');
    final ext = node.extendsClause?.superclass.toSource();
    final impl = node.implementsClause?.interfaces.map((i) => i.toSource()).join(', ');
    return [if (ext != null) 'extends $ext', if (impl != null && impl.isNotEmpty) 'implements $impl', if (members.isNotEmpty) '{ $members }'].join(' ');
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
      _add('fonction', node.name.lexeme, node, body: node.functionExpression.body,
          signature: _sigOf(node.functionExpression.parameters, node.returnType));
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
    final sig = _sigOf(node.parameters, node.returnType);
    if (ext != null) {
      final on = ext.onClause?.extendedType.toSource() ?? '?';
      _add('extension sur $on', '$on.${node.name.lexeme}', node, body: node.body, signature: sig, onType: on);
    } else {
      _add(isStatic ? 'static' : 'méthode', node.name.lexeme, node, body: node.body, nameChecked: isStatic, signature: sig);
    }
    super.visitMethodDeclaration(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _add('classe', node.namePart.typeName.lexeme, node, signature: _classSig(node));
    super.visitClassDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final n = node.name?.lexeme;
    final on = node.onClause?.extendedType.toSource();
    if (n != null) _add('extension', n, node, signature: on == null ? '' : 'on $on', onType: on);
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
