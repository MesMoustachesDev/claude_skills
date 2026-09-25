import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_local_data_source.dart';

class {{name.pascalCase()}}LocalDataSourceImpl implements {{name.pascalCase()}}LocalDataSource {
  const {{name.pascalCase()}}LocalDataSourceImpl();

  @override
  Stream<List<{{name.pascalCase()}}Entity>> watchAll() => throw UnimplementedError();

  @override
  Future<void> save({{name.pascalCase()}}Entity entity) => throw UnimplementedError();
}
