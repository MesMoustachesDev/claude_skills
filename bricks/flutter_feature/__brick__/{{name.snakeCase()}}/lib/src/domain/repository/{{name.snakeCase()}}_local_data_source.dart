import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';

abstract class {{name.pascalCase()}}LocalDataSource {
  Stream<List<{{name.pascalCase()}}Entity>> watchAll();
  Future<void> save({{name.pascalCase()}}Entity entity);
}
