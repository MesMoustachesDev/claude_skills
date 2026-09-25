import 'package:json_annotation/json_annotation.dart';

part '{{name.snakeCase()}}_data_model.g.dart';

@JsonSerializable()
class {{name.pascalCase()}}DataModel {
  const {{name.pascalCase()}}DataModel({required this.id});

  factory {{name.pascalCase()}}DataModel.fromJson(Map<String, dynamic> json) =>
      _${{name.pascalCase()}}DataModelFromJson(json);

  @JsonKey(name: r'$id')
  final String id;

  Map<String, dynamic> toJson() => _${{name.pascalCase()}}DataModelToJson(this);
}
