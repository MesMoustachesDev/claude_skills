#!/usr/bin/env bash
# Repro — deps : une vue (presentation hors bloc/) ne référence aucun use case ; elle lit son BLoC dans un
# provider de la DI. Le BLoC, lui, reçoit ses use cases.
# Cas réel : add_floors_wizard_page.dart recevait GetDefaultFloorNamesUsecase et le passait au BLoC
# (feature name_on_creation).
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/lib/src/presentation/wizard/bloc" "$R/$P/lib/src/presentation/wizard/view"
cat > "$R/$P/lib/src/presentation/wizard/bloc/wizard_bloc.dart" <<'EOF'
class WizardBloc {
  WizardBloc({required this.getNamesUsecase});
  final GetNamesUsecase getNamesUsecase;
}
EOF
cat > "$R/$P/lib/src/presentation/wizard/view/wizard_page.dart" <<'EOF'
// La page lit son BLoC, elle n'appelle pas GetNamesUsecase.
class WizardPage {}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "deps — use case dans le BLoC, commentaire dans la vue"
run_g "$R" deps x
expect_rc 0 "vert"
expect_no_out "wizard_page.dart" "le commentaire n'est pas signalé"

echo "deps — use case ajouté dans une vue"
cat >> "$R/$P/lib/src/presentation/wizard/view/wizard_page.dart" <<'EOF'
class WizardPageWithUsecase {
  WizardPageWithUsecase(this.getNamesUsecase);
  final GetNamesUsecase getNamesUsecase;
}
EOF
run_g "$R" deps x
expect_rc 1 "rouge"
expect_out "wizard_page.dart:5: vue → use case (GetNamesUsecase) interdit" "la ligne ajoutée est nommée"

finish
