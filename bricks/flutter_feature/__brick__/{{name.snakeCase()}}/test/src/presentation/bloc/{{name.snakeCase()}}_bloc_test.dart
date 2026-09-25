import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}/src/presentation/bloc/{{name.snakeCase()}}_bloc.dart';

void main() {
  late {{name.pascalCase()}}Bloc sut;

  setUp(() {
    sut = {{name.pascalCase()}}Bloc();
  });

  tearDown(() {
    sut.close();
  });

  test('initial state is {{name.pascalCase()}}Initial', () {
    expect(sut.state, isA<{{name.pascalCase()}}Initial>());
  });
}
