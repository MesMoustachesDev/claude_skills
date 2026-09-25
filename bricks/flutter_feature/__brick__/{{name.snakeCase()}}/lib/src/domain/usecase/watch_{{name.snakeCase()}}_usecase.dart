import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_repository.dart';

class Watch{{name.pascalCase()}}UseCase {
  const Watch{{name.pascalCase()}}UseCase({required this.repository});

  final {{name.pascalCase()}}Repository repository;

  Stream<List<{{name.pascalCase()}}Entity>> call() => throw UnimplementedError();
}
