import 'package:core/dartz.dart';
import 'package:core/error.dart';
import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_repository.dart';

class Fetch{{name.pascalCase()}}UseCase {
  const Fetch{{name.pascalCase()}}UseCase({required this.repository});

  final {{name.pascalCase()}}Repository repository;

  Future<Either<ErrorEntity, {{name.pascalCase()}}Entity>> call(String id) => throw UnimplementedError();
}
