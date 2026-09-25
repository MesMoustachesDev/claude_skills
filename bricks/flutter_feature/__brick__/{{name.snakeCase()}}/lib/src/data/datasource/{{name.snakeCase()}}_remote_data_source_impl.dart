import 'package:core/dartz.dart';
import 'package:core/error.dart';
import 'package:{{name.snakeCase()}}/src/data/model/{{name.snakeCase()}}_data_model.dart';
import 'package:{{name.snakeCase()}}/src/domain/repository/{{name.snakeCase()}}_remote_data_source.dart';

class {{name.pascalCase()}}RemoteDataSourceImpl implements {{name.pascalCase()}}RemoteDataSource {
  const {{name.pascalCase()}}RemoteDataSourceImpl();

  @override
  Future<Either<ErrorEntity, {{name.pascalCase()}}DataModel>> fetch(String id) => throw UnimplementedError();
}
