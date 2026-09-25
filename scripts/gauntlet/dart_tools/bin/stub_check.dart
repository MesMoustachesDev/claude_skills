// stub_check.dart — vérifie qu'après l'étape ARCHITECT, chaque méthode des fichiers
// d'implémentation est un stub : `throw UnimplementedError(...)`, en bloc ou en expression.
//
// Usage : dart run bin/stub_check.dart --root <package_dir> <fichier relatif>...
// Exit 0 si tout est stub, 1 sinon. Constructeurs, méthodes abstraites/externes ignorés.
//
// Pourquoi une analyse AST et pas un grep : compter des méthodes en bash est faux dès qu'il y a
// un `=>` dans une string ou une closure. L'AST ne se trompe pas.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  String root = '.';
  final files = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) {
      root = args[++i];
    } else {
      files.add(args[i]);
    }
  }
  if (files.isEmpty) {
    stderr.writeln('usage: stub_check.dart --root <dir> <file>...');
    exit(2);
  }

  var methods = 0;
  final violations = <String>[];
  for (final rel in files) {
    final abs = p.normalize(p.join(root, rel));
    if (!File(abs).existsSync()) {
      violations.add('$rel : fichier introuvable');
      continue;
    }
    final unit = parseFile(
      path: abs,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;
    final visitor = _StubVisitor(rel, unit);
    unit.accept(visitor);
    methods += visitor.methods;
    violations.addAll(visitor.violations);
  }

  stdout.writeln('   $methods méthode(s) inspectée(s), ${violations.length} non-stub');
  for (final v in violations) {
    stdout.writeln('   ✗ $v');
  }
  if (methods == 0) {
    stdout.writeln('   ✗ aucune méthode trouvée : les contrats ne sont pas posés');
    exit(1);
  }
  exit(violations.isEmpty ? 0 : 1);
}

class _StubVisitor extends RecursiveAstVisitor<void> {
  _StubVisitor(this.file, this.unit);
  final String file;
  final CompilationUnit unit;
  int methods = 0;
  final violations = <String>[];

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // Abstraite (`;`) ou externe : pas de corps à vérifier.
    if (node.body is EmptyFunctionBody || node.externalKeyword != null) return;
    methods++;
    if (!_isStubBody(node.body)) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      final owner = _ownerName(node);
      violations.add('$file:$line  ${owner.isEmpty ? '' : '$owner.'}${node.name.lexeme}');
    }
    // Pas de récursion : les closures internes d'un stub n'existent pas.
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.externalKeyword != null) return;
    // Fonctions top-level uniquement (les locales sont dans des corps déjà rejetés).
    if (node.parent is! CompilationUnit) return;
    methods++;
    if (!_isStubBody(node.functionExpression.body)) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      violations.add('$file:$line  ${node.name.lexeme}');
    }
  }

  static String _ownerName(AstNode node) {
    // Le parent direct peut être un corps de classe : on remonte jusqu'à la déclaration.
    // analyzer ≥ 14 : les classes et enums exposent leur nom via namePart.typeName.
    final cls = node.thisOrAncestorOfType<ClassDeclaration>();
    if (cls != null) return cls.namePart.typeName.lexeme;
    final en = node.thisOrAncestorOfType<EnumDeclaration>();
    if (en != null) return en.namePart.typeName.lexeme;
    final ext = node.thisOrAncestorOfType<ExtensionDeclaration>();
    if (ext != null) return ext.name?.lexeme ?? 'extension';
    final mix = node.thisOrAncestorOfType<MixinDeclaration>();
    if (mix != null) return mix.name.lexeme;
    return '';
  }

  static bool _isStubBody(FunctionBody body) {
    if (body is ExpressionFunctionBody) return _isUnimplementedThrow(body.expression);
    if (body is BlockFunctionBody) {
      final stmts = body.block.statements;
      if (stmts.length != 1) return false;
      final s = stmts.single;
      return s is ExpressionStatement && _isUnimplementedThrow(s.expression);
    }
    return false; // EmptyFunctionBody (;) = abstrait, déjà filtré ; NativeFunctionBody = non
  }

  static bool _isUnimplementedThrow(Expression e) {
    if (e is! ThrowExpression) return false;
    final src = e.expression.toSource();
    return src.startsWith('UnimplementedError(') || src.startsWith('const UnimplementedError(');
  }
}
