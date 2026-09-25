library;

export 'src/injection/{{name.snakeCase()}}_di.dart';
export 'src/domain/model/{{name.snakeCase()}}_entity.dart';
export 'src/domain/repository/{{name.snakeCase()}}_repository.dart';{{#remote}}
export 'src/domain/usecase/fetch_{{name.snakeCase()}}_usecase.dart';{{/remote}}{{#local}}
export 'src/domain/usecase/watch_{{name.snakeCase()}}_usecase.dart';{{/local}}{{#presentation}}
export 'src/presentation/keys.dart';
export 'src/presentation/view/{{name.snakeCase()}}_page.dart';{{/presentation}}
