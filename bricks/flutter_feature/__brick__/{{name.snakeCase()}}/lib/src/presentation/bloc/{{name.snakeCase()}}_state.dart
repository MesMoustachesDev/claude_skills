part of '{{name.snakeCase()}}_bloc.dart';

sealed class {{name.pascalCase()}}State extends Equatable {
  const {{name.pascalCase()}}State();

  @override
  List<Object?> get props => [];
}

final class {{name.pascalCase()}}Initial extends {{name.pascalCase()}}State {
  const {{name.pascalCase()}}Initial();
}

final class {{name.pascalCase()}}Loading extends {{name.pascalCase()}}State {
  const {{name.pascalCase()}}Loading();
}

final class {{name.pascalCase()}}Empty extends {{name.pascalCase()}}State {
  const {{name.pascalCase()}}Empty();
}

final class {{name.pascalCase()}}Error extends {{name.pascalCase()}}State {
  const {{name.pascalCase()}}Error(this.error);

  final ErrorEntity error;

  @override
  List<Object?> get props => [error];
}
