import 'package:core/dartz.dart';
import 'package:core/error.dart';
import 'package:{{name.snakeCase()}}/src/data/model/{{name.snakeCase()}}_data_model.dart';

abstract class {{name.pascalCase()}}RemoteDataSource {
  Future<Either<ErrorEntity, {{name.pascalCase()}}DataModel>> fetch(String id);
}
