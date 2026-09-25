{{#remote}}import 'package:core/dartz.dart';
import 'package:core/error.dart';
{{/remote}}import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';

abstract class {{name.pascalCase()}}Repository {
{{#remote}}  Future<Either<ErrorEntity, {{name.pascalCase()}}Entity>> fetch(String id);
{{/remote}}{{#local}}  Stream<List<{{name.pascalCase()}}Entity>> watchAll();
  Future<void> save({{name.pascalCase()}}Entity entity);
{{/local}}}
