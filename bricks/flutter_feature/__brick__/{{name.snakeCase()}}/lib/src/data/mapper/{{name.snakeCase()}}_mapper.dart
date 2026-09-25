import 'package:{{name.snakeCase()}}/src/data/model/{{name.snakeCase()}}_data_model.dart';
import 'package:{{name.snakeCase()}}/src/domain/model/{{name.snakeCase()}}_entity.dart';

extension {{name.pascalCase()}}DataModelMapper on {{name.pascalCase()}}DataModel {
  {{name.pascalCase()}}Entity toEntity() => throw UnimplementedError();
}
