import 'package:core/riverpod.dart';
import 'package:{{name.snakeCase()}}/src/data/repository/{{name.snakeCase()}}_repository_impl.dart';{{#remote}}
import 'package:{{name.snakeCase()}}/src/data/datasource/{{name.snakeCase()}}_remote_data_source_impl.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_remote_data_source.dart';
import 'package:{{name.snakeCase()}}/src/domain/usecase/fetch_{{name.snakeCase()}}_usecase.dart';{{/remote}}{{#local}}
import 'package:{{name.snakeCase()}}/src/data/datasource/{{name.snakeCase()}}_local_data_source_impl.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_local_data_source.dart';
import 'package:{{name.snakeCase()}}/src/domain/usecase/watch_{{name.snakeCase()}}_usecase.dart';{{/local}}
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_repository.dart';{{#bloc}}
import 'package:{{name.snakeCase()}}/src/presentation/bloc/{{name.snakeCase()}}_bloc.dart';{{/bloc}}

// Ordre : data sources → repository → use cases → BLoC. Privés jusqu'au repository inclus.
{{#remote}}
final _remoteDataSourceProvider = AutoDisposeProvider<{{name.pascalCase()}}RemoteDataSource>(
  (ref) => const {{name.pascalCase()}}RemoteDataSourceImpl(),
);
{{/remote}}{{#local}}
final _localDataSourceProvider = AutoDisposeProvider<{{name.pascalCase()}}LocalDataSource>(
  (ref) => const {{name.pascalCase()}}LocalDataSourceImpl(),
);
{{/local}}
final _repositoryProvider = AutoDisposeProvider<{{name.pascalCase()}}Repository>(
  (ref) => {{name.pascalCase()}}RepositoryImpl({{#remote}}remoteDataSource: ref.watch(_remoteDataSourceProvider){{#local}}, localDataSource: ref.watch(_localDataSourceProvider){{/local}}{{/remote}}{{^remote}}{{#local}}localDataSource: ref.watch(_localDataSourceProvider){{/local}}{{/remote}}),
);
{{#remote}}
final fetch{{name.pascalCase()}}UseCaseProvider = AutoDisposeProvider<Fetch{{name.pascalCase()}}UseCase>(
  (ref) => Fetch{{name.pascalCase()}}UseCase(repository: ref.watch(_repositoryProvider)),
);
{{/remote}}{{#local}}
final watch{{name.pascalCase()}}UseCaseProvider = AutoDisposeProvider<Watch{{name.pascalCase()}}UseCase>(
  (ref) => Watch{{name.pascalCase()}}UseCase(repository: ref.watch(_repositoryProvider)),
);
{{/local}}{{#bloc}}
final {{name.camelCase()}}BlocProvider = AutoDisposeProvider<{{name.pascalCase()}}Bloc>(
  (ref) => {{name.pascalCase()}}Bloc(),
);
{{/bloc}}
