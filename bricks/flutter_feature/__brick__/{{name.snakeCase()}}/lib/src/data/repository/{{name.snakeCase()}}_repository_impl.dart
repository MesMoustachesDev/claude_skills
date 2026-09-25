{{#remote}}import 'package:core/dartz.dart';
import 'package:core/error.dart';
{{/remote}}import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_repository.dart';{{#remote}}
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_remote_data_source.dart';{{/remote}}{{#local}}
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_local_data_source.dart';{{/local}}

class {{name.pascalCase()}}RepositoryImpl implements {{name.pascalCase()}}Repository {
  const {{name.pascalCase()}}RepositoryImpl({{#remote}}{required this.remoteDataSource{{#local}}, required this.localDataSource{{/local}}}{{/remote}}{{^remote}}{{#local}}{required this.localDataSource}{{/local}}{{/remote}});
{{#remote}}
  final {{name.pascalCase()}}RemoteDataSource remoteDataSource;
{{/remote}}{{#local}}
  final {{name.pascalCase()}}LocalDataSource localDataSource;
{{/local}}{{#remote}}
  @override
  Future<Either<ErrorEntity, {{name.pascalCase()}}Entity>> fetch(String id) => throw UnimplementedError();
{{/remote}}{{#local}}
  @override
  Stream<List<{{name.pascalCase()}}Entity>> watchAll() => throw UnimplementedError();

  @override
  Future<void> save({{name.pascalCase()}}Entity entity) => throw UnimplementedError();
{{/local}}}
