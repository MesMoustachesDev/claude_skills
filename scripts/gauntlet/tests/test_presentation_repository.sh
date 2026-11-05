#!/usr/bin/env bash
# Repro — deps : presentation ne référence aucun type *Repository ; le BLoC passe par un use case, et c'est
# le use case qui parle au repository (report d'erreur compris).
#   mode extend : un BLoC qui dépend déjà d'ErrorRepository sur develop → dette existante, pas bloquant ;
#                 un repository ajouté par la feature dans presentation → FAIL.
#   pas de faux positifs : RepositoryProvider (flutter_bloc), commentaires, gauntlet-ignore.
# Cas réel : plans_bloc.dart pousse les Left de ses use cases dans ErrorRepository (feature image_source).
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/lib/src/presentation/old/bloc" "$R/$P/lib/src/presentation/new/bloc"
cat > "$R/$P/lib/src/presentation/old/bloc/old_bloc.dart" <<'EOF'
class OldBloc {
  OldBloc({required this.errorRepository});
  final ErrorRepository errorRepository;
}
EOF
cat > "$R/$P/lib/src/presentation/new/bloc/new_bloc.dart" <<'EOF'
// Le BLoC ne connaît pas le PicturesRepository : il passe par le use case.
class NewBloc {
  Widget build() => RepositoryProvider(child: null);
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "deps — repository déjà présent sur develop"
run_g "$R" deps x
expect_rc 0 "vert : l'existant n'est pas bloquant"
expect_file_has "$R/.claude/features/x/.gauntlet/debt_deps.txt" "old_bloc.dart:3: presentation → repository (ErrorRepository)" "ErrorRepository de old_bloc listé en dette"
expect_no_out "new_bloc.dart" "ni RepositoryProvider ni le commentaire ne sont signalés"

echo "deps — repository ajouté par la feature"
cat >> "$R/$P/lib/src/presentation/new/bloc/new_bloc.dart" <<'EOF'
class NewBlocWithRepo {
  NewBlocWithRepo(this.picturesRepository);
  final PicturesRepository picturesRepository;
}
EOF
run_g "$R" deps x
expect_rc 1 "rouge"
expect_out "new_bloc.dart:7: presentation → repository (PicturesRepository) interdit" "la ligne ajoutée est nommée"

echo "deps — gauntlet-ignore exempte la ligne"
sed -i '' 's#final PicturesRepository picturesRepository;#final PicturesRepository picturesRepository; // gauntlet-ignore: test#' "$R/$P/lib/src/presentation/new/bloc/new_bloc.dart"
sed -i '' 's#NewBlocWithRepo(this.picturesRepository);#NewBlocWithRepo(this.picturesRepository); // gauntlet-ignore: test#' "$R/$P/lib/src/presentation/new/bloc/new_bloc.dart"
run_g "$R" deps x
expect_rc 0 "vert"

finish
