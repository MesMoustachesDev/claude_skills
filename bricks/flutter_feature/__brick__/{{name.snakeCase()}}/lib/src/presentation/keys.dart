/// Clés de widgets — trois consommateurs : widget tests (ValueKey), Maestro (Semantics identifier),
/// implémentation (les deux). Nommage : {{name.snakeCase()}}_{écran}_{élément}.
abstract final class {{name.pascalCase()}}Keys {
  static const String page = '{{name.snakeCase()}}_page';
  static const String loading = '{{name.snakeCase()}}_loading';
  static const String error = '{{name.snakeCase()}}_error';
  static const String errorRetry = '{{name.snakeCase()}}_error_retry';
  static const String empty = '{{name.snakeCase()}}_empty';
}
