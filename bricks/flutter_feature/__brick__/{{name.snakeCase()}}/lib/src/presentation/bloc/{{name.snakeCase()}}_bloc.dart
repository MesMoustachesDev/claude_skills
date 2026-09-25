import 'package:core/bloc.dart';

part '{{name.snakeCase()}}_event.dart';
part '{{name.snakeCase()}}_state.dart';

class {{name.pascalCase()}}Bloc extends Bloc<{{name.pascalCase()}}Event, {{name.pascalCase()}}State> {
  {{name.pascalCase()}}Bloc() : super(const {{name.pascalCase()}}Initial()) {
    on<Load{{name.pascalCase()}}>(_onLoad);
  }

  // Handlers = méthodes (pas de closures) : le gate stub_check les vérifie une par une.
  Future<void> _onLoad(Load{{name.pascalCase()}} event, Emitter<{{name.pascalCase()}}State> emit) =>
      throw UnimplementedError();
}
