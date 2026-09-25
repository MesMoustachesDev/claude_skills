// Supprime les fichiers des options désactivées : Mason génère tout, on retire ce qui n'est pas demandé.
import 'dart:io';
import 'package:mason/mason.dart';

void run(HookContext context) {
  final name = (context.vars['name'] as String);
  final snake = name.snakeCase;
  final root = Directory(snake);
  bool on(String key) => context.vars[key] == true;

  final drop = <String>[
    if (!on('remote')) ...[
      'lib/src/domain/repository/${snake}_remote_data_source.dart',
      'lib/src/data/datasource/${snake}_remote_data_source_impl.dart',
      'lib/src/data/model/${snake}_data_model.dart',
      'lib/src/data/mapper/${snake}_mapper.dart',
      'lib/src/domain/usecase/fetch_${snake}_usecase.dart',
    ],
    if (!on('local')) ...[
      'lib/src/domain/repository/${snake}_local_data_source.dart',
      'lib/src/data/datasource/${snake}_local_data_source_impl.dart',
      'lib/src/domain/usecase/watch_${snake}_usecase.dart',
    ],
    if (!on('bloc')) ...[
      'lib/src/presentation/bloc/${snake}_bloc.dart',
      'lib/src/presentation/bloc/${snake}_event.dart',
      'lib/src/presentation/bloc/${snake}_state.dart',
      'test/src/presentation/bloc/${snake}_bloc_test.dart',
    ],
    if (!on('presentation')) ...[
      'lib/src/presentation/view/${snake}_page.dart',
      'lib/src/presentation/keys.dart',
    ],
  ];
  for (final rel in drop) {
    final f = File('${root.path}/$rel');
    if (f.existsSync()) f.deleteSync();
  }
  // Dossiers vides
  for (final d in root.listSync(recursive: true).whereType<Directory>().toList().reversed) {
    if (d.listSync().isEmpty) d.deleteSync();
  }
  // Les conditionnels mustache produisent des lignes longues : on formate pour que le gate
  // `format` soit vert dès le scaffold. `dart` est celui du PATH (le SDK du projet via le gauntlet).
  final fmt = Process.runSync('dart', ['format', root.path]);
  if (fmt.exitCode != 0) {
    context.logger.warn('dart format a échoué : ${fmt.stderr}');
  }
  context.logger.info('feature "$snake" générée dans ${root.path}/');
}
